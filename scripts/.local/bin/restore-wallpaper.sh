#!/usr/bin/env bash
# restore-wallpaper.sh — astralis login restore.
#
# Ensures the awww daemon is up, then redisplays the last-set wallpaper (or, if
# none was ever set, the first image in ~/Pictures/wallpapers) instantly and
# re-runs matugen so colours are correct from the first frame. Meant for a
# Hyprland `exec-once = ~/.local/bin/restore-wallpaper.sh`.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cache="$HOME/.cache/astralis/current-wallpaper"
walldir="$HOME/wallpapers"

# 1. Make sure the daemon is running before we ask it to display anything.
if ! pgrep -x awww-daemon >/dev/null 2>&1; then
    awww-daemon >/dev/null 2>&1 &
    # Wait (up to ~3s) for the daemon's socket to accept queries.
    for _ in $(seq 1 30); do
        awww query >/dev/null 2>&1 && break
        sleep 0.1
    done
fi

# 2. Resolve which image to restore: the cached path if it still exists, else the
#    first wallpaper we can find in the wallpapers folder.
img=""
[[ -r "$cache" ]] && img="$(< "$cache")"
if [[ -z "$img" || ! -f "$img" ]]; then
    img="$(find "$walldir" -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
            2>/dev/null | sort | head -n1)"
fi

# 3. Nothing to restore (fresh box, empty wallpapers dir) — leave quietly.
if [[ -z "$img" || ! -f "$img" ]]; then
    echo "restore-wallpaper: no cached or available wallpaper to restore" >&2
    exit 0
fi

# 4. Prefer setwall (single source of truth for awww flags + matugen + cache).
#    Use TRANSITION=none so login is instant, not a crossfade from black.
if [[ -x "$here/setwall" ]]; then
    TRANSITION=none exec "$here/setwall" "$img"
fi

# Fallback if setwall isn't co-located (e.g. run straight from the repo).
awww img "$img" --transition-type none
command -v matugen >/dev/null 2>&1 && matugen image "$img"
mkdir -p "$HOME/.cache/astralis"
printf '%s\n' "$img" > "$cache"
