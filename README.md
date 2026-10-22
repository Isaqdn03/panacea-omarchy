# Panacea for Omarchy

Panacea's rail and drawer as the Omarchy bar. This is a fork of
[EnsixD/Panacea](https://github.com/EnsixD/Panacea) (MIT, see [NOTICE](NOTICE.md))
that runs as a `bar` plugin inside `omarchy-shell`. It saves its settings in
Omarchy's own files and uses Omarchy's services wherever Omarchy has one.

This branch, `omarchy-4.5`, needs Omarchy 4.5 (built on 4.5.0rc1 with Hyprland
0.56 and Quickshell 0.3.2). The `omarchy-plugin` branch is the Omarchy 4.0 version
and stays the default until 4.5 is final.

## Install

```bash
# Clones into ~/.config/omarchy/plugins/isaqdn.panacea and makes it the bar.
omarchy plugin add https://github.com/Isaqdn03/panacea-omarchy.git --enable
# Until Omarchy 4.5 is final, switch to this branch:
git -C ~/.config/omarchy/plugins/isaqdn.panacea switch omarchy-4.5

# Panacea draws the OSD and the notifications; turn off Omarchy's.
omarchy plugin disable omarchy.osd
omarchy plugin disable omarchy.notifications

# The companions (see below), and the health check after every update.
~/.config/omarchy/plugins/isaqdn.panacea/scripts/companions.sh install
omarchy plugin enable isaqdn.panacea-osd
~/.config/omarchy/plugins/isaqdn.panacea/scripts/health.sh install

omarchy restart shell
```

Update with `omarchy plugin update isaqdn.panacea`. It shows the diff, then
fast-forwards the checkout. Run `scripts/companions.sh install` afterwards if
the health check says a companion is out of date.

To go back to Omarchy's bar, run `omarchy bar use omarchy.bar`, then
`omarchy plugin disable isaqdn.panacea-osd`, `omarchy plugin enable omarchy.osd`
and `omarchy plugin enable omarchy.notifications`, then `omarchy restart shell`.

**NVIDIA.** Qt only enables its threaded render loop for Mesa and Mali drivers.
Everywhere else Qt Quick animations tick at about 60 fps, even on a high-refresh
screen. Add this to `~/.config/hypr/hyprland.lua`, then reload Hyprland and restart
the shell:

```lua
hl.env("QSG_RENDER_LOOP", "threaded")
```

## Where things live

| What | Where |
| --- | --- |
| Code (this repo) | `~/.config/omarchy/plugins/isaqdn.panacea/` |
| Panacea's own settings and state | `~/.config/panacea/settings.json`, `.vibrance` |
| Backups of Hyprland files it edits | `~/.local/state/panacea/hypr-backups/` |
| The last health check's report | `~/.local/state/panacea/health/report.txt` |

State must stay outside the plugin folder. `omarchy-shell` reloads every plugin
whenever a file under `~/.config/omarchy/plugins` is written.

## Settings write Omarchy's files

| Settings page | Saved to |
| --- | --- |
| Display (resolution, refresh, scale, rotation, position, VRR) | `~/.config/hypr/monitors.lua`, that output's own `hl.monitor()` line |
| Mouse & Keyboard | `~/.config/hypr/input.lua` |
| Windows (gaps, borders, rounding, dimming, animations), vibrance | `~/.config/hypr/looknfeel.lua` |
| Idle & Lock | `idle.screensaver` / `idle.lock` in `~/.config/omarchy/shell.json` |
| Shortcuts | the `panacea-omarchy` block in `~/.config/hypr/bindings.lua` |
| Wallpapers | Omarchy's backgrounds for the current theme (`omarchy-theme-bg-set`) |

`scripts/hyprconf.py` edits values in place and keeps your comments. If
`hyprctl configerrors` reports a problem after a reload, it puts the file back.

## Working with Omarchy

- **Theme:** the default "Omarchy" theme takes its colours live from the active
  Omarchy theme. The background matches the terminals: the `background` in the
  theme's `kitty.conf`, else `colors.toml`.
- **IPC:** Panacea answers Omarchy's `osd` and `notifications` IPC targets, so
  `omarchy-osd`, the SUPER + , keys and notification silencing all keep working.
  The volume, brightness and media keys reach the OSD another way since 4.5;
  the `osd` companion covers them.
- **Services:** Coffee mode is Omarchy's stay-awake, and lock is
  `omarchy-system-lock`. Night light is Omarchy's.
- **Its own IPC:** `omarchy-shell pill <method>`, e.g. `peek`, `controls`,
  `settingsAt display`, `back`, `current`.
- **Glass mode:** `scripts/glass.sh` (Control Center row, SUPER + SHIFT + T)
  switches Hyprland's blur and the terminals' transparency together. Off writes
  `panacea-glass.conf` next to each terminal's config, pinning its background
  opacity to 1; on removes it, so the terminal's own opacity applies. Each
  terminal has to include it below its own opacity line: `globinclude
  panacea-glass.conf` in `kitty.conf` (with `dynamic_background_opacity yes`),
  `config-file = ?"~/.config/ghostty/panacea-glass.conf"` in ghostty's `config`.

## Companions

A companion is a small plugin that takes one of Omarchy's own plugin slots and
hands its work to Panacea. Its manifest names the Omarchy plugin it stands in
for (`"omarchy": {"clonedFrom": "omarchy.osd"}`), and the shell then sends that
plugin's calls to the companion. Omarchy keeps the service; Panacea draws it.

| Companion | Stands in for | What it does |
| --- | --- | --- |
| `isaqdn.panacea-osd` | `omarchy.osd` | Sends the volume, brightness and media pop-ups to Panacea's rail |

Each one lives in `companions/<name>/` and is installed as its own plugin folder
by `scripts/companions.sh install`: Omarchy only loads plugins at the top level
of `~/.config/omarchy/plugins`, and refuses a symlinked one. Edit the copy in
this repo, then install it.

## Health check

`scripts/health.sh check` checks that Panacea still fits the Omarchy installed
now. It confirms that:

- Panacea is the bar and loaded;
- Panacea and the companions pass `omarchy plugin validate`;
- the installed companions match this repo, are enabled and hold their slots;
- the Omarchy plugins they stand in for are unchanged since their baseline;
- the `osd` and `notifications` IPC targets answer;
- the shell log has no errors from Panacea;
- Hyprland reports no config errors, and the shortcut block is still in
  `bindings.lua`.

`scripts/health.sh install` runs it after every `omarchy update` (which restarts
the shell first, so the new Omarchy is what gets checked) and at login. After an
update it always sends one notification; at login, only when something needs
attention. Click it for the full report.

`upstream/<name>.json` holds the hashes of the Omarchy files a companion stands
in for. When the check says Omarchy changed one, review the companion against
the new files, then run `scripts/health.sh baseline` and commit.

## Hacking

QML edits need `omarchy restart shell`; a hot reload keeps the old component.
The log is at `qs -p /usr/share/omarchy/shell log`. If the plugin fails to load,
Omarchy falls back to its own bar and logs why.
