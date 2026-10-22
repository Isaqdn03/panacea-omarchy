#!/bin/bash
# Panacea's health check: is Panacea still whole on the Omarchy installed now?
# Run after every `omarchy update` and at login by the hooks `health.sh
# install` puts in ~/.config/omarchy/hooks, and by hand any time.
#
#   health.sh check [--after-update|--at-boot]
#       Runs every check, prints the report, keeps it in
#       ~/.local/state/panacea/health/report.txt and sends one notification:
#       after an update always, otherwise only when something needs attention.
#       Exit status: 0 healthy, 1 something to review, 2 something broken.
#   health.sh install
#       Installs the post-update and post-boot hooks (omarchy hook install).
#
# `omarchy update` restarts the shell before it runs post-update hooks, so the
# shell checked here already runs the new Omarchy. Nothing here writes under
# ~/.config/omarchy/plugins: any write there reloads every plugin.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plugin_id="isaqdn.panacea"
plugins="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
shell_json="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
bindings="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/bindings.lua"
panacea_settings="${XDG_CONFIG_HOME:-$HOME/.config}/panacea/settings.json"
state="${XDG_STATE_HOME:-$HOME/.local/state}/panacea/health"
report="$state/report.txt"
omarchy_path="${OMARCHY_PATH:-/usr/share/omarchy}"

glyph_alert=$'\U000F0026'
glyph_ok=$'\U000F012C'

fails=()
warns=()
oks=()
fail() { fails+=("$1"); }
warn() { warns+=("$1"); }
ok() { oks+=("$1"); }

companion_names() {
  local dir
  for dir in "$here"/companions/*/; do basename "$dir"; done
}

answers() {
  [[ $(omarchy-shell "$1" "$2" 2>/dev/null) == "${3:-ok}" ]]
}

wait_for() {
  local seconds="$1"
  shift
  local i
  for ((i = 0; i < seconds; i++)); do
    "$@" && return 0
    sleep 1
  done
  "$@"
}

panacea_answers() {
  omarchy-shell pill current >/dev/null 2>&1
}

check_omarchy() {
  local version last
  version="$(omarchy version 2>/dev/null || echo unknown)"
  last="$(cat "$state/omarchy-version" 2>/dev/null || true)"
  if [[ -n $last && $last != "$version" ]]; then
    ok "Omarchy $last -> $version"
  else
    ok "Omarchy $version"
  fi
  echo "$version" >"$state/omarchy-version"
}

check_bar() {
  local bar
  bar="$(jq -r '.bar.id // "omarchy.bar"' "$shell_json" 2>/dev/null || echo unknown)"
  if [[ $bar != "$plugin_id" ]]; then
    warn "The bar is $bar, not Panacea (omarchy bar use $plugin_id)"
  elif wait_for 15 panacea_answers; then
    ok "Panacea is the bar and answers"
  else
    fail "Panacea is the bar but did not load, so Omarchy fell back to its stock bar"
  fi
}

check_plugins() {
  local id out
  for id in "$plugin_id" $(companion_names | sed "s/^/$plugin_id-/"); do
    if [[ ! -d $plugins/$id ]]; then
      fail "$id is not installed (scripts/companions.sh install)"
    elif out="$(omarchy plugin validate "$plugins/$id" 2>&1)"; then
      ok "$id passes omarchy plugin validate"
    else
      fail "$id fails omarchy plugin validate: ${out##*$'\n'}"
    fi
  done
}

check_companions() {
  local out list name id enabled slot want
  if out="$("$here/scripts/companions.sh" check 2>&1)"; then
    ok "The installed companions match the repo"
  else
    warn "$out"
  fi

  # The notifications companion runs only with Panacea's notifEngine
  # "omarchy"; with "panacea", Panacea's own server does, and the two must
  # never run together.
  local engine
  engine="$(jq -r '.notifEngine // "panacea"' "$panacea_settings" 2>/dev/null || echo panacea)"

  list="$(omarchy plugin list --json 2>/dev/null)"
  for name in $(companion_names); do
    id="$plugin_id-$name"
    want="$(jq -r '.omarchy.clonedFrom // empty' "$here/companions/$name/manifest.json")"
    enabled="$(jq -r --arg id "$id" '.[] | select(.id == $id) | .enabled' <<<"$list")"
    slot="$(jq -r --arg id "$id" '.[] | select(.id == $id) | .clonedFrom' <<<"$list")"
    if [[ $name == notifications && $engine != omarchy ]]; then
      if [[ $enabled == true ]]; then
        fail "$id is on, but Panacea draws notifications itself (notifEngine \"$engine\"): two notification servers (omarchy plugin disable $id)"
      else
        ok "$id is off: Panacea draws notifications itself"
      fi
    elif [[ $enabled != true ]]; then
      fail "$id is not enabled (omarchy plugin enable $id)"
    elif [[ -n $want && $slot != "$want" ]]; then
      fail "$id no longer takes the $want slot: Omarchy may have changed how clones work"
    else
      ok "$id is enabled${want:+ in the $want slot}"
    fi
  done
}

# Each companion stands in for one of Omarchy's plugins. upstream/<name>/
# keeps that plugin's files as the companion was last checked against them
# (companions.sh baseline); any difference is Omarchy changing something the
# companion replaces or redraws, for `companions.sh sync` to bring in.
check_upstream() {
  local catalog name base want dir version f
  catalog="$(omarchy-plugin-catalog 2>/dev/null)"
  for name in $(companion_names); do
    want="$(jq -r '.omarchy.clonedFrom // empty' "$here/companions/$name/manifest.json")"
    [[ -n $want ]] || continue
    base="$here/upstream/$name"
    if [[ ! -d $base ]]; then
      warn "$plugin_id-$name has no baseline (scripts/companions.sh baseline $name)"
      continue
    fi
    dir="$(jq -r --arg id "$want" '.[] | select(.id == $id) | .sourceDir' <<<"$catalog")"
    if [[ ! -d $dir ]]; then
      fail "Omarchy no longer ships $want, the plugin $plugin_id-$name stands in for"
      continue
    fi
    version="$(jq -r '.omarchy' "$base.json" 2>/dev/null || echo unknown)"
    local changed=()
    for f in "$base"/*; do
      [[ -f $dir/$(basename "$f") ]] || changed+=("$(basename "$f") (gone)")
    done
    for f in "$dir"/*; do
      if [[ ! -f $base/$(basename "$f") ]]; then
        changed+=("$(basename "$f") (new)")
      elif ! cmp -s "$f" "$base/$(basename "$f")"; then
        changed+=("$(basename "$f")")
      fi
    done
    if ((${#changed[@]})); then
      warn "Omarchy changed $want since $version (${changed[*]}): run scripts/companions.sh sync $name"
    else
      ok "Omarchy's $want is as $plugin_id-$name last saw it ($version)"
    fi
  done
}

check_ipc() {
  # The targets Omarchy's own keys and scripts call, which Panacea answers.
  local target
  for target in osd notifications; do
    if answers "$target" ping; then
      ok "omarchy-shell $target answers"
    else
      fail "omarchy-shell $target does not answer: Omarchy's keys and scripts reach nothing"
    fi
  done
}

check_log() {
  local log fallback errors
  log="$(qs -p "$omarchy_path/shell" log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g')"
  fallback="$(grep -m1 "failed to load, falling back" <<<"$log" | sed 's/^ *//')"
  [[ -n $fallback ]] && fail "$fallback"
  errors="$(grep -F "$plugin_id" <<<"$log" \
    | grep -E "TypeError|ReferenceError|is not a type|is not defined|Cannot assign|Unable to assign|Error:" \
    | sed -E 's/^.*plugins\/(isaqdn\.panacea[^ ]*)/\1/' | sort | uniq -c | sort -rn)"
  if [[ -n $errors ]]; then
    warn "Panacea logged $(wc -l <<<"$errors") kinds of error since the shell started; the most frequent: $(head -1 <<<"$errors" | sed 's/^ *[0-9]* //')"
  else
    ok "No errors from Panacea in the shell log"
  fi
}

