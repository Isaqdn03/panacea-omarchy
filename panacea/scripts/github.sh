#!/usr/bin/env bash
# Собирает всё, что остров показывает про GitHub, в один JSON.
#
# Отдельным скриптом по той же причине, что и agents.sh: данные лежат в чужом
# сервисе, у каждого запроса свой формат ответа, и приводить их к одной форме
# лучше здесь, чем в QML. Вид рисует то, что дали, и ничего не знает про gh.
#
# Три раздела, ровно те, за которыми сюда ходят:
#   inbox   — что ждёт лично меня: уведомления, запросы на ревью, назначенное
#   repo    — репозиторий окна, которое сейчас в фокусе: ветка, PR, последний прогон
#   actions — последний прогон в каждом из недавно тронутых репозиториев
#
# Наружу не идёт ничего, кроме имён репозиториев и заголовков: островом
# пользуются при включённой демонстрации экрана.
set -u

CACHE="${TMPDIR:-/tmp}/panacea-github-$(id -u).json"
TTL=60

fail() { printf '{"now":%s,"error":"%s","inbox":{},"repo":{"found":false},"actions":[]}\n' \
                "$(date +%s%3N)" "$1"; exit 0; }

command -v jq >/dev/null 2>&1 || fail jq

# Путь до gh ищем сами: остров стартует из автозапуска компоновщика, а туда
# профиль оболочки со своим PATH доходит не всегда.
#
# И, главное, ~/.local/bin/gh здесь — не сам gh, а обёртка mise, которая перед
# запуском печатает в СТАНДАРТНЫЙ ВЫВОД строку про версию инструмента. Она
# попадала в начало каждого ответа, и jq спотыкался на ней на каждом запросе:
# в JSON приезжало «mise ~/.config/mise/config.toml tools: gh@2.98.0» вместо
# данных. Поэтому у mise спрашиваем настоящий бинарник и зовём уже его.
GH=""
if command -v mise >/dev/null 2>&1; then
    GH="$(mise which gh 2>/dev/null || true)"
    [ -n "$GH" ] && [ -x "$GH" ] || GH=""
fi
if [ -z "$GH" ]; then
    for c in /usr/bin/gh /usr/local/bin/gh "$HOME/.local/bin/gh"; do
        [ -x "$c" ] && { GH="$c"; break; }
    done
fi
[ -n "$GH" ] || GH="$(command -v gh 2>/dev/null || true)"
[ -n "$GH" ] || fail nogh

# Кэш: страницу открывают чаще, чем меняются цифры, а каждый заход — это
# десяток сетевых запросов. Свежий ответ отдаём как есть; за новым ходим
# только когда старому больше минуты. `--force` обходит кэш.
MODE="${1:-}"

# `--cached` отдаёт кэш ЛЮБОГО возраста и в сеть не ходит вовсе. Вид зовёт его
# на открытии, чтобы показать хоть что-то мгновенно, и следом пускает `--force`
# в фоне. Без этого страница висела пустой ~3 с на каждом открытии позже, чем
# через минуту после прошлого: кэш успевал протухнуть, а показывать до конца
# запросов было нечего. Если кэша нет вовсе — проваливаемся в общий путь.
if [ "$MODE" = "--cached" ]; then
    if [ -f "$CACHE" ] && jq -e . "$CACHE" >/dev/null 2>&1; then
        cat "$CACHE"
    fi
    # Кэша нет — молчим и в сеть НЕ идём. Пустой вывод вид пропускает, а за
    # данными сходит второй процесс. Иначе холодный старт слал бы два
    # одинаковых веера запросов сразу.
    exit 0
fi

if [ "$MODE" != "--force" ] && [ -f "$CACHE" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$CACHE" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$TTL" ] && jq -e . "$CACHE" >/dev/null 2>&1; then
        cat "$CACHE"; exit 0
    fi
fi

# Каждый запрос под таймаутом. Один висящий вызов уже вешал окно агентов
# целиком — там это был `crush --version`, здесь это была бы сеть.
gh() { timeout 12 "$GH" "$@" 2>/dev/null; }

