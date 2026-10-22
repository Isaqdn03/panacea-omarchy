# Provenance

This plugin is a modified fork of **Panacea**, a Quickshell desktop shell by
EnsixD, redistributed under the terms of its MIT licence.

- **Upstream:** <https://github.com/EnsixD/Panacea>
- **Forked from:** commit `60d190b42f5b`, *"shell: bump version to 1.0.12"* (2026-09-01),
  with the local patches kept in the `main` branch of
  <https://github.com/Isaqdn03/panacea-omarchy>
- **Licence:** MIT, Copyright (c) 2026 EnsixD, reproduced verbatim in [`LICENSE`](LICENSE)

The upstream project is not affiliated with this fork and does not support it.

## What differs from upstream

The first commit of this branch imports the patched 1.0.12 tree unchanged
(`shell.qml` renamed to `Panacea.qml`). Everything after it is the Omarchy port:

- runs as an Omarchy shell **bar** plugin inside `omarchy-shell`, not as its own
  `qs -c panacea` process;
- settings are saved in Omarchy's own files (`~/.config/hypr/*.lua`,
  `~/.config/omarchy/shell.json`) through `scripts/hyprconf.py` and
  `scripts/omarchy-idle.sh`;
- colours follow the active Omarchy theme;
- Panacea is the session's notification daemon and OSD and answers Omarchy's
  `notifications` and `osd` IPC targets;
- uses Omarchy's lock screen, idle service and night light;
- adds a back arrow on every panel, and a modal for Settings / Files / media on
  the rail;
- removes the upstream updater, Panacea's own lock screen and features that do
  nothing on Omarchy.

See `git log` for the details of each change.

Files written for this fork: `BackButton.qml`, `SetWindows.qml`,
`scripts/hyprconf.py`, `scripts/omarchy-idle.sh`, `GithubView.qml`,
`scripts/github.sh`, `scripts/usage_brief.sh`, `scripts/glass.sh`.

## Omarchy

`companions/notifications/` starts as a copy of Omarchy's notifications plugin
(`shell/plugins/notifications`, Omarchy 4.5.0rc1), adopted with
`scripts/companions.sh adopt`. The lines Panacea changes are marked
`// panacea`; `PanaceaLook.qml` and `qmldir` are Panacea's. `upstream/` keeps
the Omarchy files each companion was last checked against.

- **Upstream:** <https://github.com/omacom/omarchy>
- **Licence:** MIT, Copyright (c) David Heinemeier Hansson
