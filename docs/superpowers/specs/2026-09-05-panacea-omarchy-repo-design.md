# Panacea-on-Omarchy config repo — design

Date: 2026-09-05
Status: approved, ready for implementation plan

## Problem

The Panacea pill currently running on the laptop is a hand-built setup that exists
only on that machine's disk. It is upstream Panacea v1.0.12 with eight files patched,
three files written from scratch, a sanitised `settings.json`, and five integration
points wired into files that Omarchy owns. Reproducing it on another Omarchy machine
today means repeating several days of work from memory.

Goal: a public GitHub repo that a second Omarchy machine can clone and install with one
command, ending with the same pill.

## Non-goals

- Replacing or forking upstream Panacea development. This repo is a deployment vehicle.
- Supporting non-Omarchy Hyprland setups. The integration assumes Omarchy 4 (Quattro).
- Syncing runtime state (weather cache, agent probe cache, vibrance level) between machines.

## Approach

**Full snapshot, not an overlay.** The repo carries the entire working `~/.config/panacea`
tree rather than reconstructing it from upstream plus patches at install time. Rationale:
the value of this repo is that a clone reproduces the exact pill that is known to work.
An overlay would re-derive it by cloning upstream at a pinned commit and replaying
`apply-local-patches.sh`, which introduces two failure modes on a fresh machine — an
unreachable upstream, and patch anchors that no longer match. `apply-local-patches.sh`
still ships in the repo; it is the tool for pulling a *newer* Panacea later, not part of
the install path.

Upstream is MIT licensed (github.com/EnsixD/Panacea), so redistributing a snapshot is
permitted with the licence text and attribution included.

## Repository layout

```
panacea-omarchy/
  README.md
  LICENSE                             upstream MIT, verbatim
  NOTICE.md                           upstream vs local provenance, pinned commit
  .gitignore
  .githooks/pre-commit                refuses commits containing a weather API key
  panacea/                            full working copy of ~/.config/panacea
    settings.json                     weatherKey and weatherCity blanked
    apply-local-patches.sh            kept, for future upstream updates
    ...                               all QML, scripts, assets, sounds
  integration/
    hypr/autostart.snippet.lua
    hypr/bindings.snippet.lua
    omarchy/20-panacea-wallpaper.hook
    claude/statusline-panacea-block.sh
    claude/statusline-command.sh      full script, installed only when target has none
  install.sh
  uninstall.sh
  sync.sh                             live config -> repo, with sanitisation
  docs/superpowers/specs/             this document
```

### Excluded from `panacea/`

`*.bak.*`, `*.prepatch`, `*.orig`, `.vibrance`. The `.orig` files were verified to have
no referents anywhere in the tree — nothing reads them; they were manual reference copies.
`.vibrance` is per-machine runtime state.

## Provenance

`NOTICE.md` records:

- Upstream: `EnsixD/Panacea`, commit `60d190b42f5b` ("shell: bump version to 1.0.12",
  2026-09-01), MIT, Copyright (c) 2026 EnsixD.
- Snapshot taken 2026-09-05 from a working install made 2026-09-02.
- Locally written files: `GithubView.qml`, `scripts/github.sh`, `scripts/usage_brief.sh`,
  `apply-local-patches.sh`.
- Locally patched files (8): `shell.qml`, `LauncherView.qml`, `WidgetsView.qml`,
  `Translations.qml`, `ControlsView.qml`, `AgentsView.qml`, `scripts/agents.sh`,
  `scripts/weather.sh`. Every edit is fenced with a `PANACEA-LOCAL` marker.

## Secret handling

The live `settings.json` holds an OpenWeather API key and the user's city. The repo is
public, so both are blanked in the committed copy.

The material risk is not the first commit but re-leakage: the running pill rewrites
`settings.json` continuously, so a later `git add panacea/settings.json` would restore the
key. Three defences, in order of reliability:

1. `sync.sh` is the only supported path for pulling live changes back into the repo, and it
   blanks `weatherKey` and `weatherCity` on every run.
2. `.githooks/pre-commit` greps the staged diff for a 32-hex `weatherKey` value and aborts
   the commit. When `install.sh` is run from inside a clone of this repo it sets
   `git config core.hooksPath .githooks` for that clone. Because a hook protects only the
   clone it is configured in, `README.md` also states the rule in plain terms.
3. `README.md` documents where to put the key on a new machine: run `install.sh`, then set
   `weatherKey` and `weatherCity` in the *installed* `~/.config/panacea/settings.json`, never
   in the repo copy.

`install.sh` preserves an existing target's `weatherKey`/`weatherCity` when overwriting, so
re-running it on a configured machine does not blank the working key.

The key that is currently live has been present only on local disk. Nothing in this design
publishes it, and no rotation is required as a result of this work.

## install.sh

Idempotent, safe to re-run, and it never overwrites a file that Omarchy owns — it appends
marker-fenced blocks and leaves everything else alone.

Order of operations:

1. Preflight: assert Omarchy (`omarchy` on PATH), `qs` (Quickshell), `jq`, `curl`, `git`.
   Warn but continue when `gh` is absent — only the GitHub page degrades.
2. Read `weatherKey`/`weatherCity` from an existing `~/.config/panacea/settings.json`, if any.
3. Back up an existing `~/.config/panacea` to `~/.config/panacea.bak.<epoch>`, then copy
   `panacea/` into place.
4. Restore the preserved `weatherKey`/`weatherCity` into the installed `settings.json`.
5. Create `~/.config/quickshell/panacea` -> `~/.config/panacea` (replace a stale symlink;
   refuse and report if a real directory is in the way).