gh auth status >/dev/null 2>&1 || fail noauth
USER_LOGIN="$(gh api user --jq '.login' || true)"
[ -n "$USER_LOGIN" ] || fail noauth

# ----------------------------------------------------------------- входящие
# Уведомления по умолчанию приходят только непрочитанные — именно это и нужно.
# Заголовок берём из subject, репозиторий из repository: URL в ответе ведёт в
# API, а не на сайт, и открывать его человеку бессмысленно.
#
# All pages, not just the first: the API returns 50 by default, so the pill
# sat at exactly 50. Two reasons are dropped because they only echo your own
# actions: ci_activity (a workflow you triggered finished; the actions section
# below already shows runs) and state_change (you merged or closed something).
# On 2026-10-15 they were 71 of 75 unread.
notif="$(gh api 'notifications?per_page=100' --paginate --slurp | jq '
    [ add // [] | .[]
      | select(.reason != "ci_activity" and .reason != "state_change")
      | { kind: "notification",
          title: .subject.title,
          repo: .repository.full_name,
          reason: .reason,
          url: "https://github.com/notifications",
          updated: .updated_at } ]' || echo '[]')"

reviews="$(gh search prs --review-requested=@me --state=open --limit 15 \
             --json number,title,repository,url,updatedAt --jq '
    [ .[] | { kind: "review",
              title: .title,
              repo: .repository.nameWithOwner,
              number: .number,
              url: .url,
              updated: .updatedAt } ]' || echo '[]')"

assigned="$(gh search issues --assignee=@me --state=open --limit 15 \
              --json number,title,repository,url,updatedAt --jq '
    [ .[] | { kind: "assigned",
              title: .title,
              repo: .repository.nameWithOwner,
              number: .number,
              url: .url,
              updated: .updatedAt } ]' || echo '[]')"

# Пустой ответ и сломанный ответ выглядят одинаково — оба должны стать пустым
# списком, иначе jq ниже упадёт на всём разделе из-за одного запроса.
ok_json() { [ -n "${1:-}" ] && jq -e . <<< "$1" >/dev/null 2>&1; }
ok_json "$notif"    || notif='[]'
ok_json "$reviews"  || reviews='[]'
ok_json "$assigned" || assigned='[]'

inbox="$(jq -cn --argjson n "$notif" --argjson r "$reviews" --argjson a "$assigned" '
    { notifications: ($n | length),
      reviews:       ($r | length),
      assigned:      ($a | length),
      total:         (($n | length) + ($r | length) + ($a | length)),
      items:         (($n + $r + $a) | sort_by(.updated) | reverse | .[0:6]) }')"

# ------------------------------------------------------- репозиторий в фокусе
# Какой репозиторий «текущий» — вопрос без общего ответа, поэтому берём тот, в
# котором стоит окно с фокусом: у терминала это его каталог. Спускаемся от
# процесса окна к самому глубокому потомку — у оболочки в терминале свой cwd,
# и он отличается от того, с которым терминал запускали.
focus_cwd() {
    # Проверять раздел, зависящий от фокуса, иначе нечем: окно с фокусом не
    # подставишь. Переменная — единственный способ сказать скрипту «считай,
    # что человек стоит здесь», и она же выручает при разборе жалоб.
    [ -n "${PANACEA_GH_CWD:-}" ] && { printf '%s' "$PANACEA_GH_CWD"; return 0; }
    command -v hyprctl >/dev/null 2>&1 || return 1
    local pid; pid="$(hyprctl activewindow -j 2>/dev/null | jq -r '.pid // empty')"
    [ -n "$pid" ] && [ "$pid" != "null" ] && [ "$pid" -gt 0 ] 2>/dev/null || return 1

    # Вглубь по дереву процессов: у терминала это оболочка, у оболочки —
    # то, что она сейчас выполняет. Каталог последнего и есть тот, где человек
    # работает. Ограничение на глубину — от циклов в подделанном /proc.
    local cur="$pid" depth=0 child
    while [ "$depth" -lt 12 ]; do
        child="$(pgrep -P "$cur" 2>/dev/null | tail -1)"
        [ -n "$child" ] || break
        cur="$child"; depth=$((depth + 1))
    done
    readlink -f "/proc/$cur/cwd" 2>/dev/null
}

