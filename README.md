# Panacea for Omarchy

Panacea's rail and drawer as the Omarchy bar. This is a fork of
[EnsixD/Panacea](https://github.com/EnsixD/Panacea) (MIT, see [NOTICE](NOTICE.md))
that runs as a `bar` plugin inside `omarchy-shell`. It saves its settings in
Omarchy's own files and uses Omarchy's services wherever Omarchy has one.

Built and used on Omarchy 4.0.4 with Hyprland 0.56 (Lua config) and Quickshell 0.3.1.

## Install

```bash
# Clones into ~/.config/omarchy/plugins/isaqdn.panacea and makes it the bar.
omarchy plugin add https://github.com/Isaqdn03/panacea-omarchy.git --enable

# Panacea draws the OSD and the notifications; turn off Omarchy's copies.
omarchy-shell shell setPluginEnabled omarchy.osd false
omarchy-shell shell setPluginEnabled omarchy.notifications false
omarchy restart shell
```

Update with `omarchy plugin update isaqdn.panacea`. It shows the diff, then
fast-forwards the checkout.

To go back to Omarchy's bar, run `omarchy bar use omarchy.bar`, re-enable the two
plugins with `... setPluginEnabled <id> true`, then `omarchy restart shell`.

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

## Hacking

QML edits need `omarchy restart shell`; a hot reload keeps the old component.
The log is at `qs -p /usr/share/omarchy/shell log`. If the plugin fails to load,
Omarchy falls back to its own bar and logs why.
