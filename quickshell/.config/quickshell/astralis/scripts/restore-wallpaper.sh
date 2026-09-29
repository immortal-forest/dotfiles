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

exec env RETHEME_ONLY=1 "$HOME/.config/quickshell/astralis/scripts/setwall" "$img"
