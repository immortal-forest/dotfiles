#!/usr/bin/env bash
# astralis — re-apply the cached wallpaper on login (Hyprland exec-once).
# No-op if nothing was ever set. Waits briefly for awww-daemon's socket,
# since exec-once races the daemon startup.
cache="$HOME/.cache/astralis/current-wallpaper"
[ -s "$cache" ] || exit 0
img="$(head -n1 "$cache")"
[ -n "$img" ] && [ -f "$img" ] || exit 0

for _ in $(seq 1 50); do
    awww query >/dev/null 2>&1 && break
    sleep 0.1
done

awww img "$img" --transition-type simple --transition-fps 60 --transition-duration 1

# Re-run the FULL setwall theming pipeline (scheme + chroma rescue + base16
# overlay + Colors.json remap) so the restored palette matches an interactive
# setwall, not a bare material scheme. RETHEME_ONLY=1 makes setwall recolour
# without re-sweeping the wallpaper (we already set it above).
exec env RETHEME_ONLY=1 "$HOME/.config/quickshell/astralis/scripts/setwall" "$img"
