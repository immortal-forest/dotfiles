#!/usr/bin/sh

wall_path=$1

fxb=$(magick "$wall_path" -colorspace gray -resize 1280x720 -format "%[fx:mean]" info:)
if awk -v fxb="${fxb}" 'BEGIN {exit !(fxb < 0.71)}'; then
  # dark
  theme="dark"
else
  # light
  theme="light"
fi

wallupdate.sh $2 $theme  &>/dev/null