repo_json='{"found":false}'
cwd="$(focus_cwd || true)"
if [ -n "${cwd:-}" ] && [ -d "$cwd" ]; then
    top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$top" ]; then
        branch="$(git -C "$top" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
        dirty="$(git -C "$top" status --porcelain 2>/dev/null | wc -l)"
        # ahead/behind считаем только когда у ветки есть upstream: без него
        # rev-list ругается, а «0/0» было бы неправдой.
        ahead=0; behind=0
        if git -C "$top" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
            set -- $(git -C "$top" rev-list --left-right --count 'HEAD...@{upstream}' 2>/dev/null || echo "0 0")
            ahead="${1:-0}"; behind="${2:-0}"
        fi

        # gh repo view смотрит на каталог, в котором его запустили
        nwo="$(cd "$top" && timeout 8 "$GH" repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null || true)"

        pr='null'; run='null'
        if [ -n "$nwo" ]; then
            pr="$(cd "$top" && timeout 10 "$GH" pr view --json number,title,state,isDraft,reviewDecision,url \
                    2>/dev/null || echo null)"
            [ -n "$pr" ] || pr='null'
            run="$(cd "$top" && timeout 10 "$GH" run list -b "$branch" -L 1 \
                    --json displayTitle,status,conclusion,workflowName,updatedAt --jq '.[0] // null' \
                    2>/dev/null || echo null)"
            [ -n "$run" ] || run='null'
        fi

        repo_json="$(jq -cn --arg path "$top" --arg nwo "$nwo" --arg branch "$branch" \
                            --argjson ahead "${ahead:-0}" --argjson behind "${behind:-0}" \
                            --argjson dirty "${dirty:-0}" \
                            --argjson pr "$pr" --argjson run "$run" '
            { found: true, path: $path, nameWithOwner: $nwo, branch: $branch,
              ahead: $ahead, behind: $behind, dirty: $dirty, pr: $pr, run: $run }')"
    fi
fi

# ---------------------------------------------------------------- прогоны CI
# Общего «дай все мои прогоны» в API нет, поэтому берём недавно тронутые
# репозитории и спрашиваем каждый по одному прогону. Восемь — столько, чтобы
# уложиться в секунду; параллельно, иначе это восемь задержек подряд.
repos="$(gh api '/user/repos?sort=pushed&per_page=8&affiliation=owner' --jq '.[].full_name' || true)"
actions='[]'
if [ -n "${repos:-}" ]; then
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/panacea-gh-XXXXXX")"
    i=0
    while IFS= read -r r; do
        [ -n "$r" ] || continue
        i=$((i + 1))
        (
            one="$(timeout 10 "$GH" run list -R "$r" -L 1 \
                     --json displayTitle,status,conclusion,workflowName,headBranch,updatedAt \
                     --jq '.[0] // empty' 2>/dev/null || true)"
            [ -n "$one" ] && printf '%s' "$one" \
                | jq -c --arg repo "$r" '. + { repo: $repo }' > "$tmp/$i.json"
        ) &
    done <<< "$repos"
    wait
    actions="$(cat "$tmp"/*.json 2>/dev/null | jq -sc 'sort_by(.updatedAt) | reverse' || echo '[]')"
    rm -rf "$tmp"
fi
[ -n "$actions" ] && jq -e . <<< "$actions" >/dev/null 2>&1 || actions='[]'

out="$(jq -cn --argjson now "$(date +%s%3N)" --arg user "$USER_LOGIN" \
              --argjson inbox "$inbox" --argjson repo "$repo_json" --argjson actions "$actions" '
    { now: $now, error: "", user: $user, inbox: $inbox, repo: $repo, actions: $actions }')"

printf '%s' "$out" > "$CACHE"
printf '%s\n' "$out"
