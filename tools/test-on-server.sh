#!/bin/bash
# Run as root on a test YunoHost server with Synapse.
#
#   DOMAIN=<synapse server name> tools/test-on-server.sh <bridge> <official package dir> <synced package dir>
#
# 1. install the official package, change settings in the config panel
# 2. upgrade to the synced package (twice): settings kept, config valid, bridge running
# 3. backup / remove / restore
# 4. remove, fresh install of the synced package, config panel still works
# Telegram needs API_ID and API_HASH in the environment.
set -u
n=$1; OLD=$2; NEW=$3
DOMAIN=${DOMAIN:?set DOMAIN to the Synapse server name}
app=mautrix_$n; c=/var/www/$app/config.yaml
FAIL=0; ok() { echo "  OK  $*"; }; ko() { echo "  KO  $*"; FAIL=1; }
log=/root/gotest-$n.log; : > "$log"
run() { "$@" >>"$log" 2>&1; }
setting() { yunohost app setting "$app" "$1" 2>/dev/null; }
yaml_ok() { python3 -c "import yaml; yaml.safe_load(open('$c'))" 2>/dev/null; }
active() { sleep 8; systemctl is-active --quiet "$app" && ok "$1: bridge running" || { ko "$1: bridge not running"; journalctl -u "$app" -n 15 --no-pager; }; }
cfg() { python3 - "$c" "$1" <<'EOF'
import sys, yaml
v = yaml.safe_load(open(sys.argv[1]))
for k in sys.argv[2].split('.'):
    v = v[k]
print(v)
EOF
}
perms() { python3 -c "import yaml; p=yaml.safe_load(open('$c'))['bridge']['permissions']; print(' '.join(f'{k}={v}' for k,v in sorted(p.items())))"; }
args="synapse_instance=synapse&botname=${n}bot&encryption=1&botadmin=@admin:$DOMAIN&botusers=$DOMAIN&enable_relaybot=1"
[ "$n" = telegram ] && args="$args&api_id=${API_ID:?}&api_hash=${API_HASH:?}"

echo "### $n: official package"
yunohost app remove "$app" --purge >>"$log" 2>&1
run yunohost app install "$OLD" -a "$args" --force || { ko "official install failed (see $log)"; exit 1; }
active official
run yunohost app config set "$app" main.permissions.listuser -v "$DOMAIN, @alice:example.org"
run yunohost app config set "$app" main.bot.displayname -v "Robot de test"
run yunohost app config set "$app" main.bridge -a "enable_relaybot=true&admin_only=false"
case $n in
    whatsapp) run yunohost app config set "$app" advanced.network.os_name -v "Test OS" ;;
    signal) run yunohost app config set "$app" advanced.network.location_format -v "https://www.google.com/maps/place/%[1]s,%[2]s" ;;
esac
p_before=$(perms); pickle_before=$(cfg encryption.pickle_key)
echo "  permissions: $p_before"

echo "### $n: upgrade to the synced package"
run yunohost app upgrade "$app" -F -f "$NEW" || ko "upgrade failed (see $log)"
yaml_ok && ok "config.yaml valid" || ko "config.yaml invalid"
active upgrade
[ "$(perms)" = "$p_before" ] && ok "permissions kept" || ko "permissions changed: $(perms)"
[ "$(cfg encryption.pickle_key)" = "$pickle_before" ] && ok "pickle key kept" || ko "pickle key changed"
[ "$(cfg appservice.bot.displayname)" = "Robot de test" ] && ok "bot display name kept" || ko "bot display name: $(cfg appservice.bot.displayname)"
[ "$(cfg bridge.relay.admin_only)" = False ] && ok "admin_only kept" || ko "admin_only: $(cfg bridge.relay.admin_only)"
[ "$(cfg encryption.allow)" = True ] && ok "encryption is a boolean true" || ko "encryption: $(cfg encryption.allow)"
case $n in
    whatsapp) [ "$(cfg network.os_name)" = "Test OS" ] && ok "network setting kept" || ko "os_name: $(cfg network.os_name)" ;;
    telegram) [ "$(cfg network.api_id)" = "$API_ID" ] && ok "api_id kept" || ko "api_id changed" ;;
esac
grep -q '__[A-Z_]*__' "$c" && ko "placeholder left in config.yaml" || ok "no placeholder left"
cmd=$(cfg bridge.command_prefix); echo "  command prefix: $cmd"
cfg1=$(cat "$c")
run yunohost app upgrade "$app" -F -f "$NEW" || ko "2nd upgrade failed"
# appservice tokens are regenerated at each upgrade, and the secrets left to "generate" are recreated by the bridge (as before)
other=$(diff <(echo "$cfg1") "$c" | grep '^[<>]' | grep -vcE '(_token|shared_secret|signing_key|server_key): ')
[ "$other" = 0 ] && ok "2nd upgrade: config unchanged (except tokens and generated secrets)" || ko "2nd upgrade changed $other lines"
active "2nd upgrade"

echo "### $n: backup / restore"
run yunohost backup create --apps "$app" -n "gotest-$n" && ok backup || ko backup
run yunohost app remove "$app" --purge
run yunohost backup restore "gotest-$n" --apps "$app" --force && ok restore || ko "restore (see $log)"
[ "$(stat -c %U /var/log/$app)" = "$app" ] && ok "log dir owned by $app" || ko "log dir owned by $(stat -c %U /var/log/$app)"
active restore
[ "$(perms)" = "$p_before" ] && ok "permissions kept after restore" || ko "permissions after restore: $(perms)"
run yunohost backup delete "gotest-$n"

echo "### $n: fresh install of the synced package"
run yunohost app remove "$app" --purge
run yunohost app install "$NEW" -a "$args" --force || { ko "fresh install failed (see $log)"; exit 1; }
yaml_ok && ok "config.yaml valid" || ko "config.yaml invalid"
active install
[ "$(setting enable_relaybot)" = true ] && ok "booleans stored as true/false" || ko "enable_relaybot setting: $(setting enable_relaybot)"
run yunohost app config set "$app" main.permissions.listadmin -v "@admin:$DOMAIN, @bob:example.org"
perms | grep -q '@bob:example.org=admin' && ok "config panel: permissions" || ko "config panel permissions: $(perms)"
run yunohost app config set "$app" main.bot.botname -v "${n}bot2"
[ "$(cfg appservice.bot.username)" = "${n}bot2" ] && ok "config panel: bot name" || ko "bot name: $(cfg appservice.bot.username)"
active "panel changes"
echo "  exposure: $(systemd-analyze security "$app" 2>/dev/null | tail -1)"
echo "### $n: $([ $FAIL = 0 ] && echo ALL OK || echo FAILURES)"
