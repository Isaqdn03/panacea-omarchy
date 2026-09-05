#!/bin/bash
# Claude Code statusline — two-line, icon-accented.
#
# Reads the statusLine JSON on stdin (schema per Claude Code v2.1.201) and
# prints a two-row bar:
#   line 1  identity + context     󰧑 model  󰉋 dir  󰘬 branch   󰍛 [bar] % · tok/size
#   line 2  limits + economics     󰔟 5h %  wk %   󰠓 cost  󰅐 dur  󰏫 +A/-R
#
# Token logic reads REAL fields (current_usage cache breakdown → total_input_tokens)
# and computes % from tokens ÷ context_window_size, honoring 1M windows — it does
# NOT back-derive tokens from a rounded percentage. Rate-limit segments are hidden
# when absent (API-key sessions). Glyphs are all present in JetBrainsMono Nerd Font.

input=$(cat)
now=$(date +%s)

# ── One jq pass → tab-separated fields (sentinels: -1 = absent/unknown) ────────
IFS=$'\t' read -r \
  model_name cwd session_id ctx_size tokens used_pct \
  rl5_pct rl5_reset rl7_pct rl7_reset \
  cost_usd duration_ms lines_added lines_removed \
  <<<"$(printf '%s' "$input" | jq -r '
    [ (.model.display_name // "Claude"),
      (.workspace.current_dir // .cwd // ""),
      (.session_id // ""),
      (.context_window.context_window_size // 200000),
      ( (.context_window.current_usage // null) as $cu
        | if $cu != null
          then (($cu.input_tokens // 0)
                + ($cu.cache_creation_input_tokens // 0)
                + ($cu.cache_read_input_tokens // 0))
          else (.context_window.total_input_tokens // -1) end ),
      (.context_window.used_percentage // -1),
      (.rate_limits.five_hour.used_percentage // -1),
      (.rate_limits.five_hour.resets_at // 0),
      (.rate_limits.seven_day.used_percentage // -1),
      (.rate_limits.seven_day.resets_at // 0),
      (.cost.total_cost_usd // -1),
      (.cost.total_duration_ms // 0),
      (.cost.total_lines_added // 0),
      (.cost.total_lines_removed // 0)
    ] | @tsv' 2>/dev/null)"

# Guard against a malformed / empty stdin (jq produced nothing).
[ -z "$ctx_size" ] && exit 0

# ── Panacea pill: лимиты наружу ───────────────────────────────────────────
# Claude Code отдаёт rate_limits только сюда, на stdin строки статуса, и
# никуда их не пишет: в ~/.claude.json их нет вовсе. Пилюле нужно то же
# число, поэтому кладём его в кэш — строка статуса выполняется на каждом
# обновлении, и файл остаётся свежим, пока сессия открыта.
#
# resets_at — epoch в секундах; по нему потребитель поймёт, что окно уже
# закрылось и старый процент врёт. Ошибки здесь глотаются целиком: строка
# статуса важнее кэша, и падать из-за него она не должна.
{
  _pan="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-claude-usage.json"
  mkdir -p "$(dirname "$_pan")" 2>/dev/null
  printf '{"five_hour_pct":%s,"five_hour_resets":%s,"seven_day_pct":%s,"seven_day_resets":%s,"at":%s}\n' \
    "${rl5_pct:--1}" "${rl5_reset%.*}" "${rl7_pct:--1}" "${rl7_reset%.*}" "$(date +%s)" \
    >"$_pan.tmp" 2>/dev/null && mv -f "$_pan.tmp" "$_pan" 2>/dev/null
} >/dev/null 2>&1 || true

# ── Catppuccin Mocha palette (truecolor) ──────────────────────────────────────
green=$'\e[38;2;166;227;161m'; yellow=$'\e[38;2;249;226;175m'
peach=$'\e[38;2;250;179;135m'; red=$'\e[38;2;243;139;168m'
blue=$'\e[38;2;137;180;250m';  mauve=$'\e[38;2;203;166;247m'
sky=$'\e[38;2;137;220;235m';   teal=$'\e[38;2;148;226;213m'
dim=$'\e[2m'; rst=$'\e[0m'

# color by usage %: <40 green, <60 yellow, <70 peach, else red (context bar)
ctx_color() { local p=${1%.*}; p=${p:-0}
  if   [ "$p" -ge 70 ] 2>/dev/null; then printf '%s' "$red"
  elif [ "$p" -ge 60 ] 2>/dev/null; then printf '%s' "$peach"
  elif [ "$p" -ge 40 ] 2>/dev/null; then printf '%s' "$yellow"
  else printf '%s' "$green"; fi; }

# color by usage %: <50 green, <80 yellow, <100 peach, else red (rate limits)
rl_color() { local p=${1%.*}; p=${p:-0}
  if   [ "$p" -ge 100 ] 2>/dev/null; then printf '%s' "$red"
  elif [ "$p" -ge 80 ]  2>/dev/null; then printf '%s' "$peach"
  elif [ "$p" -ge 50 ]  2>/dev/null; then printf '%s' "$yellow"
  else printf '%s' "$green"; fi; }

fmt_tokens() { awk -v n="$1" 'BEGIN{
  if(n<0){printf "?";exit}
  if(n<1000){printf "%d",n;exit}
  if(n<1000000){v=n/1000; if(v==int(v))printf "%dK",v; else printf "%.1fK",v; exit}
  if(n<1000000000){v=n/1000000; if(v==int(v))printf "%dM",v; else printf "%.1fM",v; exit}
  printf "%.1fB",n/1000000000 }'; }

fmt_delta() { local d=$1
  if [ "$d" -le 0 ] 2>/dev/null; then printf 'now'
  elif [ "$d" -lt 3600 ]; then printf '%dm' $((d/60))
  elif [ "$d" -lt 86400 ]; then printf '%dh%02dm' $((d/3600)) $(((d%3600)/60))
  else printf '%dd%dh' $((d/86400)) $(((d%86400)/3600)); fi; }

# ── Context: real tokens ÷ real window, no rounding-derived counts ─────────────
if [ "${tokens%.*}" -ge 0 ] 2>/dev/null && [ "${ctx_size%.*}" -gt 0 ] 2>/dev/null; then
  pct=$(awk -v t="$tokens" -v s="$ctx_size" 'BEGIN{printf "%.1f",100*t/s}')
elif [ "$used_pct" != "-1" ]; then
  pct=$(awk -v u="$used_pct" 'BEGIN{printf "%.1f",u}')
  tokens=$(awk -v u="$used_pct" -v s="$ctx_size" 'BEGIN{printf "%d",u/100*s}')
else
  pct="0.0"; tokens="-1"
fi
pct_int=${pct%.*}
filled=$(awk -v p="$pct_int" 'BEGIN{f=int(p/10); if(f>10)f=10; if(f<0)f=0; print f}')
bar=""; for ((i=0;i<filled;i++)); do bar+="█"; done
for ((i=filled;i<10;i++)); do bar+="░"; done
cc=$(ctx_color "$pct_int")

# ── Git branch (cached per session, 3s TTL — never lags the bar) ───────────────
branch=""
if [ -n "$cwd" ] && command -v git >/dev/null 2>&1; then
  cache="${TMPDIR:-/tmp}/claude-sl-branch-${session_id:-none}"
  if [ -f "$cache" ] && [ $(( now - $(stat -c %Y "$cache" 2>/dev/null || echo 0) )) -lt 3 ]; then
    branch=$(cat "$cache" 2>/dev/null)
  else
    branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf '%s' "$branch" >"$cache" 2>/dev/null
  fi
fi
[ -n "$cwd" ] && dir_display=$(basename "$cwd") || dir_display="?"

# ── Line 1: identity + context ────────────────────────────────────────────────
line1="${mauve}󰧑 ${model_name}${rst}  ${blue}󰉋 ${dir_display}${rst}"
[ -n "$branch" ] && line1+="  ${peach}󰘬 ${branch}${rst}"
line1+="   ${cc}󰍛 [${bar}] ${pct}%${rst}"
if [ "$tokens" != "-1" ]; then
  line1+=" ${dim}$(fmt_tokens "$tokens")/$(fmt_tokens "$ctx_size")${rst}"
fi

# ── Line 2: rate limits + economics ───────────────────────────────────────────
line2=""
if [ "$rl5_pct" != "-1" ]; then
  c5=$(rl_color "$rl5_pct")
  line2+="${c5}󰔟 5h ${rl5_pct%.*}%${rst}"
  [ "${rl5_reset%.*}" -gt 0 ] 2>/dev/null && line2+=" ${dim}$(fmt_delta $((rl5_reset - now)))${rst}"
fi
if [ "$rl7_pct" != "-1" ]; then
  c7=$(rl_color "$rl7_pct")
  [ -n "$line2" ] && line2+="   "
  line2+="${c7}󰸗 wk ${rl7_pct%.*}%${rst}"
  if [ "${rl7_reset%.*}" -gt 0 ] 2>/dev/null; then
    wk_reset=$(date -d "@${rl7_reset%.*}" '+%a %-I%p' 2>/dev/null || fmt_delta $((rl7_reset - now)))
    line2+=" ${dim}${wk_reset}${rst}"
  fi
fi

# cost
if [ "$cost_usd" != "-1" ]; then
  cost_str=$(awk -v c="$cost_usd" 'BEGIN{ if(c>=0.1)printf "%.2f",c; else if(c>0)printf "%.3f",c; else printf "%.2f",c }')
  [ -n "$line2" ] && line2+="   "
  line2+="${green}󰠓 ${cost_str}${rst}"
fi
# duration
elapsed=$(( ${duration_ms%.*} / 1000 ))
if [ "$elapsed" -gt 0 ] 2>/dev/null; then
  if   [ "$elapsed" -lt 60 ];   then dur="${elapsed}s"
  elif [ "$elapsed" -lt 3600 ]; then dur="$((elapsed/60))m$(printf '%02d' $((elapsed%60)))s"
  else dur="$((elapsed/3600))h$(printf '%02d' $(((elapsed%3600)/60)))m"; fi
  [ -n "$line2" ] && line2+="  "
  line2+="${dim}󰅐 ${dur}${rst}"
fi
# lines changed
if [ "${lines_added%.*}" -gt 0 ] 2>/dev/null || [ "${lines_removed%.*}" -gt 0 ] 2>/dev/null; then
  [ -n "$line2" ] && line2+="  "
  line2+="${teal}󰏫${rst} ${green}+${lines_added}${rst}${dim}/${rst}${red}-${lines_removed}${rst}"
fi

# ── Emit ──────────────────────────────────────────────────────────────────────
printf '%s' "$line1"
[ -n "$line2" ] && printf '\n%s' "$line2"
