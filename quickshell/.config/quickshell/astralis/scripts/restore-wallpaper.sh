#!/usr/bin/env bash
# astralis — re-theme from the restored wallpaper on login (Hyprland exec-once).
#
# Wallpaper DISPLAY + restore is owned by skwd-walld (systemd --user service,
# `skwd-walld --wait-for-session`): it re-draws the last wallpaper on login via
# its own skwd-paper engine. This script is the THEMING safety net — it recolours
# astralis (matugen + chroma-rescue + base16/pywal) from the cached wallpaper so
# the shell/terminals/gtk/qt/browser match from the first frame even if skwd's
# restore doesn't re-fire the externalMatugenCommand theme hook. It no longer
# re-applies the wallpaper itself (that double-displayed over skwd's restore).
#
# RETHEME_ONLY: recolour without rewriting current-wallpaper. No-op if unset.
cache="$HOME/.cache/astralis/current-wallpaper"
[ -s "$cache" ] || exit 0
img="$(head -n1 "$cache")"
[ -n "$img" ] && [ -f "$img" ] || exit 0

# Display safety net: skwd-walld restores from its own records in
# ~/.cache/skwd-wall-v2 (last-applied.json). When that cache is wiped it
# restores nothing and the desktop stays bare (2026-11-27). Once the daemon
# answers and has had time for its own restore, apply the cached wallpaper if
# no output shows one. Detached so the retheme below doesn't wait on it.
if command -v skwd-helm >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    ( setsid bash -c '
        for _ in $(seq 30); do
            timeout 3 skwd-helm current --json >/dev/null 2>&1 && break
            sleep 1
        done
        sleep 8
        shown="$(timeout 3 skwd-helm current --json 2>/dev/null \
            | jq -r "[.outputs[] | select((.current // \"\") != \"\")] | length" 2>/dev/null)"
        [ "$shown" = "0" ] && timeout 30 skwd-helm apply "$1"
    ' _ "$img" </dev/null >/dev/null 2>&1 & )
fi

exec env RETHEME_ONLY=1 "$HOME/.config/quickshell/astralis/scripts/setwall" "$img"
