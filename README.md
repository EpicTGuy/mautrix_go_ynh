# mautrix_go_ynh

Shared files of the YunoHost packages of the [mautrix](https://github.com/mautrix) bridges written in Go
(bridgev2): WhatsApp, Telegram, Signal for now. A fix made here goes to every package; what is specific to a
bridge stays small and in one place.

Follow-up of [mautrix_telegram_ynh#90](https://github.com/YunoHost-Apps/mautrix_telegram_ynh/issues/90)
(one parent for the Go bridges) and [#91](https://github.com/YunoHost-Apps/mautrix_telegram_ynh/issues/91)
(config.yaml rebuilt from the upstream example configs).

## Layout

| | |
|---|---|
| `common/` | copied as is into every package: `scripts/*`, `conf/systemd.service`, common part of `conf/config.yaml` and of `config_panel.toml`, `.github/` |
| `bridges/<bridge>/scripts/_bridge.sh` | the bridge's names, defaults, network settings and upgrade migrations (~30 lines) |
| `bridges/<bridge>/conf/network.yaml` | the `network:` part of `config.yaml` |
| `bridges/<bridge>/config_panel.network.toml` | the bridge's own config panel options |
| `bridges/<bridge>/network.toml` | which values of the upstream network example are replaced by YunoHost ones |
| `tools/sync.sh <bridge> <package dir>` | copies all that into a package checkout |
| `tools/update_config.py <bridge> <version>` | rebuilds `network.yaml` and the common `config.yaml` from the upstream examples |
| `tools/test-on-server.sh` | full test cycle on a test server (see below) |

Each package keeps its own `manifest.toml`, `doc/`, `README*`, `tests.toml` and `LICENSE`: the YunoHost
autoupdater keeps updating the version and the binaries in the manifest, as today.

`conf/config.yaml` and `config_panel.toml` are the only files made of two parts (YunoHost wants them in one
piece): `network.yaml` + common `config.yaml`, common `config_panel.toml` + `config_panel.network.toml`.
Everything else is a plain copy.

## How the scripts use `_bridge.sh`

`_common.sh` sources `_bridge.sh`, which sets `bridge`, `bridge_display`, `command_prefix`, the default avatar
and username template, the network settings with their defaults, and `bridge_upgrade_compat()` (migrations
from older versions of that package: Python leftovers and setting renames for Telegram, `sg_` prefix detection
for Signal...). Install and upgrade then do the same thing for every bridge: every setting written in
`config.yaml` is stored, and any setting still empty gets its default.

## Changes compared to the current packages

Everything the packages did is kept (same settings, same names, same migrations). On top of that:

- `apply_permissions` splits on commas only and stays inside the `permissions:` block; settings are quoted
  (same as the open PRs WhatsApp #207, Telegram #101, Signal #197).
- Booleans stored as 1/0 by older versions are converted to true/false at upgrade (WhatsApp #212, Telegram #103,
  Signal #198); at install, the "enable relay" answer is now used (it was always forced to true).
- The pickle key check from Signal (read back the key in use before rewriting config.yaml) now protects
  every bridge.
- Restore gives `/var/log/<app>` back to the app user (it was left to root and the bridge could not start).
- Config panel: "Relay mode allowed?" showed "no" while relay mode was on (`relay>enabled` did not match,
  now `bridge>relay>enabled`); the WhatsApp-only options (presence on typing, URL previews) are no longer shown
  for Telegram and Signal, whose config has no such keys; Signal's "disappear view-once" option is gone,
  upstream removed it; changing the bot name only rewrites the bot's `username:` line.
- Config panel values are checked (permission entries, avatar, bot name, API ID) and text is written as valid
  YAML (an apostrophe or a `: ` broke `config.yaml`; a bad permission entry could even get the app removed by a
  failed upgrade). Network options of the panel are kept across upgrades (they were lost).
- Telegram's API hash is stored as `api_hash_key`, a name YunoHost hides in its logs (it was in clear); the
  install question should be `type = "password"` in the manifest.
- `remove` deletes the copies of `config.yaml` YunoHost keeps in `/var/cache/yunohost/appconfbackup`.
- See [SECURITY-REVIEW.md](SECURITY-REVIEW.md).
- `config.yaml` follows mautrix-go v0.32.0 / bridges v0.2610.0 (new upstream options were missing).
- Signal: the `sg_` prefix detection now really looks for `@sg_` users (the first query compared `t` with
  psql's ` t`, so any database with the table got `sg_`).
- `bridge_matrix_leave: false` for Signal too (already the case for WhatsApp and Telegram).

## Updating

New upstream release:

```sh
tools/update_config.py whatsapp v0.2611.0    # rebuild the templates, then read the diff: it is the upstream change
tools/sync.sh whatsapp ../mautrix_whatsapp_ynh
```

A change in the YunoHost logic: edit `common/`, then sync every package. A GitHub action
(`.github/workflows/sync.yml`, draft) can do the sync and open one PR per package.

## Tests

`DOMAIN=<server name> tools/test-on-server.sh <bridge> <official package> <synced package>` (as root, Telegram
also needs `API_ID` and `API_HASH`): install of the official package and settings changed in the config panel,
upgrade to the synced package twice (settings, permissions and pickle key kept, valid config, bridge running),
backup / removal / restore, fresh install and config panel changes.
