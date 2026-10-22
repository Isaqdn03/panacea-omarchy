#!/bin/bash
# Panacea's companion plugins: small plugins that take one of Omarchy's own
# slots (manifest omarchy.clonedFrom) and hand its work to Panacea. Each
# directory in companions/ is one plugin, installed as a copy at
# ~/.config/omarchy/plugins/isaqdn.panacea-<name>/, because third-party
# plugins must sit at the top level and Omarchy refuses a symlinked one.
# The copy in this repo is the one to edit.
#
#   companions.sh install   copy every companion into place and validate it
#   companions.sh check     list the companions whose installed copy differs
#
# Never run from inside the shell: any write under ~/.config/omarchy/plugins
# makes omarchy-shell reload every plugin.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
cmd="${1:-check}"
status=0

for src in "$here"/companions/*/; do
  name="$(basename "$src")"
  dest="$plugins/isaqdn.panacea-$name"
  case "$cmd" in
    install)
      mkdir -p "$dest"
      cp -f "$src"* "$dest"/
      omarchy plugin validate "$dest"
      echo "installed isaqdn.panacea-$name"
      ;;
    check)
      if ! diff -rq "$src" "$dest" >/dev/null 2>&1; then
        echo "out of date: isaqdn.panacea-$name (run: companions.sh install)"
        status=1
      fi
      ;;
    *)
      echo "usage: companions.sh install|check" >&2
      exit 2
      ;;
  esac
done

exit "$status"
