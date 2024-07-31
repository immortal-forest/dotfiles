#!/usr/bin/sh

#// check swww daemon

swww query &> /dev/null
if [ $? -ne 0 ] ; then
    swww-daemon --format xrgb &
    swww query && swww restore
fi


wall_path=$1
pos=$2
reload=$3


# // check if wallpaper exists

if ! [ -f "$wall_path" ]; then
  echo "\n::Invalid wallpaper path\n"
  exit 1
fi


#// set defaults

xtrans="grow"
wallFramerate=60
wallTransDuration=0.4


if [[ $pos == "p" ]]; then
  xtrans="outer"
fi

# // wallpaper cache

wallcache.sh "$wall_path" &>/dev/null


# // generate colors

wallgen.sh "$wall_path" $reload &


#// apply wallpaper
ln -sf "$wall_path" "$HOME/wallpapers/wall.set"
swww img "$wall_path" --transition-bezier .43,1.19,1,.4 --transition-type "${xtrans}" --transition-duration "${wallTransDuration}" --transition-fps "${wallFramerate}" --invert-y --transition-pos "$(hyprctl cursorpos | grep -E '^[0-9]' || echo "0,0")" &

