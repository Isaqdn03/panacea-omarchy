#!/bin/bash
# Обои для страницы выбора -- Omarchy's backgrounds for the current theme.
#
#   list            -> строки  имя|миниатюра|активны(yes|no)|своя(yes|no)|полный_путь
#   warm            -> build missing thumbnails
#   set PATH        -> apply (omarchy-theme-bg-set)
#   add <путь>      -> copy into your backgrounds for this theme and apply
#   del NAME        -> delete one of your own backgrounds
#
# Same folders `omarchy theme bg next` cycles through: your own backgrounds in
# ~/.config/omarchy/backgrounds/<theme>/ ("own", deletable) and the theme's in
# ~/.local/state/omarchy/current/theme/backgrounds/. The current background is
# Omarchy's ~/.local/state/omarchy/current/background link.

THEME_NAME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
OWN_DIR="$HOME/.config/omarchy/backgrounds/$THEME_NAME"
THEME_DIR="$HOME/.local/state/omarchy/current/theme/backgrounds"
CURRENT_LINK="$HOME/.local/state/omarchy/current/background"
THUMBS="$(dirname "$(readlink -f "$0")")/thumbs.sh"
THUMB_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/panacea/thumbs"

backgrounds() {
    find -L "$OWN_DIR" "$THEME_DIR" -maxdepth 1 -type f \
         \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \
            -o -iname '*.gif' -o -iname '*.bmp' \) 2>/dev/null | sort
}

case "$1" in
list)
    cur=$(readlink -f "$CURRENT_LINK" 2>/dev/null)
    # Всё в одном цикле на встроенных командах: подпроцессы на каждую
    # картинку превращали список в секунды ожидания.
    backgrounds | while read -r w; do
        base=${w##*/}
        name=${base%.*}
        [ "$w" = "$cur" ] && act=yes || act=no
        case "$w" in "$OWN_DIR"/*) own=yes ;; *) own=no ;; esac
        # Готовая миниатюра, если она есть и не устарела; иначе исходник,
        # Qt ужмёт его по sourceSize.
        thumb="$THUMB_DIR/$name.jpg"
        [ -f "$thumb" ] && [ ! "$w" -nt "$thumb" ] || thumb="$w"
        printf '%s|%s|%s|%s|%s\n' "$name" "$thumb" "$act" "$own" "$w"
    done
    ;;

warm)
    # Догоняем миниатюры для новых обоев.
    exec "$THUMBS" all
    ;;

set)
    [ -f "$2" ] || exit 1
    exec omarchy-theme-bg-set "$2"
    ;;

add)
    src="$2"
    [ -f "$src" ] || { echo "error" >&2; exit 1; }
    [ -n "$THEME_NAME" ] || { echo "error: no current theme" >&2; exit 1; }
    mkdir -p "$OWN_DIR"

    # Если такой же файл уже есть в своих обоях — используем его без дубликатов
    for existing in "$OWN_DIR"/*; do
        if [ -f "$existing" ] && cmp -s "$src" "$existing"; then
            omarchy-theme-bg-set "$existing" >/dev/null 2>&1
            basename "$existing" | sed 's/\.[^.]*$//'
            exit 0
        fi
    done

    base=$(basename "$src")
    slug=$(printf '%s' "${base%.*}" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' \
           | tr -cd '[:alnum:]_-')
    [ -z "$slug" ] && slug="background-$(date +%s)"
    ext="${base##*.}"
    dest="$OWN_DIR/$slug.$ext"
    # имя занято — не затираем чужую картинку молча
    [ -e "$dest" ] && dest="$OWN_DIR/${slug}-$(date +%s).$ext"
    cp -f "$src" "$dest" || exit 1
    omarchy-theme-bg-set "$dest" >/dev/null 2>&1
    basename "$dest" | sed 's/\.[^.]*$//'
    ;;

del)
    [ -n "$2" ] && [ -n "$THEME_NAME" ] || exit 1
    case "$2" in */*|.*) exit 1 ;; esac
    rm -f -- "$OWN_DIR/$2".* 2>/dev/null
    ;;

*)
    echo "usage: themes.sh list | warm | set <path> | add <file> | del <name>" >&2
    exit 1
    ;;
esac
