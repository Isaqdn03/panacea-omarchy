#!/bin/bash
# Помощник для Wi-Fi на iwd (в системе нет NetworkManager).
#
#   status            -> RADIO|SSID|QUALITY      (RADIO = on|off)
#   list              -> строки  connected|ssid|security|quality|known
#   scan              -> запускает поиск сетей
#   toggle            -> включает/выключает радио
#   connect SSID [PW] -> подключение (PW нужен только для незнакомых сетей)
#   disconnect        -> отключиться от текущей сети
#   forget SSID       -> забыть сеть (и отключиться, если она сейчас активна)

# Все беспроводные интерфейсы машины. Имя может быть любым: wlan0 там, где
# ядро их не переименовывает, wlp2s0 и подобное — почти везде ещё, а на
# машине с двумя адаптерами их и вовсе несколько. Список берём из sysfs:
# каталог wireless есть ровно у беспроводных, и для этого не нужен ни iw,
# ни права.
iface_list() {
    [ -n "${WIFI_IFACE:-}" ] && { printf '%s\n' "$WIFI_IFACE"; return; }
    local d n
    for d in /sys/class/net/*; do
        [ -d "$d/wireless" ] || continue
        n=$(basename "$d")
        printf '%s\n' "$n"
    done
}

# Тот, что сейчас связан; если связи нет ни у одного — первый по списку.
# Спрашивать «какой интерфейс» бессмысленно без ответа «а что на нём»:
# у ноутбука с внешним свистком угадывание по имени промахивается.
active_iface() {
    local i
    for i in $(iface_list); do
        [ -n "$(ssid_on "$i")" ] && { printf '%s' "$i"; return; }
    done
    iface_list | head -1
}

# iwctl раскрашивает вывод — убираем escape-последовательности
strip() { sed 's/\x1b\[[0-9;]*m//g'; }

radio_state() {
    rfkill list wifi 2>/dev/null | grep -q 'Soft blocked: no' && echo on || echo off
}

# Имя сети на конкретном интерфейсе. Спрашиваем по очереди у трёх источников:
# они дают один и тот же ответ, но есть не везде. `iw` идёт первым — он читает
# состояние прямо у ядра и не зависит от того, кто именно управляет сетью;
# дальше iwd и NetworkManager, каждый знает только про себя.
#
# Порядок важен и тем, что `iw` отвечает сразу после установления связи, тогда
# как остальные обновляют своё состояние с задержкой — из-за неё имя сети
# появлялось только после ручного сканирования.
ssid_on() {
    local i="$1" out

    out=$(iw dev "$i" link 2>/dev/null | sed -n 's/.*SSID: //p' | sed 's/ *$//')
    [ -n "$out" ] && { printf '%s' "$out"; return; }

    out=$(iwctl station "$i" show 2>/dev/null | strip \
          | sed -n 's/.*Connected network[[:space:]]*//p' | sed 's/ *$//')
    [ -n "$out" ] && { printf '%s' "$out"; return; }

    out=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null \
          | sed -n 's/^yes://p' | head -1)
    printf '%s' "$out"
}

# Интерфейс выбираем здесь, а не выше: active_iface спрашивает ssid_on, и
# та должна быть уже объявлена.
IFACE="$(active_iface)"
IFACE="${IFACE:-wlan0}"

current_ssid() { ssid_on "$IFACE"; }

# уровень сигнала в dBm -> проценты
current_quality() {
    local d
    d=$(iw dev "$IFACE" link 2>/dev/null | sed -n 's/.*signal: \(-[0-9]*\).*/\1/p')
    if [ -z "$d" ]; then
        # без iw остаётся то, что записало ядро: третья колонка /proc — это
        # качество связи по шкале драйвера, ноль там означает «нет данных»
        d=$(awk -v i="$IFACE:" '$1==i {gsub(/\./,"",$3); print $3; exit}' \
            /proc/net/wireless 2>/dev/null)
        [ -n "$d" ] && [ "$d" -gt 0 ] 2>/dev/null && { echo "$d"; return; }
        echo 0; return
    fi
    awk -v d="$d" 'BEGIN{q=2*(d+100); if(q>100)q=100; if(q<0)q=0; print int(q)}'
}

known_networks() {
    iwctl known-networks list 2>/dev/null | strip \
        | awk 'NR>4 && NF { sub(/^[[:space:]]+/,"");
               if (match($0, /[[:space:]][[:space:]]+(psk|open|8021x|wep)/)) {
                   print substr($0, 1, RSTART-1)
               } }' \
        | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------- PANACEA-LOCAL
