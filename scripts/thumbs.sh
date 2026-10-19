#!/bin/bash
# Миниатюры обоев для страницы выбора темы.
#
# Обои весят до 9 МБ, и Qt при каждом открытии страницы декодировал их
# целиком, чтобы получить картинку шириной 320 px — отсюда задержка.
# Здесь они один раз ужимаются в ~/.cache/panacea/thumbs и дальше читаются
# мгновенно. Перегенерация только если исходник новее миниатюры.
#
#   thumb PATH -> печатает путь к миниатюре (создав её при необходимости)
#   all        -> прогреть кеш для всех обоев

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/panacea/thumbs"
# Omarchy's backgrounds for the current theme: yours, then the theme's.
THEME_NAME=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
WALLS=("$HOME/.config/omarchy/backgrounds/$THEME_NAME" "$HOME/.local/state/omarchy/current/theme/backgrounds")
# 480 хватало списку под пилюлей, но в карусели превью растянуто почти на
# половину экрана — и выглядело мылом. 1100 закрывает карточку с запасом.
WIDTH=1100

mkdir -p "$CACHE"

make_thumb() {
    local src="$1"
    [ -f "$src" ] || return 1

    local name
    name=$(basename "$src")
    name="${name%.*}.jpg"
    local dst="$CACHE/$name"

    if [ ! -f "$dst" ] || [ "$src" -nt "$dst" ]; then
        # -noautorotate не нужен, обои без EXIF; q=5 хватает для превью
        ffmpeg -loglevel error -y -i "$src" \
               -vf "scale=$WIDTH:-1" -q:v 5 "$dst" </dev/null || return 1
    fi
    printf '%s\n' "$dst"
}

case "$1" in
    thumb)
        make_thumb "$2"
        ;;
    path)
        # Путь к готовой миниатюре — БЕЗ создания. Список обоев вызывает это
        # на каждую картинку, и один ffmpeg на файл превращал открытие
        # карусели в минуты ожидания: обоев теперь сотни, а не полтора десятка.
        src="$2"
        [ -f "$src" ] || exit 1
        name=$(basename "$src"); name="${name%.*}.jpg"
        dst="$CACHE/$name"
        [ -f "$dst" ] && [ ! "$src" -nt "$dst" ] && printf '%s\n' "$dst"
        ;;
    all)
        find -L "${WALLS[@]}" -maxdepth 1 -type f \
             \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
        | while read -r f; do
            make_thumb "$f" >/dev/null
        done
        ;;
    *)
        echo "usage: thumbs.sh thumb <path> | all" >&2
        exit 1
        ;;
esac
