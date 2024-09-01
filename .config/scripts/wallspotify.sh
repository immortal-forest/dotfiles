#!/usr/bin/sh

# check if spotify is running
if pgrep -x spotify >/dev/null; then
  # if spotify is running and spicetify is not, start spicetify in watch mode
  if ! pgrep -x spicetify >/dev/null; then
    spicetify -n -q watch -s &
  fi
fi

if [[ "$1" == "k" ]]; then
  pkill -x spicetify
  pkill -x spotify
  exit 0
fi
