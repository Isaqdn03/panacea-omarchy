#!/usr/bin/env bash
# Одна цифра про нагрузку Claude — для сегмента на пилюле, карточки в панели
# и настольного виджета.
#
# Отдельно от agents.sh нарочно. Тот опрашивает четырнадцать бинарников, ждёт
# каждый и укладывается в секунды: столько ждать можно, когда окно открыли
# руками, но не когда цифра висит на пилюле и обновляется сама. Здесь только
# jq по паре файлов — это миллисекунды, и опрашивать можно хоть раз в минуту.
#
# ГДЕ ЛЕЖАТ ДАННЫЕ. Claude Code (2.1.x) НЕ пишет нагрузку на диск: ключа
# cachedUsageUtilization в ~/.claude.json больше нет. Лимиты он отдаёт только
# на stdin команде строки состояния — полями rate_limits.five_hour и
# .seven_day. Поэтому строка состояния (~/.claude/statusline-command.sh)
# складывает их в кэш, а мы читаем оттуда. Пока сессия открыта, файл свежий.
#
# Старый путь через ~/.claude.json оставлен запасным: на другой машине или
# на прежней версии агента данные лежат там, и терять их незачем.
#
# Берём САМЫЙ ЗАГРУЖЕННЫЙ из ещё открытых лимитов, а не какой-то заранее
# выбранный: первым упрётся тот, что выше. Окно, у которого resets_at уже
# прошёл, отбрасываем целиком — там счётчик обнулился, и старый процент
# врёт.
#
# percent = -1 означает «данных нет», и это не то же самое, что ноль: ноль —
# «ничего не израсходовано», -1 — «мы не знаем». На -1 сегмент не рисуется.
set -u

none() { printf '{"percent":-1,"kind":"","severity":"","resetsAt":0,"plan":""}\n'; exit 0; }

command -v jq >/dev/null 2>&1 || none

cfg="$HOME/.claude.json"
plan=""
[ -f "$cfg" ] && plan="$(jq -r '.oauthAccount.organizationType // ""' "$cfg" 2>/dev/null || echo "")"

emit() {  # emit <percent> <kind> <resetsAtSeconds>
    local pct="$1" kind="$2" reset="$3" sev="normal"
    [ "${pct%.*}" -ge 90 ] 2>/dev/null && sev="critical"
    jq -cn --argjson p "${pct%.*}" --arg k "$kind" --arg s "$sev" \
           --argjson r "$(( ${reset:-0} * 1000 ))" --arg plan "$plan" \
        '{ percent: $p, kind: $k, severity: $s, resetsAt: $r, plan: $plan }'
    exit 0
}

# ------------------------------------------------- кэш от строки состояния
cache="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-claude-usage.json"
if [ -f "$cache" ]; then
    now="$(date +%s)"
    # Из двух окон берём то, что выше, среди ещё не сброшенных. jq отдаёт
    # «процент kind resets» одной строкой или ничего.
    top="$(jq -r --argjson now "$now" '
        [ { kind: "session",    pct: (.five_hour_pct // -1),  reset: (.five_hour_resets // 0) },
          { kind: "weekly_all", pct: (.seven_day_pct // -1),  reset: (.seven_day_resets // 0) } ]
        | map(select(.pct >= 0 and (.reset == 0 or .reset > $now)))
        | sort_by(.pct) | last
        | if . == null then empty else "\(.pct) \(.kind) \(.reset)" end
    ' "$cache" 2>/dev/null || true)"
    if [ -n "$top" ]; then
        # shellcheck disable=SC2086
        set -- $top
        emit "$1" "$2" "$3"
    fi
fi

# ----------------------------------------- запасной путь: старый ~/.claude.json
[ -f "$cfg" ] || none

# Кэш принадлежит конкретному аккаунту — при несовпадении считаем, что данных
# нет, а не приписываем одному аккаунту расход другого. Та же осторожность,
# что и в agents.sh.
acct="$(jq -r '.oauthAccount.accountUuid // ""' "$cfg" 2>/dev/null || echo "")"
cacheAcct="$(jq -r '.cachedUsageUtilization.accountUuid // ""' "$cfg" 2>/dev/null || echo "")"
[ -n "$cacheAcct" ] && [ "$cacheAcct" = "$acct" ] || none

old="$(jq -c '
    (.cachedUsageUtilization.utilization) as $u
    | ( if (($u.limits // []) | length) > 0 then
          [ $u.limits[] | select(.percent != null)
            | { kind: (.kind // "unknown"), percent: (.percent | floor),
                severity: (.severity // "normal"), resetsAtIso: (.resets_at // "") } ]
        else
          [ { kind: "session", v: $u.five_hour }, { kind: "weekly_all", v: $u.seven_day } ]
          | map(select(.v != null and .v.utilization != null))
          | map({ kind: .kind, percent: (.v.utilization | floor),
                  severity: "normal", resetsAtIso: (.v.resets_at // "") })
        end )
    | sort_by(.percent) | last // empty
' "$cfg" 2>/dev/null || echo "")"

[ -n "$old" ] && [ "$old" != "null" ] || none

iso="$(printf '%s' "$old" | jq -r '.resetsAtIso // ""')"
ms=0
[ -n "$iso" ] && [ "$iso" != "null" ] && ms="$(date -d "$iso" +%s%3N 2>/dev/null || echo 0)"

printf '%s' "$old" | jq -c --arg plan "$plan" --argjson ms "${ms:-0}" \
    'del(.resetsAtIso) | .resetsAt = $ms | .plan = $plan'