# На этой машине сетями заведует NetworkManager, а iwd снесён вместе с
# iwctl. Всё, что ниже, спрашивало именно у iwctl — и молча получало
# пустоту: `list` не выдавал ни строки, и меню показывало «Сети не
# найдены» при живом, подключённом и прекрасно работающем Wi-Fi.
#
# Отсюда — ветка на nmcli, которая включается, только когда NetworkManager
# действительно запущен. Она берёт на себя ровно те команды, что упирались
# в iwctl; `status` оставлен общему коду ниже — он читает состояние у ядра
# через `iw` и работает при любом менеджере.
if command -v nmcli >/dev/null 2>&1 \
   && [ "$(nmcli -t -f RUNNING general 2>/dev/null)" = "running" ]; then

    # Интерфейс спрашиваем у самого NetworkManager: связанный, а если связи
    # нет ни у одного — первый беспроводной.
    nm_iface() {
        [ -n "${WIFI_IFACE:-}" ] && { printf '%s' "$WIFI_IFACE"; return; }
        nmcli -t -f DEVICE,TYPE,STATE device 2>/dev/null | awk -F: '
            $2 == "wifi" {
                if ($3 == "connected") { print $1; done = 1; exit }
                if (first == "") first = $1
            }
            END { if (!done && first != "") print first }'
    }
    NMIF="$(nm_iface)"

    # В терсе nmcli экранирует двоеточия обратным слешем — снимаем.
    nm_unesc() { sed 's/\\\(.\)/\1/g'; }

    # UUID сохранённых беспроводных профилей.
    nm_saved() {
        nmcli -t -f UUID,TYPE connection show 2>/dev/null \
            | awk -F: '$2 == "802-11-wireless" { print $1 }'
    }

    # SSID сохранённых сетей. Имя профиля — не имя сети: профиль можно
    # переименовать, и тогда «сохранена» стояло бы не у той строки.
    nm_known() {
        local u
        nm_saved | while IFS= read -r u; do
            nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | nm_unesc
        done
    }

    case "$1" in
    scan)
        # Скан сразу после предыдущего NetworkManager запрещает. Это не
        # ошибка: у вида просто останется список с прошлого раза.
        nmcli device wifi rescan ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        exit 0
        ;;

    list)
        # --rescan no: отдаём то, что уже в кэше. Сканирование — отдельная
        # команда, и ждать его здесь значило бы держать меню пустым лишние
        # секунды на каждом открытии.
        nmcli -t -f IN-USE,SIGNAL,SECURITY,SSID device wifi list --rescan no 2>/dev/null \
        | awk -v known="$(nm_known)" '
        # Поля режем вручную: SSID может содержать двоеточие, приезжает оно
        # экранированным, и обычный split по ":" разорвал бы имя пополам.
        function cut(line, out,   i, c, n, fld) {
            n = 1; fld = ""
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "\\") { i++; fld = fld substr(line, i, 1); continue }
                if (c == ":" && n < 4) { out[n++] = fld; fld = ""; continue }
                fld = fld c
            }
            out[n] = fld
        }
        BEGIN {
            n = split(known, arr, "\n")
            for (i = 1; i <= n; i++) if (arr[i] != "") isKnown[arr[i]] = 1
        }
        {
            delete f
            cut($0, f)
            name = f[4]
            if (name == "") next          # скрытая сеть: в меню жать не на что

            sec = f[3]
            if (sec == "") s = "open"
            else if (index(sec, "802.1X")) s = "8021x"
            else if (tolower(sec) ~ /wep/) s = "wep"
            else s = "psk"

            q = f[2] + 0
            # Одна сеть — несколько точек: в меню нужна одна строка, и
            # сигнал у неё лучший из всех.
            if (!(name in best)) { order[++m] = name; best[name] = q; sech[name] = s }
            else if (q > best[name]) best[name] = q
            if (f[1] ~ /\*/) conn[name] = 1
        }
        END {
            for (i = 1; i <= m; i++) {
                name = order[i]
                print (conn[name] ? "yes" : "no") "|" name "|" sech[name] "|" \
                      best[name] "|" (isKnown[name] ? "yes" : "no")
            }
        }'
        exit 0
        ;;

    toggle)
        # Через nmcli, а не rfkill: NetworkManager держит свой флаг радио
        # отдельно, и погашенный только по rfkill он потом сам не поднимет.
        # Мягкую блокировку `radio wifi off` ставит тоже, так что radio_state
        # выше видит результат.
        if [ "$(nmcli radio wifi 2>/dev/null)" = "enabled" ]; then
            nmcli radio wifi off >/dev/null 2>&1
        else
            nmcli radio wifi on >/dev/null 2>&1
        fi
        exit 0
        ;;

    connect)
        SSID="$2"; PW="$3"
        [ -z "$SSID" ] && exit 1
        # --wait: без него неудачная попытка висит полторы минуты, и всё это
        # время меню стоит в «подключаюсь».
        if [ -n "$PW" ]; then
            nmcli --wait 25 device wifi connect "$SSID" password "$PW" \
                  ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        else
            nmcli --wait 25 device wifi connect "$SSID" \
                  ${NMIF:+ifname "$NMIF"} >/dev/null 2>&1
        fi
        exit $?
        ;;

    disconnect)
        [ -n "$NMIF" ] && nmcli device disconnect "$NMIF" >/dev/null 2>&1
        exit 0
        ;;

    forget)
        [ -z "$2" ] && exit 1
        # Профилей с одним SSID может быть несколько — сносим все. Иначе
        # «забытая» сеть вернётся из второго профиля при первом же случае.
        nm_saved | while IFS= read -r u; do
            s=$(nmcli -g 802-11-wireless.ssid connection show uuid "$u" 2>/dev/null | nm_unesc)
            [ "$s" = "$2" ] && nmcli connection delete uuid "$u" >/dev/null 2>&1
        done
        exit 0
        ;;
    esac
