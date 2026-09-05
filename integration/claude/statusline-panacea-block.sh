# >>> panacea-omarchy >>>
# Panacea pill: expose Claude Code's rate limits.
#
# Claude Code hands rate_limits to the statusline command on stdin and writes
# them nowhere else -- they are not in ~/.claude.json at all. The pill needs the
# same number, so mirror it into a cache: the statusline runs on every render,
# which keeps the file fresh for as long as a session is open.
#
# resets_at is an epoch in seconds, so a consumer can tell that the window has
# already closed and the old percentage is lying. Errors here are swallowed
# whole -- the statusline matters more than the cache and must not die for it.
#
# Requires rl5_pct / rl5_reset / rl7_pct / rl7_reset to be in scope. Those come
# from the shipped statusline-command.sh; pasting this block into a different
# statusline will silently write -1 unless that script defines them too.
{
  _pan="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-claude-usage.json"
  mkdir -p "$(dirname "$_pan")" 2>/dev/null
  printf '{"five_hour_pct":%s,"five_hour_resets":%s,"seven_day_pct":%s,"seven_day_resets":%s,"at":%s}\n' \
    "${rl5_pct:--1}" "${rl5_reset%.*}" "${rl7_pct:--1}" "${rl7_reset%.*}" "$(date +%s)" \
    >"$_pan.tmp" 2>/dev/null && mv -f "$_pan.tmp" "$_pan" 2>/dev/null
} >/dev/null 2>&1 || true
# <<< panacea-omarchy <<<
