#!/bin/sh
#
# astralis — toggle the focused window in and out of a special workspace.
# From a normal workspace the window drops into special:<name> silently; a
# window already in that special comes back to the focused monitor's active
# workspace and follows along, so one key both sends and retrieves. Bound per
# special (e.g. Super+Shift+M → minimized, whose windows the pill's hover
# tray shows as restore chips). Vanilla dispatchers, so it works with or
# without the hyprland-lua plugin.

name="$1"
[ -n "$name" ] || exit 0

aw=$(hyprctl activewindow -j 2>/dev/null)
addr=$(printf '%s' "$aw" | jq -r '.address // ""')
ws=$(printf '%s' "$aw" | jq -r '.workspace.name // ""')
[ -n "$addr" ] || exit 0

if [ "$ws" = "special:$name" ]; then
	real=$(hyprctl monitors -j | jq -r 'map(select(.focused)) | .[0].activeWorkspace.id // 1')
	hyprctl dispatch movetoworkspace "$real,address:$addr" >/dev/null
else
	hyprctl dispatch movetoworkspacesilent "special:$name,address:$addr" >/dev/null
fi