fi

case "$1" in
status)
    echo "$(radio_state)|$(current_ssid)|$(current_quality)"
    ;;

scan)
    iwctl station "$IFACE" scan >/dev/null 2>&1
    ;;

list)
    KNOWN=$(known_networks)
    iwctl station "$IFACE" get-networks 2>/dev/null | strip | awk -v known="$KNOWN" '
    BEGIN {
        n = split(known, arr, "\n")
        for (i = 1; i <= n; i++) if (arr[i] != "") isKnown[arr[i]] = 1
    }
    {
        connected = "no"; line = $0
        if (line ~ /^[[:space:]]*>/) {
            connected = "yes"
            sub(/^[[:space:]]*>[[:space:]]*/, "", line)
        } else {
            sub(/^[[:space:]]*/, "", line)
        }
        # строка сети: имя, затем защита и звёздочки сигнала
        if (match(line, /[[:space:]][[:space:]]+(psk|open|8021x|wep)[[:space:]]+\*+[[:space:]]*$/)) {
            rest = substr(line, RSTART)
            name = substr(line, 1, RSTART - 1)
            split(rest, a, /[[:space:]]+/)
            sec = a[2]; stars = a[3]
            gsub(/[[:space:]]+$/, "", name)
            # 1..4 звезды -> 25..100 %
            quality = length(stars) * 25
            print connected "|" name "|" sec "|" quality "|" (isKnown[name] ? "yes" : "no")
        }
    }'
    ;;

toggle)
    if [ "$(radio_state)" = "on" ]; then rfkill block wifi; else rfkill unblock wifi; fi
    ;;

connect)
    SSID="$2"; PW="$3"
    [ -z "$SSID" ] && exit 1
    if [ -n "$PW" ]; then
        iwctl --passphrase "$PW" station "$IFACE" connect "$SSID" >/dev/null 2>&1
    else
        iwctl station "$IFACE" connect "$SSID" >/dev/null 2>&1
    fi
    # 0 = успех; вызывающий может перечитать status
    exit $?
    ;;

disconnect)
    iwctl station "$IFACE" disconnect >/dev/null 2>&1
    ;;

forget)
    [ -z "$2" ] && exit 1
    # Сначала отключаемся, если забываем ту сеть, в которой сидим: иначе
    # соединение остаётся жить, а сеть уже не сохранена — на следующем
    # обрыве связь просто пропадёт без объяснения.
    [ "$2" = "$(current_ssid)" ] && iwctl station "$IFACE" disconnect >/dev/null 2>&1
    iwctl known-networks "$2" forget >/dev/null 2>&1
    ;;

*)
    echo "usage: wifi.sh status|list|scan|toggle|connect SSID [PW]|disconnect|forget SSID" >&2
    exit 1
    ;;
esac
