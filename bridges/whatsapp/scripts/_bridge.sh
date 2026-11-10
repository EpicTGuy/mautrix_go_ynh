#!/bin/bash
# What is specific to this bridge. Everything else comes from mautrix_go_ynh (common files).

bridge="whatsapp"                  # binary: mautrix-whatsapp
bridge_display="WhatsApp"
command_prefix="!wa"
bridge_avatar="mxc://maunium.net/NeXNQarUbrlYBiPCpprYsRqr"
bridge_username_template="whatsapp_{{.}}"
bridge_legacy_pickle_key="maunium.net/go/mautrix-whatsapp"   # used by versions < 0.11

# Network settings written in config.yaml (name=default)
network_settings=(
    'displayname_template={{or .BusinessName .PushName .Phone .RedactedPhone "Unknown user"}} (WA)'
    "disable_view_once=false"
    "os_name=Mautrix-WhatsApp bridge"
    "browser_name=unknown"
    "send_presence_on_typing=false"
    "url_previews=false"
)

# Migrations from older versions of this package (run at upgrade, before the defaults)
bridge_upgrade_compat() {
    # DB Backup missing because of wrong Upgrade from <=0.2.0
    if [ -z "${botname:-}" ]
    then
        botname=$(ynh_app_setting_get --key=whatsappbot)
        ynh_app_setting_set --key=botname --value="$botname"
    fi
}

# Bridge-specific handling of settings (install and upgrade, before the defaults)
bridge_init() {
    :
}

# Free-text config panel options written by our own setter (short key=dotted path in config.yaml)
panel_text_options=(
    "displayname_template=network.displayname_template"
    "os_name=network.os_name"
)
