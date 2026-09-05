#!/usr/bin/env bash
#
# Pull the live config on this machine back into the repo, sanitised.
#
# This is the ONLY supported way to update panacea/ from a working install. The
# running pill rewrites settings.json continuously, so copying it by hand is how
# the OpenWeather API key ends up in a public repo. This blanks it every time.
#
#   ./sync.sh            copy live -> repo
#   ./sync.sh --dry-run  show what would change
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/panacea"
HYPR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
OMA="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
STATUSLINE="$HOME/.claude/statusline-command.sh"

DRY=0
case "${1:-}" in --dry-run|-n) DRY=1 ;; esac

bold=$'\033[1m'; dim=$'\033[2m'; grn=$'\033[32m'; ylw=$'\033[33m'; red=$'\033[31m'; rst=$'\033[0m'
step() { printf '%s==>%s %s\n' "$bold" "$rst" "$*"; }
did()  { printf '    %s+%s %s\n' "$grn" "$rst" "$*"; }
skip() { printf '    %s·%s %s\n' "$dim" "$rst" "$*"; }
warn() { printf '    %s!%s %s\n' "$ylw" "$rst" "$*"; }
die()  { printf '\n%sError:%s %s\n' "$red" "$rst" "$*" >&2; exit 1; }

[ -d "$CONF" ] || die "no $CONF — nothing to sync from."
[ "$DRY" = 1 ] && printf '%sDry run — nothing will be written.%s\n\n' "$ylw" "$rst"

RSYNC_FLAGS=(-a --delete
    --exclude='*.bak' --exclude='*.bak.*' --exclude='*.prepatch'
    --exclude='*.orig' --exclude='.vibrance')
[ "$DRY" = 1 ] && RSYNC_FLAGS+=(--dry-run -i)

step "Syncing the Panacea tree"
command -v rsync >/dev/null || die "rsync required for sync.sh"
rsync "${RSYNC_FLAGS[@]}" "$CONF/" "$REPO/panacea/" | sed 's/^/    /'
did "$(find "$CONF" -type f ! -name '*.bak*' ! -name '*.prepatch' ! -name '*.orig' | wc -l) files considered"

step "Sanitising settings.json"
# Do this even on a dry run's behalf check: the key must never reach the tree.
if [ "$DRY" = 0 ]; then
    jq -S --indent 4 '.weatherKey = "" | .weatherCity = ""' \
        "$REPO/panacea/settings.json" > "$REPO/panacea/settings.json.tmp" \
        && mv "$REPO/panacea/settings.json.tmp" "$REPO/panacea/settings.json"
    LEFT="$(jq -r '.weatherKey' "$REPO/panacea/settings.json")"
    [ -z "$LEFT" ] || die "weatherKey is still set after sanitising — refusing to continue."
    did "weatherKey and weatherCity blanked"
else
    skip "would blank weatherKey and weatherCity"
fi

step "Refreshing integration files"
copy() {
    local src="$1" dst="$2" name="$3"
    [ -f "$src" ] || { skip "$name absent on this machine"; return; }
    if cmp -s "$src" "$dst"; then skip "$name unchanged"; return; fi
    if [ "$DRY" = 1 ]; then printf '    %swould:%s update %s\n' "$dim" "$rst" "$name"; return; fi
    cp "$src" "$dst"; did "$name updated"
}
copy "$OMA/hooks/theme-set.d/20-panacea-wallpaper.hook" \
     "$REPO/integration/omarchy/20-panacea-wallpaper.hook" "wallpaper hook"
copy "$STATUSLINE" "$REPO/integration/claude/statusline-command.sh" "Claude statusline"

# The two Lua snippets are canonical in the repo, not on disk: the live files
# hold them inline among unrelated Omarchy config, and on a hand-wired machine
# they are not even marker-fenced. Report drift rather than guess at extents.
step "Checking the Hyprland snippets"
for pair in "autostart.lua:launch_on_start(\"qs -c panacea\")" "bindings.lua:ipc call pill github"; do
    f="${pair%%:*}"; needle="${pair#*:}"
    if [ -f "$HYPR/$f" ] && grep -qF "$needle" "$HYPR/$f"; then
        skip "$f still carries the pill wiring"
    else
        warn "$f no longer contains: $needle"
    fi
done

step "Final secret scan"
if grep -rIn --exclude-dir=.git -E '"weatherKey"[[:space:]]*:[[:space:]]*"[0-9a-f]{16,}"' "$REPO" ; then
    die "an API key is present in the repo tree. Do not commit."
fi
did "no API key anywhere in the tree"

printf '\n%sDone.%s Review with `git diff`, then commit.\n' "$grn" "$rst"
