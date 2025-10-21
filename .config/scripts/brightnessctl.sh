#! /usr/bin/sh

function print_error
{
  cat <<"EOF"
    ./brightnesscontrol.sh <action>
    ...valid actions are...
        i -- <i>ncrease brightness [+5%]
        d -- <d>ecrease brightness [-5%]
EOF
}

get_brightness() {
  brightnessctl -m | grep -o '[0-9]\+%' | head -c-2
}

case "$1" in
i)
  if [[ $(get_brightness) -lt 10 ]]; then
    brightnessctl s +1%
  else
    brightnessctl s +5%
  fi
  ;;
d)
  if [[ $(get_brightness) -le 1 ]]; then
    brightnessctl s 1%
  elif [[ $(get_brightness) -le 10 ]]; then
    brightnessctl s 1%-
  else
    brightnessctl s 5%-
  fi
  ;;
*)
  print_error
  ;;
esac
