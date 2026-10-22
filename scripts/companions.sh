#!/bin/bash
# Panacea's companion plugins: small plugins that take one of Omarchy's own
# slots (manifest omarchy.clonedFrom) and hand its work to Panacea, or run
# Omarchy's own code drawn Panacea's way. Each directory in companions/ is one
# plugin, installed as a copy at ~/.config/omarchy/plugins/isaqdn.panacea-<name>/,
# because third-party plugins must sit at the top level and Omarchy refuses a
# symlinked one. The copy in this repo is the one to edit.
#
#   companions.sh install          copy every companion into place and validate it
#   companions.sh check            list the companions whose installed copy differs
#   companions.sh adopt <omarchy-id> <name>
#       Start a companion as an exact copy of one of Omarchy's plugins, as
#       `omarchy plugin clone` does, but in companions/<name>: the same files,
#       the manifest renamed and pointed at the slot. Records the baseline.
#   companions.sh baseline [name]
#       Keep a copy of the Omarchy files each companion stands in for, as they
#       are now, in upstream/<name>/: what the companion was last checked
#       against, and the common ancestor `sync` merges from.
#   companions.sh sync <name> [omarchy-dir]
#       Bring Omarchy's changes to its plugin into the companion. A file the
#       companion never changed takes Omarchy's version; one it changed (the
#       `// panacea` lines) is merged three ways (git merge-file) with the
#       baseline as the ancestor. Clean: the baseline moves up. A conflict
#       leaves git's markers in the file and the baseline where it was:
#       resolve them, then run `baseline <name>`. [omarchy-dir] stands in for
#       Omarchy's copy, for trying a sync out.
#
# Plugins with subdirectories are not handled: the ones adopted so far are flat.
# Never run from inside the shell: any write under ~/.config/omarchy/plugins
# makes omarchy-shell reload every plugin.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_id="isaqdn.panacea"
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
cmd="${1:-check}"

fail() {
  echo "companions.sh: $*" >&2
  exit 2
}

slot_of() {
  jq -r '.omarchy.clonedFrom // empty' "$here/companions/$1/manifest.json"
}

source_dir() {
  omarchy-plugin-catalog | jq -r --arg id "$1" '.[] | select(.firstParty and .id == $id) | .sourceDir'
}

