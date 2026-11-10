# Security and reliability review (November 2026)

Scope: `common/`, `bridges/*`, `tools/` and the draft workflow, and the three packages they produce
(WhatsApp, Telegram, Signal), compared with the current YunoHost-Apps packages (`testing` branches).

## Method

1. **Threat model.** Assets: network sessions, messages, appservice tokens, pickle key (encrypts the e2ee keys
   in the bridge database), Telegram API hash, database password. Attackers: another local system account,
   leaks through YunoHost logs (readable by local accounts, shareable with `yunohost log share`) or leftover
   files, admin mistakes in the config panel, supply chain (upstream example configs, GitHub actions).
2. **Static analysis.** shellcheck on every script; line-by-line reading of the scripts, with the panel values and
   install answers as entry points (they end up in `config.yaml` through templates, `sed` and the panel binds).
3. **Secrets.** Real values of the pickle key, database password and API hash looked up in the YunoHost
   operation logs (without printing them); git history checked for tokens and personal data.
4. **Real runs on a test server.** File modes, listening ports, systemd exposure, crafted panel values
   followed by an upgrade, full cycles official package → synced package (see `tools/test-on-server.sh`).

## Findings

| # | Severity | Finding | Status |
|---|---|---|---|
| 1 | **High** (reliability) | A permission entry with a backslash (`@a:b\x`) is written inside double quotes in `config.yaml`: invalid YAML. The next upgrade fails, YunoHost's safety restore fails too (the backup already holds the bad value) and **the app is removed**. Reproduced with the current packages. | **Fixed**: entries must be `*`, a server name or a Matrix ID; the panel refuses others, install/upgrade skip them with a warning (e.g. the old default "Your main Matrix account") |
| 2 | Medium | Free text in the panel (bot display name, avatar, WhatsApp device name...) is written raw in the template: `Robot: test` or `x: y` makes `config.yaml` invalid (at once for the avatar, at the next upgrade for the display name). | **Fixed**: those values are written between single quotes (quote doubled); avatar must be `remove` or `mxc://…`; bot name `^[a-z0-9._=-]+$`; display name on one line; Telegram API ID numeric |
| 2b | Medium | The config panel's own writer (`ynh_write_var_in_file`) turns `'` into `\'`, invalid in a single-quoted YAML string: "Robot d'Alice" breaks `config.yaml`. It also handles only one `>` level: a fixed `bridge>relay>enabled` bind would have overwritten the `relay:` line. | **Fixed**: text options and the relay switch use our own setter (`write_yaml_value`, exact key path, proper quoting) |
| 2c | Medium | Network options of the panel (contact name template, view-once...) were written only in `config.yaml`, which upgrades rebuild from the template: **lost at every upgrade**. | **Fixed**: kept as settings, put back by the template |
| 3 | Medium | Telegram `api_hash` in clear in the YunoHost operation logs (11 logs on the test server): YunoHost only redacts setting names ending in `key`, `pwd`, `token`, `secret`... | **Fixed**: stored as `api_hash_key` (migrated at upgrade); the install question should become `type = "password"` in the package manifest |
| 4 | Medium | Copies of `config.yaml` (secrets included) kept by YunoHost in `/var/cache/yunohost/appconfbackup` stay after removal; their owner UID is given to the next app user created. | **Fixed**: `remove` deletes them. YunoHost core issue, to report |
| 5 | Medium | Restore left `/var/log/<app>` to root: the bridge could not start. | **Fixed** |
| 6 | Low | Changing the bot name: string compared with `-eq`, and `sed` replaced every `username:` line of the file. | **Fixed** |
| 7 | Low | Config panel shows "relay mode allowed: no" while it is on (`relay>enabled` did not match); WhatsApp-only options shown for Telegram/Signal. | **Fixed** |
| 8 | Low | Workflow: actions referenced by a movable tag. | **Fixed**: pinned by commit SHA. The sync token should be limited to the three package repositories |
| 9 | Info | `tools/update_config.py` reads the upstream example configs at a release tag over HTTPS. Nothing is executed; the result is a diff to read before committing. A `__WORD__` in an upstream text would make install stop (fails closed). | Accepted |
| 10 | Info | systemd exposure 3.6 (same as today). The units could be hardened further (`ProtectProc`, `RestrictAddressFamilies`, `CapabilityBoundingSet=`…: 1.3 on other bridges). | Proposed separately |
| 12 | Info | A contact name template using a field the bridge does not have is accepted by the panel; the bridge refuses it at the next start / upgrade (the upgrade stops and YunoHost restores the previous version, checked). | Accepted (the bridge is the only one that knows its fields) |
| 11 | Info | Secrets left to `generate` (provisioning, media keys) are recreated by the bridge after each upgrade (same as today). | Accepted |

Checked without findings: bridges listen on 127.0.0.1 only; `config.yaml` 600 app:app; appservice registrations
600 synapse; settings 400 root; logs 600; pickle key and database password in no operation log; no secret or
personal data in the git history.
