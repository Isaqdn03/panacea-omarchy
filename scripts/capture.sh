#!/bin/bash
# Временно отключает горячие клавиши Hyprland, чтобы панель настроек
# поймала нажатие целиком, а не получила сработавшее действие.
#
#   on  -> enter the "panacea-capture" submap, defined in the managed block of
#          ~/.config/hypr/bindings.lua with no binds but SUPER+Escape.
#   off -> возвращаемся в обычный режим.
#
# Конфиг Hyprland здесь на Lua, поэтому dispatch принимает Lua-вызов.

case "$1" in
    on)
        hyprctl dispatch 'hl.dsp.submap("panacea-capture")' >/dev/null
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
