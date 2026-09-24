#!/usr/bin/env bash
# astralis — thin delegate. The canonical, maintained restore-wallpaper.sh
# lives in the astralis tree; this file exists only because Hyprland's
# `exec-once = ~/.local/bin/restore-wallpaper.sh` expects it here. Edit the
# canonical copy, not this one.
exec "$HOME/.config/quickshell/astralis/scripts/restore-wallpaper.sh" "$@"
