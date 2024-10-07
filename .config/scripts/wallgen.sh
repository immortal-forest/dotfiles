#!/usr/bin/sh

wall_path=$1
theme="dark"

fxb=$(magick "$wall_path" -colorspace gray -resize 1280x720 -format "%[fx:mean]" info:)
if awk -v fxb="${fxb}" 'BEGIN {exit !(fxb < 0.72)}'; then
  # dark
  wal -i "$wall_path" -n -e &>/dev/null
else
  # light
  theme="light"
  wal -i "$wall_path" -l -n -e &>/dev/null
fi

wallupdate.sh $2 $theme  &>/dev/null

