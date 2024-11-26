#!/usr/bin/sh

reload=$1

colorsDir="$HOME/.cache/wal"
confDir="$HOME/.config"

# copying files

# hyprland
mkdir -p "$confDir/hypr/theme"
cp "$colorsDir/hypr-colors.conf" "$confDir/hypr/theme/colors.conf"

# kitty
cp "$colorsDir/colors-kitty.conf" "$confDir/kitty/theme.conf"

# rofi
if [[ "$2" == "light" ]]; then
  cp "$colorsDir/colors-rofi-light.rasi" "$confDir/rofi/colors.rasi"
else
  cp "$colorsDir/colors-rofi-dark.rasi" "$confDir/rofi/colors.rasi"
fi

# spicetify
cp "$colorsDir/colors-spotify.ini" "$confDir/spicetify/Themes/Sleek/color.ini"

# cava
mkdir -p "$confDir/cava"
cp "$colorsDir/colors-cava" "$confDir/cava/config"

# kvantum
mkdir -p "$confDir/Kvantum/pywal"
cp "$colorsDir/pywal.kvconfig" "$confDir/Kvantum/pywal/pywal.kvconfig"
cp "$colorsDir/pywal.svg" "$confDir/Kvantum/pywal/pywal.svg"

if [[ "$reload" == "r" ]]; then
  pkill -x rofi

  pkill -USR2 cava

  pywalfox update

  if ! pgrep -x spicetify >/dev/null; then
    if pgrep -x spotify >/dev/null; then
      spicetify -n -q watch -s &
    fi
  fi

fi
