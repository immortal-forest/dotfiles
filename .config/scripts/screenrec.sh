#!/usr/bin/sh

if pgrep -x wl-screenrec >/dev/null; then
  pkill -x wl-screenrec
  exit 0
fi

save_file=$(date +'%Y-%m-%d_%H:%M:%S.mkv')
output="$HOME/Videos/Recordings/recording_$save_file"

device="$2"

audio="$1"
if [[ $audio == "a" ]] then
  hyprctl dispatch exec "LIBVA_DRIVER_NAME=iHD wl-screenrec -f $output --audio --audio-device $device --audio-codec aac --codec avc --low-power=off"
else
  hyprctl dispatch exec "LIBVA_DRIVER_NAME=iHD wl-screenrec -f $output --codec avc --low-power=off"
fi
