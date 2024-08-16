#!/usr/bin/sh

wall_conf="$HOME/wallpapers/wall.conf"
config_content=$(cat "$wall_conf")

theme=$(echo "$config_content" | grep -oP 'Theme=\K.*')

image_dir="$HOME/wallpapers/$theme"
images=("$image_dir"/*)


image_list=""
for img in "${images[@]}"; do
    image_list+=$(basename "$img" | cut -d. -f1)"\x00icon\x1f${img}\n"
done

selected_image=$(printf '%b' "$image_list" | rofi -dmenu -theme ~/.config/rofi/wallselect.rasi -p "Select wallpaper")

for img in "${images[@]}"; do
    if [[ "$(basename "$img" | cut -d. -f1)" = "$selected_image" ]]; then
        selected_image_path="$(basename "$img")"
        break
    fi
done

if [ -n "$selected_image_path" ]; then
  swww.py w "$selected_image_path" &
fi