6. Append the autostart line to `~/.config/hypr/autostart.lua` if its marker is absent.
7. Append the `SUPER + I` / `SUPER + U` binds to `~/.config/hypr/bindings.lua` if absent.
8. Install `20-panacea-wallpaper.hook` into `~/.config/omarchy/hooks/theme-set.d/`, chmod +x.
9. Seed `~/.config/hypr/wallpaper.conf` once, by running the hook.
10. Claude statusline: if `~/.claude/statusline-command.sh` is absent, install the full
    shipped one. If it exists and lacks the marker, print the block and instruct the user to
    paste it — do not append blindly, because the block reads `rl5_pct`/`rl7_pct` variables
    that only the shipped statusline defines.
11. `omarchy toggle bar on` to hide the Omarchy bar. Note the inverted flag: the toggle
    passes the word through to a flag named `bar-off`, so `on` hides.
12. Restart the pill: kill by `pgrep -x qs` — not `pkill -f "qs -c panacea"`, which needs an
    exact cmdline match and misses the autostarted `/usr/bin/qs -c panacea` — then relaunch it
    directly and detached (`setsid qs -c panacea`). A `hyprctl reload` does *not* re-run
    `launch_on_start`, which is `exec-once`; only a compositor restart does.

Every mutating step is announced. `--dry-run` prints the plan without touching anything.

**It must never invoke upstream's `install.sh`.** That installer replaces
`~/.config/{hypr,foot,fish,fastfetch,nano}` wholesale, sets SDDM and GRUB themes, and
switches NetworkManager to the iwd backend. It is a full Omarchy replacement. `install.sh`
carries this as a comment and `README.md` states it prominently.

## uninstall.sh

Reverses each step: strips the marker-fenced blocks from `autostart.lua` and `bindings.lua`,
removes the symlink and the theme-set hook, strips the marker-fenced statusline block, runs
`omarchy toggle bar off` to restore the Omarchy bar, and kills the pill. It never deletes a
`statusline-command.sh` outright, even one `install.sh` put there — that file is the user's
Claude Code statusline, not a Panacea artifact, and removing it would silently break the
status line. It leaves
`~/.config/panacea` on disk by default and removes it only with `--purge`.

## sync.sh

Copies the live `~/.config/panacea` back into the repo's `panacea/`, applying the same
exclusion list and the `settings.json` sanitisation. Also refreshes the four integration
files from their live locations. This is how the repo stays current after further tuning
on the laptop, and it is the only path that guarantees the API key does not travel.

## README.md

Sections: what this is and what it looks like; requirements (Omarchy 4 / Quattro,
Quickshell, JetBrainsMono Nerd Font, `gh` for the GitHub page); install; the weather key
step; what the install touches, file by file; uninstall; updating from upstream
(`scripts/update.sh` then `apply-local-patches.sh`); attribution to upstream.

Warnings it must carry, all of them load-bearing:

- **Do not run upstream's `install.sh`.** With the reason.
- **Do not open Panacea's Display or Input settings pages.** `shell.qml` replays its own
  monitor overrides, mouse sensitivity, accel profile and vibrance shader at the compositor
  via `hyprctl eval` on start and on every Hyprland `configreloaded`. Its stored defaults
  currently match the machine, so nothing moves — but touching those pages starts
  overwriting Omarchy's monitor and input config on every reload. This matters most on a
  multi-monitor mixed-scale setup. Keep `monOverrides` empty and `pillScreen` on `auto`.
- **Known-degraded surfaces on Omarchy**, because Omarchy owns the DBus names or the
  dependency is absent: notifications and polkit (`featNotifications`, `featPolkit` off),
  clipboard (`featClipboard` off, Omarchy has its own history), recording (`featRecord` off,
  Omarchy uses gpu-screen-recorder), vault (`featVault` off — also the only way to stop its
  `wl-paste --watch` clipboard subprocess), and the Wallpapers tab, which wants a
  `~/.config/hypr/wallpaper/` directory and a `switch_theme.sh` that Omarchy does not have.
- **The bar toggle is inverted**: `omarchy toggle bar on` hides the Omarchy bar.
- **Killing the pill orphans its `wl-paste --watch` child** when the vault is enabled. With
  `featVault: false` shipped, this does not arise, but it is worth knowing.

## Machine portability

The snapshot is machine-agnostic as shipped: no hardcoded home paths anywhere in the tree
(verified), `monOverrides` empty, `pillScreen` `auto`, `mouseSens` 0, and `github.sh`
derives the account from `gh api user` rather than a baked-in login. The two per-machine
values are the weather key and city, handled above.

The `themeId` is `nothing`, which pairs with the user's custom Nothing Omarchy theme. The
pill renders on any theme; the README notes the pairing without making it a requirement.

## Testing

There is no test framework here and adding one is not warranted. Verification is a
scripted checklist, run in this order:

1. `install.sh --dry-run` on the laptop — the plan must report every integration point as
   already present, proving idempotency against the live machine.
2. `bash -n` on all four shipped shell scripts; `shellcheck` if available.
3. Install into a throwaway `HOME` (`HOME=/tmp/.../fakehome ./install.sh --dry-run`) to
   confirm the fresh-machine path takes the "install statusline" and "append block"
   branches rather than the "already present" ones.
4. `panacea/apply-local-patches.sh --check` against the repo copy must report 8/8 files
   patched — this is the guard that the snapshot did not lose local edits.
5. `git grep` for the API key across the full history before pushing, plus a deliberate
   attempt to commit the live `settings.json` to confirm the pre-commit hook aborts it.
6. Real install on the desktop is the acceptance test, and it is the user's to run.

## Open decisions deferred

- Whether to also track the custom Nothing Omarchy theme in this repo. It is a separate
  artifact with its own install path; out of scope here.
