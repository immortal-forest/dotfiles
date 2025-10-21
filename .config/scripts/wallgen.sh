#!/usr/bin/sh

wall_path=$1

theme=$(sed -n 's/.*"theme.matugen_settings.mode": "\(.*\)".*/\1/p' ~/.config/hyprpanel/config.json)
if [[ "$theme" == "dark" ]]; then
  # dark
  wal -i "$wall_path" -n -e &>/dev/null
else
  # light
  wal -i "$wall_path" -l -n -e &>/dev/null
fi

wallupdate.sh $2 $theme  &>/dev/null

