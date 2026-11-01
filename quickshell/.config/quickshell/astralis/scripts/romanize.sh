#!/bin/sh
# astralis — romanize lyric lines for the lyrics widget.
# Usage: romanize.sh "<lines joined by \n>"  → one romanized line per input line.
# Japanese (any kana present) needs kakasi (pacman -S kakasi): kanji get their
# Japanese readings. Korean / Chinese / anything else go through ICU's uconv.
# Exit 3 = Japanese but kakasi missing.
in=$1
if printf '%s' "$in" | grep -qP '[\x{3040}-\x{30ff}]'; then
    command -v kakasi >/dev/null 2>&1 || exit 3
    printf '%s\n' "$in" | kakasi -i utf8 -o utf8 -Ja -Ha -Ka -Ea -s
else
    printf '%s\n' "$in" | uconv -x 'Any-Latin; NFC'
fi
