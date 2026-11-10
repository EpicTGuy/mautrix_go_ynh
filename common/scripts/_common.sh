#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
# This file is the same in every mautrix Go bridge package (synced from mautrix_go_ynh).
# What is specific to one bridge lives in _bridge.sh.

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_bridge.sh"

binary="mautrix-$bridge"

# Settings written in config.yaml, with their default (name=default).
# The bridge-specific ones are in network_settings (_bridge.sh).
common_settings=(
    "personal_filtering_spaces=false"
    "enable_relaybot=true"
    "admin_only=true"
    "displayname=$bridge_display bridge bot"
    "listrelay=*"
    "async_media=false"
    "avatar=$bridge_avatar"
    "ephemeral_events=true"
    "username_template=$bridge_username_template"
    "delivery_receipts=false"
    "encryption_default=false"
    "encryption_require=false"
    "print_level=info"
)

# Settings that are booleans in config.yaml (older versions stored manifest answers as 1/0)
bool_settings=(encryption encryption_default encryption_require ephemeral_events delivery_receipts
               async_media personal_filtering_spaces enable_relaybot admin_only)

# Give every setting still empty its default value, and store it
set_default_settings() {
    local kv key
    for kv in "${common_settings[@]}" "${network_settings[@]}"; do
        key="${kv%%=*}"
        if [ -z "${!key:-}" ]; then
            printf -v "$key" '%s' "${kv#*=}"
            ynh_app_setting_set --key="$key" --value="${!key}"
        fi
    done
}

# For each setting <name>, <name>_yaml is its value ready to be put between single quotes in config.yaml
# (a quote is doubled), so that text like "Bot: #1" never breaks the YAML.
set_yaml_vars() {
    local kv key value
    for kv in "${common_settings[@]}" "${network_settings[@]}"; do
        key="${kv%%=*}"
        value="${!key:-}"
        printf -v "${key}_yaml" '%s' "${value//\'/\'\'}"
    done
}

# Write one value in config.yaml: write_yaml_value <dotted.path> <value> [raw]
# The value is written between single quotes (a quote doubled), unless "raw" (booleans, numbers).
# Used by the config panel: YunoHost's own writer turns ' into \', which is not valid YAML.
write_yaml_value() {
    YAML_VALUE="$2" python3 - "$install_dir/config.yaml" "$1" "${3:-}" <<'PY'
import os, re, sys
path, dotted, raw = sys.argv[1:4]
want = dotted.split(".")
value = os.environ["YAML_VALUE"].replace("\n", " ")
if raw != "raw":
    value = "'" + value.replace("'", "''") + "'"
lines = open(path).read().split("\n")
stack = []
for i, line in enumerate(lines):
    m = re.match(r"^( *)([A-Za-z_][A-Za-z0-9_]*):(\s.*)?$", line)
    if not m:
        continue
    depth = len(m.group(1)) // 4
    stack = stack[:depth] + [m.group(2)]
    if stack == want:
        comment = re.search(r"\s+#.*$", m.group(3) or "")
        lines[i] = f"{m.group(1)}{m.group(2)}: {value}" + (comment.group(0) if comment and raw == "raw" else "")
        break
else:
    sys.exit(f"{dotted} not found in {path}")
open(path, "w").write("\n".join(lines))
PY
}

# Allowed permission entries: "*", a server name or a Matrix ID
valid_permission_entry() {
    [[ "$1" == "*" || "$1" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ || "$1" =~ ^@[^:[:space:]\"\\]+:[A-Za-z0-9.-]+(:[0-9]+)?$ ]]
}

# 1/0/yes/no -> true/false, stored back if it changed
normalize_bool_settings() {
    local key value
    for key in "${bool_settings[@]}"; do
        value="${!key:-}"
        case "${value,,}" in
            1|yes|true) value="true" ;;
            0|no|false) value="false" ;;
            *) continue ;;
        esac
        if [ "${!key}" != "$value" ]; then
            printf -v "$key" '%s' "$value"
            ynh_app_setting_set --key="$key" --value="$value"
        fi
    done
}

get_synapse_db_name() {
	# Parameters: synapse instance identifier
	# Returns: database name
	ynh_app_setting_get --app="$1" --key=db_name
}

# Generate the appservice registration and reload Synapse
register_appservice() {
    chmod u+x "$install_dir/$binary"
    # Run as root to be able to write in /etc/matrix-...
    "$install_dir/$binary" -g -c "$install_dir/config.yaml" -r "/etc/matrix-$synapse_instance/app-service/$app.yaml"
    # config.yaml gets chown root:root by the command above
    chown "$app:$app" "$install_dir/config.yaml"
}

#=================================================
# CONFIG PANEL SETTERS
#=================================================

apply_permissions() {
    set -o noglob # Disable globbing to avoid expansions when passing * as value.
    declare values="list$role"
    newValues="${!values}" # Here we expand the dynamic variable we created in the previous line. ! Does the trick
    newValues="${newValues//\"}"
    # Split on commas only and trim surrounding whitespace, so that a value containing spaces
    # (e.g. a leftover placeholder sentence) is never split into several bogus entries.
    IFS=',' read -r -a rawArray <<< "$newValues"
    usersArray=()
    for user in "${rawArray[@]}"; do
        user="${user#"${user%%[![:space:]]*}"}"
        user="${user%"${user##*[![:space:]]}"}"
        [ -z "$user" ] && continue
        if valid_permission_entry "$user"; then
            usersArray+=("$user")
        else
            ynh_print_warn "Ignoring invalid entry '$user' for role $role (expected *, a server name or a Matrix ID)"
        fi
    done

    if [ ${#usersArray[@]} -gt 0 ]
    then
        # Only touch the "permissions:" block of the bridge section (it ends at the top-level "database:" key).
        allDefinedEntries=$(sed -n '/^    permissions:/,/^database:/p' "$install_dir/config.yaml" | sed '1d;$d' | sed '/^ *#/d' | grep -v -E ": \"?$role\"?$" | sed -E 's/^ *"?([^"]*)"?: .*/\1/')
        # Delete everything from the corresponding role to insert the new defined values. This way we also handle deletion of users.
        sed -i -E "/^    permissions:/,/^database:/{/: \"?$role\"?$/d;}" "$install_dir/config.yaml"
        for user in "${usersArray[@]}"
        do
            if grep -q -x -F "${user}" <<< "$allDefinedEntries"
            then
                ynh_print_info "User $user already defined in another role."
            else
                sed -i "/^    permissions:/a \        \\\"$user\\\": $role" "$install_dir/config.yaml" # Whitespaces are needed so that the file can be correctly parsed
            fi
        done
    fi
    set +o noglob

    ynh_print_info "Users with role $role added in $install_dir/config.yaml"
}

set__listuser() {
  role="user"
  ynh_app_setting_set --key=listuser --value="$listuser"
  apply_permissions
  ynh_store_file_checksum "$install_dir/config.yaml"
}

set__listrelay() {
  role="relay"
  ynh_app_setting_set --key=listrelay --value="$listrelay"
  apply_permissions
  ynh_store_file_checksum "$install_dir/config.yaml"
}

set__listadmin() {
  role="admin"
  ynh_app_setting_set --key=listadmin --value="$listadmin"
  apply_permissions
  ynh_store_file_checksum "$install_dir/config.yaml"
}
