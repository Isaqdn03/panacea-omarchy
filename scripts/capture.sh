#!/bin/bash
# Временно отключает горячие клавиши Hyprland, чтобы панель настроек
# поймала нажатие целиком, а не получила сработавшее действие.
#
#   on  -> уходим в submap "capture": он объявлен в keybindings.lua пустым,
#          поэтому все клавиши достаются приложению.
#   off -> возвращаемся в обычный режим.
#
# Конфиг Hyprland здесь на Lua, поэтому dispatch принимает Lua-вызов.

case "$1" in
    on)
        hyprctl dispatch 'hl.dsp.submap("capture")' >/dev/null
        ;;
    off)
        hyprctl dispatch 'hl.dsp.submap("reset")' >/dev/null
        omarchy-shell -q pill cancelCapture
        ;;
    *)
        echo "usage: capture.sh on|off" >&2
        exit 1
        ;;
esac
