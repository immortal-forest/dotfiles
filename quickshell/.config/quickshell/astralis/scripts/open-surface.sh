#!/bin/sh
# astralis — keybind → pill surface bridge. One IPC call; the empty second
# arg is the monitor (qs IPC is arity-strict), which shell.qml resolves to
# the focused monitor. Usage: open-surface.sh <surface> (launcher, media,
# wallpaper, clipboard, power, link, calendar, mixer, notifications, settings)
qs -c astralis ipc call pill "$1" ""
