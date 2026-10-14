#!/usr/bin/env bash
#
# Install the Panacea pill as the bar on an Omarchy machine.
#
# Idempotent: safe to re-run, and safe to run on a machine where the pill was
# wired up by hand. It appends marker-fenced blocks to the files Omarchy owns
# and never rewrites them wholesale.
#
#   ./install.sh            install
#   ./install.sh --dry-run  print the plan, change nothing
#
# This deliberately does NOT run upstream Panacea's own install.sh. That script
# replaces ~/.config/{hypr,foot,fish,fastfetch,nano} wholesale, installs SDDM and
# GRUB themes, and switches NetworkManager to the iwd backend. It is a full
# Omarchy replacement, not an add-on. See README.md.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/panacea"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
OMA="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
QSDIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
GHOSTTY="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty"
STATUSLINE="$HOME/.claude/statusline-command.sh"
MARK_OPEN='>>> panacea-omarchy >>>'

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
[ "${1:-}" = "-n" ] && DRY=1

bold=$'\033[1m'; dim=$'\033[2m'; grn=$'\033[32m'; ylw=$'\033[33m'; red=$'\033[31m'; rst=$'\033[0m'
step() { printf '%s==>%s %s\n' "$bold" "$rst" "$*"; }
did()  { if [ "${DRY:-0}" = 1 ]; then printf '    %s+ (would)%s %s\n' "$dim" "$rst" "$*";
                else printf '    %s+%s %s\n' "$grn" "$rst" "$*"; fi; }
skip() { printf '    %s·%s %s\n' "$dim" "$rst" "$*"; }
warn() { printf '    %s!%s %s\n' "$ylw" "$rst" "$*"; }
die()  { printf '\n%sError:%s %s\n' "$red" "$rst" "$*" >&2; exit 1; }
# Redact anything key-shaped before echoing a planned command: --dry-run output
# lands in scrollback and pasted bug reports.
redact() { sed -E "s/[0-9a-f]{32}/<redacted>/g"; }
run()  {
    if [ "$DRY" = 1 ]; then
        printf '    %swould:%s %s\n' "$dim" "$rst" "$*" | redact
    else
        eval "$@"
    fi
}

[ "$DRY" = 1 ] && printf '%sDry run — nothing will be changed.%s\n\n' "$ylw" "$rst"

# ── 1. Preflight ──────────────────────────────────────────────────────────────
step "Checking prerequisites"
for c in qs jq curl git; do
    command -v "$c" >/dev/null || die "\`$c\` not found. Install it and re-run."
done
did "qs, jq, curl, git present"
command -v omarchy >/dev/null || die "\`omarchy\` not found — this installer targets Omarchy 4 (Quattro)."
did "omarchy present"
if command -v gh >/dev/null; then did "gh present"
else warn "gh not found — the GitHub page will show an auth error until you install and \`gh auth login\`."; fi
# Captured, not piped: `set -o pipefail` plus `grep -q` reports failure even on a
# match, because grep exits early and fc-list dies on SIGPIPE.
_families="$(fc-list : family 2>/dev/null || true)"
case "$_families" in
    *"JetBrainsMono Nerd Font"*) did "JetBrainsMono Nerd Font present" ;;
    *) warn "JetBrainsMono Nerd Font missing — glyphs on the pill will render as boxes." ;;
esac
[ -d "$REPO/panacea" ] || die "no $REPO/panacea — run this from inside the cloned repo."

# ── 2. Preserve the machine's weather credentials ────────────────────────────
step "Preserving local weather settings"
KEEP_KEY=""; KEEP_CITY=""
if [ -f "$CONF/settings.json" ]; then
    KEEP_KEY="$(jq -r '.weatherKey  // ""' "$CONF/settings.json" 2>/dev/null || true)"
    KEEP_CITY="$(jq -r '.weatherCity // ""' "$CONF/settings.json" 2>/dev/null || true)"
fi
if [ -n "$KEEP_KEY" ]; then did "carrying over the existing weather API key"
else skip "no existing weather key — set one after install (see README)"; fi
[ -n "$KEEP_CITY" ] && did "carrying over weatherCity: $KEEP_CITY"

