#!/usr/bin/sh

reload=$1

colorsDir="$HOME/.cache/wal"
confDir="$HOME/.config"

# copying files

# hyprland
cp "$colorsDir/hypr-colors.conf" "$confDir/hypr/theme/colors.conf"

# kitty
cp "$colorsDir/colors-kitty.conf" "$confDir/kitty/theme.conf"

# rofi
if [[ "$2" == "light" ]]; then
  cp "$colorsDir/colors-rofi-light.rasi" "$confDir/rofi/colors.rasi"
else
  cp "$colorsDir/colors-rofi-dark.rasi" "$confDir/rofi/colors.rasi"
fi

# waybar
cp "$colorsDir/colors-waybar.css" "$confDir/waybar/theme.css"

# wlogout
cp "$colorsDir/colors-waybar.css" "$confDir/wlogout/theme.css"

# spicetify
cp "$colorsDir/colors-spotify.ini" "$confDir/spicetify/Themes/Sleek/color.ini"

# cava
cp "$colorsDir/colors-cava" "$confDir/cava/config"

# kvantum
cp "$colorsDir/pywal.kvconfig" "$confDir/Kvantum/pywal/pywal.kvconfig"
cp "$colorsDir/pywal.svg" "$confDir/Kvantum/pywal/pywal.svg"

# dunst
cp "$colorsDir/dunstrc" "$confDir/dunst/dunstrc"

if [[ "$reload" == "r" ]]; then
  pkill -x rofi

  # don't start waybar if its not running
  if pgrep -x waybar > /dev/null ; then
    pkill -x waybar
    hyprctl dispatch exec waybar &>/dev/null
  fi

  pkill -USR2 cava

  pywalfox update

  pkill -x dunst
  hyprctl dispatch exec dunst &>/dev/null

  if ! pgrep -x spicetify > /dev/null ; then
    if pgrep -x spotify > /dev/null ; then
      spicetify -n -q watch -s &
    fi
  fi

fi

