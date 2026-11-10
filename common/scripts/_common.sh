#!/bin/bash

#=================================================
# COMMON VARIABLES AND CUSTOM HELPERS
#=================================================
# Same file in every mautrix Go bridge package (from mautrix_go_ynh), bridge specifics are in _bridge.sh

# shellcheck source=/dev/null
source "$(dirname "${BASH_SOURCE[0]}")/_bridge.sh"

binary="mautrix-$bridge"

# Settings written in config.yaml (name=default), the network ones are in _bridge.sh
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

bool_settings=(encryption encryption_default encryption_require ephemeral_events delivery_receipts
               async_media personal_filtering_spaces enable_relaybot admin_only)

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

# <setting>_yaml = value escaped for a double-quoted YAML string (used in conf/config.yaml)
set_yaml_vars() {
    local kv key value
    for kv in "${common_settings[@]}" "${network_settings[@]}"; do
        key="${kv%%=*}"
        value="${!key:-}"
        value="${value//\\/\\\\}"
        printf -v "${key}_yaml" '%s' "${value//\"/\\\"}"
    done
}

# Older versions stored booleans as 1/0
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

# "*", a server name or a Matrix ID
valid_permission_entry() {
    [[ "$1" == "*" || "$1" =~ ^[A-Za-z0-9.-]+(:[0-9]+)?$ || "$1" =~ ^@[^:[:space:]\"\\]+:[A-Za-z0-9.-]+(:[0-9]+)?$ ]]
}

get_synapse_db_name() {
	# Parameters: synapse instance identifier
	# Returns: database name
	ynh_app_setting_get --app="$1" --key=db_name
}

register_appservice() {
    chmod u+x "$install_dir/$binary"
    # As root to write in /etc/matrix-..., then config.yaml gets chown root:root
    "$install_dir/$binary" -g -c "$install_dir/config.yaml" -r "/etc/matrix-$synapse_instance/app-service/$app.yaml"
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
    # Split on commas only, trim spaces, skip invalid entries
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