# ── 3. Install the Panacea tree ──────────────────────────────────────────────
step "Installing ~/.config/panacea"
if [ -e "$CONF" ]; then
    BAK="$CONF.bak.$(date +%s)"
    run "cp -a '$CONF' '$BAK'"
    did "backed up existing config to $(basename "$BAK")"
fi
run "mkdir -p '$CONF'"
# --delete would take the user's runtime state and any hand-added file with it,
# so copy over the top instead and let update.sh be the thing that prunes.
if command -v rsync >/dev/null; then
    run "rsync -a '$REPO/panacea/' '$CONF/'"
else
    run "cp -a '$REPO/panacea/.' '$CONF/'"
fi
did "$(find "$REPO/panacea" -type f | wc -l) files installed"

# ── 4. Put the weather credentials back ──────────────────────────────────────
if [ -n "$KEEP_KEY" ] || [ -n "$KEEP_CITY" ]; then
    step "Restoring weather settings"
    run "jq -S --indent 4 --arg k '$KEEP_KEY' --arg c '$KEEP_CITY' \
        '.weatherKey = \$k | .weatherCity = \$c' '$CONF/settings.json' > '$CONF/settings.json.tmp' \
        && mv '$CONF/settings.json.tmp' '$CONF/settings.json'"
    did "weatherKey and weatherCity restored"
fi

# ── 5. Quickshell symlink ────────────────────────────────────────────────────
step "Linking into Quickshell"
run "mkdir -p '$QSDIR'"
if [ -L "$QSDIR/panacea" ]; then
    if [ "$(readlink -f "$QSDIR/panacea")" = "$(readlink -f "$CONF")" ]; then
        skip "$QSDIR/panacea already points at the config"
    else
        run "ln -sfn '$CONF' '$QSDIR/panacea'"
        did "repointed a stale symlink"
    fi
elif [ -e "$QSDIR/panacea" ]; then
    die "$QSDIR/panacea exists and is not a symlink. Move it aside and re-run."
else
    run "ln -s '$CONF' '$QSDIR/panacea'"
    did "created $QSDIR/panacea -> $CONF"
fi

# append_block <file> <snippet> <sentinel-regex> <human-name>
# Skips when the sentinel already matches, so this is idempotent against a
# machine that was wired up by hand before the markers existed.
append_block() {
    local file="$1" snippet="$2" sentinel="$3" name="$4"
    if [ ! -f "$file" ]; then warn "$file does not exist — skipping $name"; return; fi
    if grep -qE "$sentinel" "$file"; then skip "$name already present in $(basename "$file")"; return; fi
    if [ "$DRY" = 1 ]; then printf '    %swould:%s append %s to %s\n' "$dim" "$rst" "$name" "$file"; return; fi
    printf '\n' >>"$file"
    cat "$snippet" >>"$file"
    did "appended $name to $(basename "$file")"
}

# ── 6-7. Hyprland autostart and keybinds ─────────────────────────────────────
step "Wiring Hyprland"
append_block "$HYPR/autostart.lua" "$REPO/integration/hypr/autostart.snippet.lua" \
    'launch_on_start\("qs -c panacea"\)' "the autostart line"
append_block "$HYPR/bindings.lua" "$REPO/integration/hypr/bindings.snippet.lua" \
    'ipc call pill github' "the SUPER+I / SUPER+U / SUPER+SHIFT+T binds"

# ── Glass mode ───────────────────────────────────────────────────────────────
# The toggle needs the terminal as much as it needs Hyprland: blur has nothing
# to frost unless the terminal's background is transparent, so the two are
# flipped together. This include is how glass.sh reaches ghostty.
step "Wiring glass mode"
append_block "$GHOSTTY/config" "$REPO/integration/ghostty/glass.snippet.conf" \
    'panacea-glass\.conf' "the glass-mode include"
# Seed the terminal's side now. Without it ghostty falls back to opaque while
# the pill — which reads the Hyprland flag, and that flag is absent — reports
# glass on: a fresh machine would boot into half a mode.
if [ -f "$CONF/scripts/glass.sh" ]; then
    run "'$CONF/scripts/glass.sh' on"
    did "glass mode on (toggle it with SUPER + SHIFT + T or the pill's switch)"
