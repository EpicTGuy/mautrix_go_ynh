#!/bin/bash
# Copy the common files and the bridge's own files into a package checkout.
#
#   tools/sync.sh <bridge> <package dir>        e.g. tools/sync.sh whatsapp ../mautrix_whatsapp_ynh
#
# Plain copies, except two files YunoHost wants in one piece:
#   conf/config.yaml   = bridges/<bridge>/conf/network.yaml + common/conf/config.yaml
#   config_panel.toml  = common/config_panel.toml + bridges/<bridge>/config_panel.network.toml
# manifest.toml, doc/, README*, tests.toml and LICENSE stay the package's own.
set -euo pipefail
bridge=$1
pkg=$(cd "$2" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)
b="$root/bridges/$bridge"
[ -f "$b/scripts/_bridge.sh" ] || { echo "unknown bridge: $bridge" >&2; exit 1; }

mkdir -p "$pkg/scripts" "$pkg/conf"
# common files (config.yaml and config_panel.toml are assembled below)
(cd "$root/common" && find . -type f ! -path ./conf/config.yaml ! -path ./config_panel.toml -print0) |
    while IFS= read -r -d '' f; do
        mkdir -p "$pkg/$(dirname "$f")"
        cp "$root/common/$f" "$pkg/$f"
    done
cp "$b/scripts/_bridge.sh" "$pkg/scripts/_bridge.sh"
cat "$b/conf/network.yaml" "$root/common/conf/config.yaml" > "$pkg/conf/config.yaml"
cat "$root/common/config_panel.toml" "$b/config_panel.network.toml" > "$pkg/config_panel.toml"
chmod +x "$pkg"/scripts/{install,upgrade,remove,backup,restore,config}
echo "synced $bridge -> $pkg"
