#!/usr/bin/env bash
# Собирает сведения об установленных ИИ-агентах в один JSON для острова.
#
# Почему отдельным скриптом, а не разбором в QML: данные лежат в чужих файлах
# чужого формата, и каждый агент хранит их по-своему. Здесь это приводится к
# одной форме, и вид рисует её, ничего не зная про то, кто где что держит.
#
# Что НЕ выводится: почта, имя учётной записи, идентификаторы организации и
# аккаунта. Окно показывает нагрузку и тариф, а не то, чей это аккаунт, —
# островом пользуются при включённой демонстрации экрана.
#
# Подписи лимитов здесь не переводятся: наружу идёт устойчивый ключ (kind), а
# человеческое название подставляет вид — иначе смена языка интерфейса не
# доходила бы до этого окна.
set -u

command -v jq >/dev/null 2>&1 || { printf '{"agents":[],"error":"jq"}\n'; exit 0; }

# ISO 8601 -> миллисекунды эпохи. У Claude в resets_at шесть знаков после
# запятой; JS такую дробную часть местами разбирает как попало, поэтому
# считаем здесь, где есть date(1), и отдаём наружу число.
iso_ms() {
    [ -n "${1:-}" ] && [ "$1" != "null" ] || { echo "0"; return; }
    date -d "$1" +%s%3N 2>/dev/null || echo "0"
}

