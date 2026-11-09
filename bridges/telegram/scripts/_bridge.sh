#!/bin/bash
# What is specific to this bridge. Everything else comes from mautrix_go_ynh (common files).

bridge="telegram"                  # binary: mautrix-telegram
bridge_display="Telegram"
command_prefix="!tg"
bridge_avatar="mxc://maunium.net/tJCRmUyJDsgRNgqhOgoiHWbX"
bridge_username_template="telegram_{{.}}"
bridge_legacy_pickle_key="mautrix.bridge.e2ee"   # used by versions < 0.11

# Network settings written in config.yaml (name=default).
# api_id and api_hash are install questions: their default is only used if they are missing.
network_settings=(
    "api_id="
    "api_hash="
    "device_model=mautrix-telegram"
)

# Migrations from older versions of this package (run at upgrade, before the defaults)
bridge_upgrade_compat() {
    # We may have leftover files from the Python bridge version. This step tries to clean them up.
    # The version check is here to only run this cleanup step once. The version it checks for is the version
    # this cleanup was introduced in.
    if ynh_app_upgrading_from_version_before 0.2512.0~ynh1
    then
        ynh_print_info --message="Cleaning up possible leftovers from python bridge version"
        for target in bin include lib lib64 pyvenv.cfg share src .python_history example-config.yaml
        do
            ynh_safe_rm --file="${install_dir:?}/$target"
        done
    fi

    # Settings of the Python bridge
    if [ -z "${botname:-}" ]
    then
        botname="$(ynh_app_setting_get --key=bot_username)"
        ynh_app_setting_set --key=botname --value="$botname"
        ynh_app_setting_delete --key=bot_username
    fi
    if [ -z "${port:-}" ]
    then
        port=$(ynh_app_setting_get --key=listen_port)
        ynh_app_setting_set --key=port --value="$port"
        ynh_app_setting_delete --key=listen_port
    fi
    if [ -z "${api_id:-}" ]
    then
        api_id=$(ynh_app_setting_get --key=apiid)
        ynh_app_setting_set --key=api_id --value="$api_id"
        ynh_app_setting_delete --key=apiid
    fi
    if [ -z "${api_hash:-}" ]
    then
        api_hash=$(ynh_app_setting_get --key=apihash)
        ynh_app_setting_set --key=api_hash --value="$api_hash"
        ynh_app_setting_delete --key=apihash
    fi
    if [ -z "${displayname:-}" ]
    then
        displayname=$(ynh_app_setting_get --key=bot_displayname)
        [ -n "$displayname" ] && ynh_app_setting_set --key=displayname --value="$displayname"
        ynh_app_setting_delete --key=bot_displayname
    fi
    if [ -z "${listrelay:-}" ]
    then
        listrelay=$(ynh_app_setting_get --key=listrelaybot)
        [ -n "$listrelay" ] && ynh_app_setting_set --key=listrelay --value="$listrelay"
        ynh_app_setting_delete --key=listrelaybot
    fi
    if [ -z "${avatar:-}" ]
    then
        avatar=$(ynh_app_setting_get --key=bot_avatar)
        [ -n "$avatar" ] && ynh_app_setting_set --key=avatar --value="$avatar"
        ynh_app_setting_delete --key=bot_avatar
    fi
    # The Go bridge keeps the Python bridge's ghost users: the template can't change
    username_template="telegram_{{.}}"
    ynh_app_setting_set --key=username_template --value="$username_template"

    for key in telegram_link_preview enable_metrics alias_template displayname_template \
               is_encryption_enabled listpuppeting listfull bottoken
    do
        ynh_app_setting_delete --key=$key
    done
}
