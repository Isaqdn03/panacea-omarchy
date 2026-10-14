# Provenance

This repository redistributes a modified snapshot of **Panacea**, a Quickshell
desktop shell by EnsixD, under the terms of its MIT licence.

- **Upstream:** <https://github.com/EnsixD/Panacea>
- **Pinned at:** commit `60d190b42f5b` — *"shell: bump version to 1.0.12"*, 2026-09-01
- **Licence:** MIT, Copyright (c) 2026 EnsixD — reproduced verbatim in [`LICENSE`](LICENSE)
- **Snapshot taken:** 2026-09-05, from a working install made 2026-09-02

Everything under `panacea/` is upstream's work except as listed below. The
upstream project is not affiliated with this repository and does not support it.

## Files written locally

| File | What it is |
| --- | --- |
| `panacea/GithubView.qml` | GitHub inbox / CI page for the pill |
| `panacea/scripts/github.sh` | Its data source: notifications, review requests, focused-repo CI |
| `panacea/scripts/usage_brief.sh` | Highest Claude rate-limit percentage, for the pill segment |
| `panacea/scripts/glass.sh` | Glass mode: Hyprland blur and the terminal's transparent background, flipped together |
| `panacea/apply-local-patches.sh` | Re-applies every patch below after an upstream update |

## Files patched locally

Nine upstream files carry local edits. Every edit is fenced with a
`PANACEA-LOCAL` marker, and `apply-local-patches.sh --check` reports 9/9 when
they are all present.

| File | What changed |
| --- | --- |
| `panacea/shell.qml` | GitHub + agent-usage segments on the collapsed pill, hairline group rules, shoulder-balance fixes, weather retry-on-network-failure, glass-mode state |
| `panacea/ControlsView.qml` | Full-width GitHub and glass-mode rows in the expanded control centre; Flickable around the Wi-Fi list so it can scroll |
| `panacea/LauncherView.qml` | "github" / "pr" / "ci" launcher keywords |
| `panacea/WidgetsView.qml` | Clickable desktop widget cards |
| `panacea/AgentsView.qml` | Page-level Flickable so the agent list can scroll |
| `panacea/Translations.qml` | English strings for everything added above |
| `panacea/scripts/agents.sh` | 6 h cache for static agent probes (3.2 s → 0.07 s per open) |
| `panacea/scripts/weather.sh` | Distinguish "no network" from "no such city" |
| `panacea/scripts/wifi.sh` | nmcli backend — this machine runs NetworkManager, not iwd |

## Updating from upstream

```sh
~/.config/panacea/scripts/update.sh      # pulls upstream over the top
~/.config/panacea/apply-local-patches.sh # puts the local edits back
```

`update.sh` carries everything from the upstream repo except `settings.json`, so
the nine patched files above are overwritten and must be re-patched. If an
anchor no longer matches, `apply-local-patches.sh` aborts and names the file
rather than half-applying.
