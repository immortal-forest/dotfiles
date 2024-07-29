#!/usr/bin/env sh

term=$(cat $HOME/.config/hypr/conf.d/keybindings.conf | grep ^'$term' | cut -d '=' -f2)

$term "htop" &
