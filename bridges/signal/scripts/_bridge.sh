#!/bin/bash
# What is specific to this bridge. Everything else comes from mautrix_go_ynh (common files).

bridge="signal"                    # binary: mautrix-signal
bridge_display="Signal"
command_prefix="!signal"
bridge_avatar="mxc://maunium.net/wPJgTQbZOtpBFmDNkiNEMDUp"
bridge_username_template="signal_{{.}}"   # older installs use sg_{{.}}, see bridge_upgrade_compat
bridge_legacy_pickle_key="mautrix.bridge.e2ee"   # used by versions < 0.11

# Network settings written in config.yaml (name=default)
network_settings=(
    'displayname_template={{or .ProfileName .AboutEmoji "Unknown user"}} (SG)'
    "device_name=mautrix-signal"
    "note_to_self_avatar=mxc://maunium.net/REBIVrqjZwmaWpssCZpBlmlL"
    'location_format=https://www.openstreetmap.org/?mlat=%[1]s&mlon=%[2]s'
)

# Migrations from older versions of this package (run at upgrade, before the defaults)
bridge_upgrade_compat() {
    # We may have leftover files from the Python bridge version. This step tries to clean them up.
    # The version check is here to only run this cleanup step once. The version it checks for is the version
    # this cleanup was introduced in.
    if ynh_app_upgrading_from_version_before 0.8.4~ynh2
    then
        ynh_print_info --message="Cleaning up possible leftovers from python bridge version"
        for target in bin include lib lib64 pyvenv.cfg share src .python_history example-config.yaml
        do
            ynh_safe_rm --file="${install_dir:?}/$target"
        done
    fi

    # Between november 2024 to february 2025 the username_template was set to signal_{{.}}
    # This change broke previous installed instance which was declared with sg_{{.}}
    # Upstream doesn't allow to change this var, so we need to support both now.
    # See https://github.com/YunoHost-Apps/mautrix_signal_ynh/pull/140
    if [ -z "${username_template:-}" ]
    then
        # Check if any user was created with the old "sg_" prefix
        # First, check if the mx_registrations table exists: if not, no users have been created
        ret=$(sudo -u postgres psql --dbname="$db_name" -q -t -c "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'mx_registrations');")
        if [ "$ret" = " t" ]
        then # The table exists, check for users
            ret=$(sudo -u postgres psql --dbname="$db_name" -q -t -c "SELECT EXISTS(SELECT 1 FROM mx_registrations WHERE user_id LIKE '@sg_%');")
        fi
        if [ "$ret" = " t" ]
        then # At least one @sg_* user exists in the database
            username_template="sg_{{.}}"
        else # The table does not exist, or no users named "@sg_*"
            username_template="signal_{{.}}"
        fi
        ynh_print_info "Detected username template $username_template from the database, saving it in settings"
        ynh_app_setting_set --key=username_template --value="$username_template"
    fi
}

# Bridge-specific handling of settings (install and upgrade, before the defaults)
bridge_init() {
    :
}

# Config panel validators (scripts/config): text written in config.yaml
validate__displayname_template() { check_text "$displayname_template"; }
validate__device_name() { check_text "$device_name"; }
validate__note_to_self_avatar() { check_text "$note_to_self_avatar"; }
validate__location_format() { check_text "$location_format"; }
