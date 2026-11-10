#!/usr/bin/env python3
"""Rebuild the config.yaml templates from the official mautrix example configs (issue mautrix_telegram_ynh#91).

  tools/update_config.py <bridge> <version>      e.g. tools/update_config.py whatsapp v0.2610.0

Writes:
  bridges/<bridge>/conf/network.yaml   the "network:" part, from pkg/connector/example-config.yaml of the bridge
  common/conf/config.yaml              everything else, from bridgev2/matrix/mxmain/example-config.yaml of
                                       mautrix-go, at the version required by the bridge's go.mod

YunoHost values are put in place of the example ones:
  - common keys: COMMON below (the same for every bridge);
  - network keys: bridges/<bridge>/network.toml, table [placeholders] ("key.path" = "__VALUE__").
Comments and every other value are kept as upstream wrote them, so a diff after an upstream release shows
exactly what changed upstream.
"""
import re, sys, tomllib, urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# (path of the key in the example config) -> value written in the template
COMMON = {
    ('bridge', 'command_prefix'): '"__COMMAND_PREFIX__"',
    ('bridge', 'personal_filtering_spaces'): '__PERSONAL_FILTERING_SPACES__',
    ('bridge', 'bridge_matrix_leave'): 'false',
    ('bridge', 'relay', 'enabled'): '__ENABLE_RELAYBOT__',
    ('bridge', 'relay', 'admin_only'): '__ADMIN_ONLY__',
    ('database', 'uri'): 'postgres://__APP__:__DB_PWD__@localhost:5432/__DB_NAME__?sslmode=disable',
    ('homeserver', 'address'): 'https://__DOMAIN__',
    ('homeserver', 'domain'): '__SERVER_NAME__',
    ('homeserver', 'async_media'): '__ASYNC_MEDIA__',
    ('appservice', 'address'): 'http://localhost:__PORT__',
    ('appservice', 'port'): '__PORT__',
    ('appservice', 'id'): '__APP__',
    ('appservice', 'bot', 'username'): '__BOTNAME__',
    ('appservice', 'bot', 'displayname'): "'__DISPLAYNAME_YAML__'",
    ('appservice', 'bot', 'avatar'): "'__AVATAR_YAML__'",
    ('appservice', 'ephemeral_events'): '__EPHEMERAL_EVENTS__',
    ('appservice', 'username_template'): "'__USERNAME_TEMPLATE_YAML__'",
    ('matrix', 'delivery_receipts'): '__DELIVERY_RECEIPTS__',
    ('encryption', 'allow'): '__ENCRYPTION__',
    ('encryption', 'default'): '__ENCRYPTION_DEFAULT__',
    ('encryption', 'require'): '__ENCRYPTION_REQUIRE__',
    ('encryption', 'pickle_key'): '__PICKLE_KEY__',
    ('logging', 'min_level'): '__PRINT_LEVEL__',
}
PERMISSIONS = ['        "__LISTRELAY__": "relay"', '        "__LISTUSER__": "user"', '        "__LISTADMIN__": "admin"']
LOGFILE = '/var/log/__APP__/__APP__.log'


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read().decode()


def replace_keys(text, mapping, indent=0):
    """Replace the values of the keys of `mapping` (tuple paths); returns (text, keys found)."""
    out, stack, seen, in_perms = [], [], set(), False
    for line in text.splitlines():
        if in_perms:
            if re.match(r'^        \S', line):
                continue  # example permissions, replaced by ours
            in_perms = False
        m = re.match(r'^( *)([A-Za-z_][A-Za-z0-9_]*):(.*)$', line)
        if m:
            depth = (len(m.group(1)) - indent) // 4
            stack = stack[:depth] + [m.group(2)]
            path = tuple(stack)
            if path == ('bridge', 'permissions') and indent == 0:
                out.append(line)
                out.extend(PERMISSIONS)
                in_perms = True
                continue
            if path in mapping:
                comment = re.search(r'\s+#.*$', m.group(3))
                line = f'{m.group(1)}{m.group(2)}: {mapping[path]}' + (comment.group(0) if comment else '')
                seen.add(path)
        if re.match(r'^ +filename: \./logs/', line):
            line = re.sub(r'filename: .*', f'filename: {LOGFILE}', line)
        out.append(line)
    return '\n'.join(out) + '\n', seen


def main(bridge, version):
    repo = f'https://raw.githubusercontent.com/mautrix/{bridge}/{version}'
    net_conf = tomllib.loads((ROOT / 'bridges' / bridge / 'network.toml').read_text())
    gomod = fetch(f'{repo}/go.mod')
    go_version = re.search(r'^\s*maunium\.net/go/mautrix (v\S+)', gomod, re.M).group(1)

    # network part: the bridge's example, indented under "network:"
    example = fetch(f'{repo}/{net_conf.get("example", "pkg/connector/example-config.yaml")}')
    network = '\n'.join(('    ' + l) if l.strip() else '' for l in example.rstrip('\n').splitlines())
    placeholders = {tuple(['network'] + k.split('.')): v for k, v in net_conf.get('placeholders', {}).items()}
    network, seen = replace_keys('# Network-specific config options\nnetwork:\n' + network, placeholders)
    missing = set(placeholders) - seen
    assert not missing, f'{bridge}: network keys not found upstream: {sorted(missing)}'
    out = ROOT / 'bridges' / bridge / 'conf' / 'network.yaml'
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(network + '\n')

    # common part: mautrix-go's example
    common = fetch(f'https://raw.githubusercontent.com/mautrix/go/{go_version}/bridgev2/matrix/mxmain/example-config.yaml')
    common, seen = replace_keys(common, COMMON)
    missing = set(COMMON) - seen
    assert not missing, f'mautrix-go {go_version}: keys not found: {sorted(missing)}'
    assert LOGFILE in common
    (ROOT / 'common' / 'conf').mkdir(parents=True, exist_ok=True)
    (ROOT / 'common' / 'conf' / 'config.yaml').write_text(common)
    print(f'{bridge} {version}: network.yaml written; common config.yaml from mautrix-go {go_version}')


if __name__ == '__main__':
    main(*sys.argv[1:3])
