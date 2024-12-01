#!/usr/bin/env sh

if [ -z "$XDG_PICTURES_DIR" ]; then
  XDG_PICTURES_DIR="$HOME/Pictures"
fi

save_dir="${2:-$XDG_PICTURES_DIR/Screenshots}"
save_file=$(date +'%Y-%m-%d_%H-%M-%S.png')

mkdir -p $save_dir

function print_error
{
  cat <<"EOF"
    ./screenshot.sh <action>
    ...valid actions are...
        p  : print all screens
        s  : snip current screen
        sf : snip current screen (frozen)
        m  : print focused monitor
EOF
}

case $1 in
p) # print all outputs
  grimblast copysave screen "${save_dir}/${save_file}" ;;
s) # drag to manually snip an area / click on a window to print it
  grimblast copysave area "${save_dir}/${save_file}" ;;
sf) # frozen screen, drag to manually snip an area / click on a window to print it
  grimblast --freeze copysave area "${save_dir}/${save_file}" ;;
m) # print focused monitor
  grimblast copysave output "${save_dir}/${save_file}" ;;
*) # invalid option
  print_error ;;
esac

if [ -f "${save_dir}/${save_file}" ]; then
  notify-send -u low -i "${save_dir}/${save_file}" "Screenshot" "$save_file"
fi
