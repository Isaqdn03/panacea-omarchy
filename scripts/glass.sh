#!/usr/bin/env bash
# Стеклянный режим одной командой: матовое стекло <-> плоские непрозрачные окна.
#
#   glass.sh            — переключить
#   glass.sh on|off     — задать явно
#   glass.sh status     — напечатать on или off, ничего не трогая
#
# ЧТО ЗДЕСЬ СТЕКЛО. Две вещи, и работают они только вместе:
#
#   1. Размытие Hyprland (decoration:blur). Оно матирует то, что видно СКВОЗЬ
#      прозрачные пиксели: фон терминала, подложки меню, слои Quickshell.
#   2. Прозрачный фон терминала (ghostty background-opacity, kitty
#      background_opacity). Без него размывать нечего: окно рисует сплошной
#      цвет, и стекла не видно вовсе.
#
# Отсюда и то, что переключаются они разом. Убрать только размытие — терминал
# останется дырой в обои, но уже без матовости: читать в нём нельзя. Убрать
# только прозрачность — размытие останется включённым и будет стоить кадров
# там, где его больше не видно.
#
# ГДЕ ЖИВЁТ СОСТОЯНИЕ. Файл в каталоге переключателей Omarchy. Всё, что лежит
# в ~/.local/state/omarchy/toggles/hypr/*.lua, подключается ПОСЛЕ пользовательских
# файлов (в hyprland.lua `require "default.hypr.toggles"` стоит следом за
# `require "hypr.looknfeel"`), поэтому написанное здесь перекрывает looknfeel.lua,
# а не спорит с ним.
#
# Отсутствие файла — стекло ВКЛЮЧЕНО. Так выглядит машина, на которой этим
# переключателем ни разу не пользовались: ничего не написано, а вид ровно тот,
# что задан в looknfeel.lua. Имя файла поэтому и с «-off»: он означает не
# «режим существует», а «режим выключен».
set -u

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/toggles/hypr"
FLAG="$STATE_DIR/panacea-glass-off.lua"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
GHOSTTY_CONF="$CONF_DIR/ghostty/panacea-glass.conf"
KITTY_CONF="$CONF_DIR/kitty/panacea-glass.conf"

# Прозрачность фона терминала в каждом из режимов. 0 — фон не рисуется совсем,
# и видно только размытые обои под текстом; ровно это и настраивали руками до
# появления переключателя. Хочется стекла помягче — поставьте 0.85: терминал
# получит собственный тёмный фон, а размытие ляжет под него.
GLASS_TERM_ALPHA=0
FLAT_TERM_ALPHA=1

# Каждый терминал читает свою прозрачность из отдельного файла рядом со своим
# конфигом: в ~/.config/ghostty/config последней строкой стоит
# `config-file = ?"~/.config/ghostty/panacea-glass.conf"`, в
# ~/.config/kitty/kitty.conf — `globinclude panacea-glass.conf`, и у обоих
# побеждает значение, прочитанное последним. Свой файл, а не правка основного
# конфига: у одного файла не бывает двух хозяев без спора, и переписывать
# пользовательский конфиг на каждое нажатие тумблера незачем.
#
# Пишем оба разом, даже когда в системе стоит один терминал: лишний файл никому
# не мешает, зато смена `omarchy default terminal` не оставляет стекло
# рассогласованным — новый терминал открывается уже в том режиме, что показывает
# тумблер.
#
# Синтаксис разный: у ghostty дефисы и знак равенства, у kitty подчёркивания и
# пробел. Про kitty важно ещё одно: смену background_opacity на перечитывании
# конфига он применяет только при `dynamic_background_opacity yes` — тот стоит в
# kitty.conf рядом с globinclude, без него тумблер молчал бы до перезапуска
# терминала.
write_glass_conf() {
    mkdir -p "$(dirname "$1")" 2>/dev/null || return 0
    printf '# Пишет ~/.config/panacea/scripts/glass.sh — правки затрутся.\n%s\n' \
           "$2" >"$1"
}

write_term() {
    write_glass_conf "$GHOSTTY_CONF" "background-opacity = $1"
    write_glass_conf "$KITTY_CONF" "background_opacity $1"
}

glass_off() {
    mkdir -p "$STATE_DIR" || return 1
    cat >"$FLAG" <<'LUA'
-- Стекло выключено. Файл пишет ~/.config/panacea/scripts/glass.sh — удалите
-- его (или нажмите тумблер ещё раз), и вернётся то, что задано в looknfeel.lua.
--
-- Гасим размытие целиком, а не по слоям: у слоёв правило blur только
-- добавляют, снять его отдельным правилом нельзя, а общий выключатель
-- достаёт до всех разом — до окон, слоёв и всплывающих подсказок.
hl.config({
  decoration = {
    blur = { enabled = false },
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,
  },
})
LUA
    write_term "$FLAT_TERM_ALPHA"
    apply
}

glass_on() {
    rm -f "$FLAG"
    write_term "$GLASS_TERM_ALPHA"
    apply
}

# Оба конфига читаются не нами: Hyprland перечитывает свой по команде, kitty —
# по SIGUSR1, ghostty — по SIGUSR2. Рассылает сигналы omarchy-restart-terminal,
# который знает про все поддерживаемые терминалы; руками сигналим только если
# его нет. Без этого нажатие тумблера не меняло бы ничего до следующего входа в
# систему.
apply() {
    command -v hyprctl >/dev/null 2>&1 && hyprctl reload >/dev/null 2>&1
    if command -v omarchy-restart-terminal >/dev/null 2>&1; then
        omarchy-restart-terminal >/dev/null 2>&1
    else
        pgrep -x kitty >/dev/null 2>&1 && killall -SIGUSR1 kitty >/dev/null 2>&1
        pgrep -x ghostty >/dev/null 2>&1 && killall -SIGUSR2 ghostty >/dev/null 2>&1
    fi
    return 0
}

case "${1:-toggle}" in
    status)     [ -f "$FLAG" ] && echo off || echo on ;;
    on)         glass_on ;;
    off)        glass_off ;;
    toggle|"")  if [ -f "$FLAG" ]; then glass_on; else glass_off; fi ;;
    *)          echo "usage: glass.sh [on|off|toggle|status]" >&2; exit 2 ;;
esac