check_hyprland() {
  local errors
  errors="$(hyprctl configerrors 2>/dev/null | grep -v '^\s*$' || true)"
  if [[ -n $errors ]]; then
    warn "Hyprland reports config errors: $(head -1 <<<"$errors")"
  else
    ok "Hyprland reports no config errors"
  fi
  if grep -q ">>> panacea-omarchy >>>" "$bindings" 2>/dev/null; then
    ok "Panacea's shortcut block is in bindings.lua"
  else
    warn "Panacea's shortcut block is gone from bindings.lua (a config reset?): save the shortcuts again in Panacea"
  fi
}

write_report() {
  local mode="$1" line
  {
    echo "Panacea health check, $(date '+%Y-%m-%d %H:%M') (${mode#--})"
    echo
    for line in "${fails[@]}"; do echo "BROKEN  $line"; done
    for line in "${warns[@]}"; do echo "REVIEW  $line"; done
    for line in "${oks[@]}"; do echo "ok      $line"; done
  } >"$report"
  cat "$report"
}

notify() {
  local mode="$1"
  local send=(omarchy-notification-send --app-name Panacea)
  local open=(--exec xdg-terminal-exec less "$report")
  if ((${#fails[@]})); then
    "${send[@]}" -u critical -g "$glyph_alert" "Panacea needs attention" "${fails[0]}" "${open[@]}"
  elif ((${#warns[@]})); then
    "${send[@]}" -g "$glyph_alert" "Panacea: ${#warns[@]} to review" "${warns[0]}" "${open[@]}"
  elif [[ $mode == --after-update ]]; then
    "${send[@]}" -u low -g "$glyph_ok" "Panacea is healthy" "Checked against Omarchy $(cat "$state/omarchy-version")" "${open[@]}"
  fi
}

check() {
  local mode="${1:---by-hand}"
  mkdir -p "$state"
  check_omarchy
  # At login the shell may still be starting.
  if wait_for "$([[ $mode == --at-boot ]] && echo 60 || echo 15)" answers shell ping; then
    check_bar
    check_plugins
    check_companions
    check_upstream
    check_ipc
    check_log
  else
    fail "omarchy-shell is not answering, so Panacea could not be checked"
  fi
  check_hyprland
  write_report "$mode"
  notify "$mode"
  ((${#fails[@]})) && return 2
  ((${#warns[@]})) && return 1
  return 0
}

install_hooks() {
  omarchy hook install post-update "$here/hooks/post-update/panacea-health"
  omarchy hook install post-boot "$here/hooks/post-boot/panacea-health"
  echo "installed the post-update and post-boot hooks"
}

case "${1:-}" in
  check) check "${2:-}" ;;
  install) install_hooks ;;
  *)
    echo "usage: health.sh check [--after-update|--at-boot] | install" >&2
    exit 2
    ;;
esac
