#!/usr/bin/sh

thmbDir="$HOME/.cache/wal/wallpaper"
mkdir -p $thmbDir

# hyprlock doesn't support gif image..
if [[ $1 =~ \.gif$ ]]; then
  convert "$1"[0] -resize 1280x720 "$thmbDir/wall.set.png"
else
  cp "$1" "$thmbDir/wall.set.png"
fi

convert "$thmbDir/wall.set.png"[0] -strip -scale 10% -blur 0x3 -resize 100% "$thmbDir/wall.blur" &

convert -strip -resize 1000 -gravity center -extent 1000 -quality 90 "$thmbDir/wall.set.png"[0] "$thmbDir/wall.thmb" &

convert -strip "$thmbDir/wall.set.png"[0] -thumbnail 500x500^ -gravity center -extent 500x500 "$thmbDir/wall.sqre"

convert "$thmbDir/wall.sqre" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) -alpha Off -compose CopyOpacity -composite "$thmbDir/wall.png" && mv "$thmbDir/wall.png" "$thmbDir/wall.quad" &

mv "$thmbDir/wall.set.png" "$thmbDir/wall.set"