baseline() {
  local name="$1" want dir version file
  want="$(slot_of "$name")"
  [[ -n $want ]] || return 0
  dir="$(source_dir "$want")"
  [[ -d $dir ]] || fail "Omarchy does not ship $want"
  version="$(omarchy version 2>/dev/null || echo unknown)"
  mkdir -p "$here/upstream/$name"
  for file in "$here/upstream/$name"/*; do
    [[ -f $file && ! -f $dir/$(basename "$file") ]] && rm -f "$file"
  done
  cp -f "$dir"/* "$here/upstream/$name"/
  jq -n --arg want "$want" --arg version "$version" '{clonedFrom: $want, omarchy: $version}' \
    >"$here/upstream/$name.json"
  echo "baseline: $plugin_id-$name <- $want (Omarchy $version)"
}

adopt() {
  local want="$1" name="$2" dir dest
  [[ $name =~ ^[a-z][a-z0-9-]*$ ]] || fail "companion names are lower-case words: $name"
  dir="$(source_dir "$want")"
  [[ -d $dir ]] || fail "not one of Omarchy's plugins: $want"
  dest="$here/companions/$name"
  [[ ! -e $dest ]] || fail "already a companion: $dest"
  mkdir -p "$dest"
  cp -a "$dir"/. "$dest"/
  jq --arg id "$plugin_id-$name" --arg name "Panacea ${name^}" --arg want "$want" '
    .id = $id | .name = $name |
    .omarchy = ((if (.omarchy | type) == "object" then .omarchy else {} end) + {clonedFrom: $want}) |
    del(.omarchy.clonePaths)
  ' "$dest/manifest.json" >"$dest/manifest.json.tmp"
  mv "$dest/manifest.json.tmp" "$dest/manifest.json"
  echo "adopted $want as $plugin_id-$name in companions/$name"
  baseline "$name"
}

sync() {
  local name="$1" dir="${2:-}" want base ours theirs file was now conflicts=0 changes=0
  want="$(slot_of "$name")"
  [[ -n $want ]] || fail "$name stands in for no Omarchy plugin"
  [[ -n $dir ]] || dir="$(source_dir "$want")"
  [[ -d $dir ]] || fail "Omarchy does not ship $want"
  base="$here/upstream/$name"
  ours="$here/companions/$name"
  [[ -d $base ]] || fail "no baseline for $name (companions.sh baseline $name)"
  was="$(jq -r '.omarchy' "$here/upstream/$name.json")"
  now="$(omarchy version 2>/dev/null || echo unknown)"

  for theirs in "$dir"/*; do
    file="$(basename "$theirs")"
    [[ -f $base/$file ]] && cmp -s "$theirs" "$base/$file" && continue
    changes=1
    if [[ ! -f $ours/$file ]]; then
      cp "$theirs" "$ours/$file"
      echo "added    $file"
    elif [[ ! -f $base/$file ]]; then
      echo "CONFLICT $file: new in Omarchy, but the companion already has one"
      conflicts=1
    elif cmp -s "$ours/$file" "$base/$file"; then
      cp "$theirs" "$ours/$file"
      echo "updated  $file"
    elif git merge-file -L "panacea" -L "omarchy $was" -L "omarchy $now" \
        "$ours/$file" "$base/$file" "$theirs"; then
      echo "merged   $file (kept the // panacea lines)"
    else
      echo "CONFLICT $file: Omarchy changed lines Panacea changed too; see the <<<<<<< markers"
      conflicts=1
    fi
  done

  for theirs in "$base"/*; do
    file="$(basename "$theirs")"
    [[ -f $dir/$file ]] && continue
    changes=1
    if [[ ! -f $ours/$file ]] || cmp -s "$ours/$file" "$theirs"; then
      rm -f "$ours/$file"
      echo "removed  $file"
    else
      echo "CONFLICT $file: Omarchy removed it, but the companion changed it"
      conflicts=1
    fi
  done

  if ((conflicts)); then
    echo "Resolve the conflicts in companions/$name, then: companions.sh baseline $name"
    return 1
  fi
  ((changes)) || { echo "$plugin_id-$name: nothing changed in Omarchy's $want"; return 0; }
  [[ -z ${2:-} ]] && baseline "$name"
  echo "Synced. Install it (companions.sh install), restart the shell, and look before committing."
}

case "$cmd" in
  adopt)
    (($# == 3)) || fail "usage: companions.sh adopt <omarchy-id> <name>"
    adopt "$2" "$3"
    exit 0
    ;;
  baseline)
    if (($# == 2)); then
      baseline "$2"
    else
      for src in "$here"/companions/*/; do baseline "$(basename "$src")"; done
    fi
    exit 0
    ;;
  sync)
    (($# >= 2)) || fail "usage: companions.sh sync <name> [omarchy-dir]"
    sync "$2" "${3:-}"
    exit $?
    ;;
  install | check) ;;
  *) fail "usage: companions.sh install|check|adopt|baseline|sync" ;;
esac

status=0
for src in "$here"/companions/*/; do
  name="$(basename "$src")"
  dest="$plugins/$plugin_id-$name"
  if [[ $cmd == install ]]; then
    mkdir -p "$dest"
    cp -f "$src"* "$dest"/
    omarchy plugin validate "$dest"
    echo "installed $plugin_id-$name"
  elif ! diff -rq "$src" "$dest" >/dev/null 2>&1; then
    echo "out of date: $plugin_id-$name (run: companions.sh install)"
    status=1
  fi
done

exit "$status"