fi

# ── 8-9. Wallpaper hook ──────────────────────────────────────────────────────
step "Installing the wallpaper hook"
HOOKDIR="$OMA/hooks/theme-set.d"
run "mkdir -p '$HOOKDIR'"
run "install -m 755 '$REPO/integration/omarchy/20-panacea-wallpaper.hook' '$HOOKDIR/'"
did "20-panacea-wallpaper.hook installed"
# Seed wallpaper.conf now; the hook itself only fires on the next theme change.
run "'$HOOKDIR/20-panacea-wallpaper.hook' || true"
if [ "$DRY" = 0 ] && [ -f "$HYPR/wallpaper.conf" ]; then did "seeded $HYPR/wallpaper.conf"
else skip "wallpaper.conf will be written on the next theme change"; fi

# ── 10. Claude Code statusline (optional) ────────────────────────────────────
step "Claude Code usage cache"
if [ ! -e "$STATUSLINE" ]; then
    run "mkdir -p '$HOME/.claude'"
    run "install -m 755 '$REPO/integration/claude/statusline-command.sh' '$STATUSLINE'"
    did "installed statusline-command.sh (it feeds the pill's usage segment)"
    warn "point Claude Code at it: set statusLine.command to $STATUSLINE in ~/.claude/settings.json"
elif grep -q "panacea-claude-usage.json" "$STATUSLINE"; then
    skip "your statusline already mirrors the rate limits"
else
    warn "you already have a statusline at $STATUSLINE — not touching it."
    warn "the pill's usage segment needs the block in:"
    warn "  integration/claude/statusline-panacea-block.sh"
    warn "paste it in AFTER rl5_pct/rl7_pct are set, or the cache will just record -1."
fi

# ── 11. Hide the Omarchy bar ─────────────────────────────────────────────────
step "Hiding the Omarchy bar"
# The toggle is inverted: the word is passed straight through to a flag named
# `bar-off`, so `on` means "bar-off on", i.e. hidden. `off` brings it back.
if [ -f "$HOME/.local/state/omarchy/toggles/bar-off" ]; then
    skip "already hidden"
else
    run "omarchy toggle bar on"
    did "Omarchy bar hidden (undo with: omarchy toggle bar off)"
fi

# ── 12. Restart the pill ─────────────────────────────────────────────────────
step "Starting the pill"
# Kill by process name: autostart launches it as `/usr/bin/qs -c panacea`, and a
# pkill -f on the short form misses that. A `hyprctl reload` will NOT relaunch it
# either -- launch_on_start is exec-once -- so start it here.
if [ "$DRY" = 1 ]; then
    printf '    %swould:%s pkill qs, then setsid qs -c panacea\n' "$dim" "$rst"
else
    pgrep -x qs >/dev/null && { pkill -x qs || true; sleep 1; did "stopped the running pill"; }
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then
        setsid qs -c panacea >/dev/null 2>&1 < /dev/null &
        sleep 2
        pgrep -x qs >/dev/null && did "pill running" || warn "pill did not stay up — run \`qs -c panacea\` to see why"
    else
        warn "no Wayland session — the pill starts on your next login"
    fi
fi

# ── Git hook, when we're inside the clone ────────────────────────────────────
if [ -d "$REPO/.git" ]; then
    run "git -C '$REPO' config core.hooksPath .githooks"
    did "enabled the pre-commit secret guard for this clone"
fi

printf '\n%sDone.%s\n' "$grn" "$rst"
if [ -z "$KEEP_KEY" ]; then
cat <<'MSG'

  Next: the weather widget needs a free OpenWeather API key.
  Get one at https://openweathermap.org/api, then:

      jq -S --indent 4 --arg k 'YOUR_KEY' --arg c 'Your City, ST' \
        '.weatherKey = $k | .weatherCity = $c' ~/.config/panacea/settings.json > /tmp/s.json \
        && mv /tmp/s.json ~/.config/panacea/settings.json && pkill -x qs && setsid qs -c panacea &

  Never put that key in the repo copy -- this repo is public.
MSG
fi
