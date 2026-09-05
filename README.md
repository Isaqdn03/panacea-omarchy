# panacea-omarchy

The [Panacea](https://github.com/EnsixD/Panacea) pill, set up as the **top bar on
Omarchy 4 (Quattro)** — installed alongside Omarchy rather than on top of it, with
a GitHub inbox page, a Claude agent-usage page, and a rebalanced Nothing-theme
island.

This is a snapshot of a working machine, packaged so a second Omarchy box can
reproduce it in one command. It is not a fork of Panacea and not a general-purpose
Panacea installer — see [Why not upstream's installer](#why-not-upstreams-installer).

```
clone → ./install.sh → same pill
```

## What you get

- Panacea's island pill at the top of the screen, reserving an exclusive zone
  (windows sit below it) in place of the Omarchy bar.
- **GitHub page** (`SUPER + I`) — notification inbox, review requests, assigned
  issues, the CI status of the repo in your focused window, and the last run for
  your eight most recently pushed repos. Stale-while-revalidate, so it paints
  instantly from cache and refreshes behind you.
- **Agent usage page** (`SUPER + U`) — installed AI CLIs with versions and plans,
  plus live Claude Code rate-limit percentages.
- Both surfaces also appear as segments on the collapsed pill and as a row in the
  expanded control centre.
- The Nothing-theme island, regrouped into five clusters — `nav │ ambient │ clock
  │ live │ status` — separated by hairline rules, with the shoulders balanced so
  the clock sits at true screen centre.

## Requirements

| | |
| --- | --- |
| **Omarchy 4 (Quattro)** | The installer targets Omarchy's Lua-based Hyprland config and its hook and toggle system. |
| **Quickshell** (`qs`) | Draws the pill. |
| `jq`, `curl`, `git` | Hard requirements; the installer refuses without them. |
| `gh`, authenticated | Optional. Without it everything works except the GitHub page. |
| JetBrainsMono Nerd Font | Optional but strongly advised — the pill is full of Nerd Font glyphs. |

## Install

```sh
git clone https://github.com/Isaqdn03/panacea-omarchy.git
cd panacea-omarchy
./install.sh --dry-run    # read the plan first
./install.sh
```

The installer is idempotent and safe to re-run, including on a machine where the
pill was wired up by hand — it detects the functional lines, not just its own
markers, so it will not duplicate your binds.

### The weather key

The weather widget needs a free [OpenWeather](https://openweathermap.org/api) API
key. **It is not in this repo and must never be**, because this repo is public.
The tracked `panacea/settings.json` ships with `weatherKey` and `weatherCity`
blank; `install.sh` carries over whatever is already on the target machine.

To set it after a fresh install:

```sh
jq -S --indent 4 --arg k 'YOUR_KEY' --arg c 'Your City, ST' \
  '.weatherKey = $k | .weatherCity = $c' ~/.config/panacea/settings.json > /tmp/s.json \
  && mv /tmp/s.json ~/.config/panacea/settings.json
pkill -x qs && setsid qs -c panacea &
```

Set it in the **installed** config at `~/.config/panacea/`, never in the repo
copy. A `pre-commit` hook (enabled by `install.sh`) blocks a commit that carries
a key, and `./sync.sh` blanks it on every run — but the rule is the real defence.

## What the install touches

Everything outside `~/.config/panacea` is an append or an added file. Omarchy's
own files are never rewritten wholesale.

| Path | Change |
| --- | --- |
| `~/.config/panacea/` | The pill itself. An existing one is backed up to `panacea.bak.<epoch>` first. |
| `~/.config/quickshell/panacea` | Symlink to the above, so `qs -c panacea` resolves. |
| `~/.config/hypr/autostart.lua` | One appended, marker-fenced `launch_on_start` line. |
| `~/.config/hypr/bindings.lua` | Appended, marker-fenced `SUPER + I` / `SUPER + U` binds. |
| `~/.config/omarchy/hooks/theme-set.d/20-panacea-wallpaper.hook` | New file. Mirrors Omarchy's current background into `~/.config/hypr/wallpaper.conf`, which Panacea reads as its wallpaper state. |
| `~/.config/hypr/wallpaper.conf` | Seeded once by running that hook. |
| `~/.claude/statusline-command.sh` | Installed **only if absent**. See below. |
| `omarchy toggle bar on` | Hides the Omarchy bar. Note the inversion, below. |

### The Claude statusline is conditional

The pill's usage segment reads `~/.cache/panacea-claude-usage.json`, which a block
in the Claude Code statusline writes. Claude Code hands rate limits to the
statusline command on stdin and stores them nowhere else, so this mirror is the
only way to get them.

If you have no statusline, the installer drops in the one from this repo. **If you
already have one, it will not touch it** — it prints the block from
`integration/claude/statusline-panacea-block.sh` and leaves the paste to you. The
block reads `rl5_pct` / `rl7_pct`, which only the shipped statusline defines;
appending it blindly to a different script would write `-1` forever.

## Warnings

These are all load-bearing. Each one cost real debugging to find.

### Why not upstream's installer

**Do not run Panacea's own `install.sh`.** It replaces
`~/.config/{hypr,foot,fish,fastfetch,nano}` wholesale, installs an SDDM theme and
a GRUB theme, and switches NetworkManager to the iwd backend. It is a complete
desktop replacement, and on Omarchy it will take your Hyprland config, your
terminal config and your network stack with it. This repo installs the pill only.

### Do not open Panacea's Display or Input settings pages

On startup and on **every Hyprland `configreloaded`**, `shell.qml` replays its own
monitor overrides, mouse sensitivity, accel profile and vibrance shader at the
compositor via `hyprctl eval`. As shipped its stored values match a default
machine, so nothing moves. The moment you change something on those pages, it
starts overwriting Omarchy's monitor and input config on every reload — which is
painful on a multi-monitor setup and worse on one with mixed scale factors.

Keep `monOverrides` empty and `pillScreen` on `auto`. Change monitors and input
through Omarchy.

### The bar toggle is inverted

The flag is named `bar-off` and `omarchy toggle bar <word>` passes the word
straight through to it. So:

```sh
omarchy toggle bar on    # HIDES the Omarchy bar
omarchy toggle bar off   # brings it back
```

### Features turned off on purpose

Omarchy already owns these jobs, or the dependency is not installed. They are off
in `settings.json` and turning them on gets you a dead surface, not a feature.

| Setting | Why |
| --- | --- |
| `featNotifications`, `featPolkit` | Omarchy holds both DBus names. Panacea's notification panel and auth prompts can never claim them. |
| `featClipboard` | Omarchy has its own history in `~/.local/state/omarchy/clipboard-history.json`; `cliphist` is not installed. |
| `featRecord` | Omarchy records via gpu-screen-recorder; `wf-recorder` is not installed. |
| `featVault`, `vaultCapture` | **Also the only way to stop a clipboard watcher.** With the vault on, Panacea runs `wl-paste --type text --watch` and parses everything you copy. `vaultCapture: false` only stops the prompt — the subprocess keeps running. Killing the pill orphans it, still reading the clipboard, reparented to init. |

The Wallpapers tab also cannot work: it wants a `~/.config/hypr/wallpaper/`
directory and a `~/.config/hypr/scripts/switch_theme.sh` that Omarchy does not
have. The wallpaper hook exists only to give `lock.qml` an image and silence a
startup read error.

Panacea's visualizer needs `cava`, which is likewise absent — it gates on `hasCava`
at runtime, so it simply does not draw. No setting to change.

### One harmless startup warning

`featNotifications` defaults to `true` at `shell.qml:177`, so before
`settings.json` loads, a `NotificationServer` is briefly built and fails to claim
the DBus name. Omarchy keeps the name, the loader deactivates, nothing breaks.

## Keeping it current

After tuning the live config on a machine, pull the changes back in:

```sh
./sync.sh --dry-run
./sync.sh
git diff && git commit -am "..."
```

`sync.sh` is the only supported path — it blanks the API key, drops the backup and
`.prepatch` files, and refuses to finish if a key survives anywhere in the tree.

### Updating Panacea itself

```sh
~/.config/panacea/scripts/update.sh        # upstream, over the top
~/.config/panacea/apply-local-patches.sh   # put the local edits back
~/.config/panacea/apply-local-patches.sh --check   # expect 8/8
```

`update.sh` carries everything from upstream except `settings.json`, so the eight
patched files lose their edits and must be re-patched. Every edit is fenced with a
`PANACEA-LOCAL` marker and is idempotent; if an anchor no longer matches, the
script aborts and names the file rather than half-applying. Then `./sync.sh` and
commit.

## Uninstall

```sh
./uninstall.sh            # unwire, keep ~/.config/panacea
./uninstall.sh --purge    # and delete it
```

Strips the marker-fenced blocks, removes the symlink and the hook, runs
`omarchy toggle bar off` to bring the Omarchy bar back, and stops the pill. It
never deletes your `statusline-command.sh` — only the block inside it.

A block you added by hand, before the markers existed, is reported with line
numbers rather than removed, because guessing its extent from content risks
eating the lines around it.

## Credits

Panacea is by **[EnsixD](https://github.com/EnsixD/Panacea)**, MIT licensed. This
repo redistributes a modified snapshot of it under that licence; see
[`LICENSE`](LICENSE) and [`NOTICE.md`](NOTICE.md), which records the pinned
upstream commit and lists every locally written and locally patched file.

Upstream is not affiliated with this repo. Report bugs in the pill itself to
upstream only after checking they reproduce without these patches.