# ------------------------------------------------------------------ claude
claude_json() {
    local cfg="$HOME/.claude.json"
    local bin; bin="$(command -v claude 2>/dev/null)"
    [ -n "$bin" ] || [ -f "$cfg" ] || return 1

    local ver=""
    [ -n "$bin" ] && ver="$(timeout 2 "$bin" --version 2>/dev/null | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')"

    local plan="" raw="" fetched=0
    if [ -f "$cfg" ]; then
        raw="$(jq -r '.oauthAccount.organizationType // ""' "$cfg" 2>/dev/null)"
        fetched="$(jq -r '.cachedUsageUtilization.fetchedAtMs // 0' "$cfg" 2>/dev/null)"
    fi

    # Известные значения переводим в то, как тариф называется на сайте.
    # Неизвестное не прячем и не выдумываем: "claude_max_40x" превратится в
    # "Claude Max 40x" и будет видно, что появился тариф, которого здесь ещё
    # не знают, — это честнее пустого места.
    case "$raw" in
        claude_pro)        plan="Claude Pro" ;;
        claude_max_5x)     plan="Claude Max 5x" ;;
        claude_max_20x)    plan="Claude Max 20x" ;;
        claude_team)       plan="Claude Team" ;;
        claude_enterprise) plan="Claude Enterprise" ;;
        "")                plan="" ;;
        *)                 plan="$(printf '%s' "$raw" | sed 's/_/ /g' | sed 's/\b\(.\)/\u\1/g')" ;;
    esac

    # Кэш нагрузки принадлежит КОНКРЕТНОМУ аккаунту, и это записано в нём
    # самом. При смене аккаунта Claude Code либо стирает кэш целиком, либо
    # какое-то время держит старый — до первого запроса от нового. Показать
    # его как текущий значило бы приписать одному аккаунту расход другого,
    # поэтому сверяем accountUuid и при несовпадении считаем, что данных нет.
    local acct cacheAcct
    acct="$(jq -r '.oauthAccount.accountUuid // ""' "$cfg" 2>/dev/null)"
    cacheAcct="$(jq -r '.cachedUsageUtilization.accountUuid // ""' "$cfg" 2>/dev/null)"

    local limits='[]'
    if [ -f "$cfg" ] && [ -n "$cacheAcct" ] && [ "$cacheAcct" = "$acct" ]; then
        # limits[] — готовый список, каким его прислал сервер: и пятичасовое
        # окно, и недельное, и всё, что добавят потом. Берём его целиком, а не
        # два заранее известных поля, чтобы новые лимиты появились сами.
        #
        # Запасной путь — те самые two поля: у старых версий Claude Code
        # массива limits ещё нет, а five_hour и seven_day уже есть.
        limits="$(jq -c '
            (.cachedUsageUtilization.utilization) as $u
            | if (($u.limits // []) | length) > 0 then
                [ $u.limits[]
                  | select(.percent != null)
                  | { kind: (.kind // "unknown"),
                      percent: (.percent | floor),
                      severity: (.severity // "normal"),
                      resetsAtIso: (.resets_at // "") } ]
              else
                [ { kind: "session",    v: $u.five_hour },
                  { kind: "weekly_all", v: $u.seven_day } ]
                | map(select(.v != null and .v.utilization != null))
                | map({ kind: .kind,
                        percent: (.v.utilization | floor),
                        severity: "normal",
                        resetsAtIso: (.v.resets_at // "") })
              end
        ' "$cfg" 2>/dev/null)" || limits='[]'
    fi
    [ -n "$limits" ] && [ "$limits" != "null" ] || limits='[]'

    # PANACEA-LOCAL. Claude Code 2.1.x не пишет нагрузку в ~/.claude.json вовсе:
    # rate_limits он отдаёт ТОЛЬКО на stdin команде строки состояния. Поэтому
    # строка состояния складывает их в кэш (см. usage_brief.sh и
    # ~/.claude/statusline-command.sh), и если выше ничего не нашлось — берём
    # оттуда. Окно с истёкшим resets_at отбрасываем: счётчик там уже обнулился,
    # и старый процент соврал бы.
    local ucache="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-claude-usage.json"
    if [ "$limits" = "[]" ] && [ -f "$ucache" ]; then
        local fresh
        fresh="$(jq -c --argjson now "$(date +%s)" '
            [ { kind: "session",    percent: (.five_hour_pct // -1), reset: (.five_hour_resets // 0) },
              { kind: "weekly_all", percent: (.seven_day_pct // -1), reset: (.seven_day_resets // 0) } ]
            | map(select(.percent >= 0 and (.reset == 0 or .reset > $now)))
            | map({ kind, percent: (.percent | floor), severity: "normal",
                    resetsAtIso: "", resetsAtSec: .reset })
        ' "$ucache" 2>/dev/null || echo '[]')"
        if [ -n "$fresh" ] && [ "$fresh" != "[]" ] && [ "$fresh" != "null" ]; then
            limits="$fresh"
            # Свежесть — это возраст кэша: сам файл и есть отметка времени.
            fetched="$(( $(stat -c %Y "$ucache" 2>/dev/null || echo 0) * 1000 ))"
        fi
    fi

    # Почему лимитов нет — вопрос не праздный: «агент их не отдаёт» и «данных
    # ещё не приехало» выглядят одинаково, а значат противоположное. Первое
    # навсегда, второе пройдёт само, как только агент поработает.
    local note=""
    [ "$limits" = "[]" ] && note="nodata"

    # Дату превращаем в число здесь: в jq нет разбора дробных секунд.
    local out='[]' i=0 n
    n="$(printf '%s' "$limits" | jq 'length')"
    while [ "$i" -lt "${n:-0}" ]; do
        local one iso ms
        one="$(printf '%s' "$limits" | jq -c ".[$i]")"
        iso="$(printf '%s' "$one" | jq -r '.resetsAtIso')"
        ms="$(iso_ms "$iso")"
        # PANACEA-LOCAL: путь через кэш строки состояния отдаёт epoch в
        # секундах, а не ISO.
        if [ "${ms:-0}" = "0" ]; then
            local sec; sec="$(printf '%s' "$one" | jq -r '.resetsAtSec // 0')"
            [ "${sec:-0}" -gt 0 ] 2>/dev/null && ms="$(( sec * 1000 ))"
        fi
        out="$(printf '%s' "$out" | jq -c --argjson one "$one" --argjson ms "${ms:-0}" \
               '. + [ ($one | del(.resetsAtIso) | del(.resetsAtSec) | .resetsAt = $ms) ]')"
        i=$((i + 1))
    done

    jq -cn --arg name "Claude Code" --arg ver "$ver" --arg plan "$plan" \
           --arg note "$note" \
           --argjson fetched "${fetched:-0}" --argjson limits "$out" '
        { id: "claude", name: $name, version: $ver, plan: $plan,
          note: $note, fetchedAt: $fetched, limits: $limits }'
}

# -------------------------------------------------------------------- codex
# Тариф Codex лежит в токене OpenAI: auth.json хранит JWT, а внутри него, в
# полезной нагрузке, есть chatgpt_plan_type. Достаём только это поле — сам
# токен наружу не идёт ни в каком виде.
codex_plan() {
    local auth="$HOME/.codex/auth.json"
    [ -f "$auth" ] || return 0
    local tok; tok="$(jq -r '.tokens.id_token // ""' "$auth" 2>/dev/null)"
    [ -n "$tok" ] && [ "$tok" != "null" ] || return 0

    # средняя часть JWT — base64url без выравнивания, добиваем '=' сами
    local body; body="$(printf '%s' "$tok" | cut -d. -f2)"
    [ -n "$body" ] || return 0
    case $(( ${#body} % 4 )) in 2) body="$body==" ;; 3) body="$body=" ;; esac

    local raw; raw="$(printf '%s' "$body" | tr '_-' '/+' | base64 -d 2>/dev/null \
        | jq -r '.["https://api.openai.com/auth"].chatgpt_plan_type // ""' 2>/dev/null)"
    case "$raw" in
        plus)  echo "ChatGPT Plus" ;;
        pro)   echo "ChatGPT Pro" ;;
        team)  echo "ChatGPT Team" ;;
        enterprise) echo "ChatGPT Enterprise" ;;
        free)  echo "ChatGPT Free" ;;
        "")    ;;
        *)     printf 'ChatGPT %s\n' "$(printf '%s' "$raw" | sed 's/\b\(.\)/\u\1/g')" ;;
    esac
}

# ------------------------------------------------- остальные агенты в системе
# Тариф читается там, где до него можно дотянуться; лимиты наружу не отдаёт
# сейчас никто, кроме Claude. Пустой список вид рисует как «нет данных», а не
# как нулевую нагрузку — разница важная: ноль означал бы, что не израсходовано
# ничего, а на деле мы просто не знаем.
#
# Список именно перечислением, а не «всё, что похоже на агента»: под общий
# шаблон попадает слишком много постороннего, а промахнуться именем дешевле,
# чем показать в окне случайный бинарник.
other_agent() {
    local bin="$1" name="$2" plan="${3:-}"
    command -v "$bin" >/dev/null 2>&1 || return 1
    # PANACEA-LOCAL: `crush --version` не возвращается никогда, а copilot думает
    # пять секунд. Один зависший бинарник вешал весь скрипт, и окно агентов не
    # открывалось вовсе. Версия — не та цифра, ради которой стоит ждать.
    local ver; ver="$(timeout 2 "$bin" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
    jq -cn --arg id "$bin" --arg name "$name" --arg ver "$ver" --arg plan "$plan" '
        { id: $id, name: $name, version: $ver, plan: $plan,
          note: "unsupported", fetchedAt: 0, limits: [] }'
}

agents='[]'
add() {
    local one="$1"
    [ -n "$one" ] || return 0
    agents="$(printf '%s' "$agents" | jq -c --argjson one "$one" '. + [$one]')"
}

# PANACEA-LOCAL: опрос версий стоил 3.2 с на КАЖДЫЙ запуск, и 3.0 из них —
# три бинарника с тяжёлым стартом среды: gemini (1.7 с), opencode (0.7 с),
# copilot (0.6 с). Причём вид дёргает скрипт не только на открытии: раз в 20 с
# по таймеру и на каждую правку ~/.claude.json, то есть на каждую отрисовку
# строки состояния Claude Code. Версия и тариф меняются при обновлении CLI —
# раз в неделю, — поэтому держим их в кэше. Нагрузка Claude, единственное живое
# число на этой странице, считается каждый раз заново. `--force` обходит кэш;
# после обновления CLI версия догонит сама, но не позже, чем через TTL.
#
# PANACEA-LOCAL: кэш лежал в /tmp, а /tmp чистится на каждой загрузке. Пустой
# кэш — это опрос с нуля, ~8 с (crush, copilot и cursor-agent упираются в
# timeout по 2 с каждый), и всё это время окно агентов стояло пустым. Хуже
# того: закрытие окна убивает скрипт раньше, чем тот успевал записать кэш, и
# следующее открытие начинало те же 8 с заново — окно не открывалось никогда.
# Поэтому кэш теперь в ~/.cache, а устаревший отдаётся сразу и обновляется в
# фоне (см. --probe ниже).
OTHERS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/panacea-agents.json"
OTHERS_TTL=21600   # 6 ч

others='[]'
oadd() {
    local one="$1"
    [ -n "$one" ] || return 0
    others="$(printf '%s' "$others" | jq -c --argjson one "$one" '. + [$one]')"
}

probe_others() {
    oadd "$(other_agent codex        "Codex CLI"     "$(codex_plan)" || true)"
    oadd "$(other_agent antigravity  "Antigravity"   || true)"
    oadd "$(other_agent gemini       "Gemini CLI"    || true)"
    oadd "$(other_agent opencode     "OpenCode"      || true)"
    oadd "$(other_agent cursor-agent "Cursor Agent"  || true)"
    oadd "$(other_agent windsurf     "Windsurf"      || true)"
    oadd "$(other_agent copilot      "GitHub Copilot" || true)"
    oadd "$(other_agent amp          "Amp"           || true)"
    oadd "$(other_agent aider        "Aider"         || true)"
    oadd "$(other_agent goose        "Goose"         || true)"
    oadd "$(other_agent crush        "Crush"         || true)"
    oadd "$(other_agent droid        "Droid"         || true)"
    oadd "$(other_agent openhands    "OpenHands"     || true)"
    oadd "$(other_agent qwen         "Qwen Code"     || true)"
}

# Запись через временный файл: вид может прочитать кэш посреди записи.
save_others() {
    mkdir -p "${OTHERS_CACHE%/*}" 2>/dev/null
    printf '%s' "$others" >"$OTHERS_CACHE.$$" 2>/dev/null \
        && mv -f "$OTHERS_CACHE.$$" "$OTHERS_CACHE" 2>/dev/null \
        || rm -f "$OTHERS_CACHE.$$"
}

# Фоновый опрос. Своя сессия (setsid) — чтобы закрытие окна не убило и его;
# flock — чтобы таймер вида, дёргающий скрипт раз в 20 с, не наплодил
# параллельных опросов, пока первый ещё идёт.
if [ "${1:-}" = "--probe" ]; then
    mkdir -p "${OTHERS_CACHE%/*}" 2>/dev/null
    exec 9>"$OTHERS_CACHE.lock"
    flock -n 9 || exit 0
    probe_others
    save_others
    exit 0
fi

cached=''; stale=1
if [ -f "$OTHERS_CACHE" ] && jq -e . "$OTHERS_CACHE" >/dev/null 2>&1; then
    cached="$(cat "$OTHERS_CACHE")"
    age=$(( $(date +%s) - $(stat -c %Y "$OTHERS_CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$OTHERS_TTL" ] && stale=0
fi

if [ "${1:-}" = "--force" ]; then
    probe_others
    save_others
else
    # Устаревшее лучше пустого: версии меняются раз в неделю, а пустое окно и
    # было тем, из-за чего страница казалась сломанной.
    [ -n "$cached" ] && others="$cached"
    [ "$stale" = 1 ] && setsid -f bash "$0" --probe </dev/null >/dev/null 2>&1
fi

add "$(claude_json || true)"
agents="$(printf '%s' "$agents" | jq -c --argjson o "$others" '. + $o')"

printf '%s' "$agents" | jq -c --argjson now "$(date +%s%3N)" '{ now: $now, agents: . }'
