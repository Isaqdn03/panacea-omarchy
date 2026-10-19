#!/bin/bash
# Reads and writes Omarchy's idle timings (idle.screensaver / idle.lock in
# ~/.config/omarchy/shell.json, in seconds) for Panacea's Idle & Lock page.
#
#   omarchy-idle.sh get                      -> {"screensaver":150,"lock":300,"stayAwake":false}
#   omarchy-idle.sh set <screensaver> <lock>
#
# Writes go through Omarchy's own omarchy-shell-config helper, the same path
# `omarchy bar ...` uses: atomic write, then the running shell reloads it.

set -euo pipefail
source omarchy-shell-config

case "${1:-}" in
  get)
    stay=false
    [[ -f $HOME/.local/state/omarchy/indicators/stay-awake ]] && stay=true
    jq -c --argjson stay "$stay" \
      '{screensaver: (.idle.screensaver // 150), lock: (.idle.lock // 300), stayAwake: $stay}' \
      "$(source_file)"
    ;;
  set)
    [[ ${2:-} =~ ^[0-9]+$ && ${3:-} =~ ^[0-9]+$ ]] || fail "usage: set <screensaver-seconds> <lock-seconds>"
    commit '.idle.screensaver = $s | .idle.lock = $l' --argjson s "$2" --argjson l "$3"
    ;;
  *)
    fail "usage: get | set <screensaver-seconds> <lock-seconds>"
    ;;
esac
