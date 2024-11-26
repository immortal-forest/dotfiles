#!/usr/bin/env sh

# define functions

print_error() {
  cat <<"EOF"
    ./volumecontrol.sh -[device] <actions>
    ...valid device are...
        i   -- input device
        o   -- output device
        p   -- player application
    ...valid actions are...
        i   -- increase volume [+5]
        d   -- decrease volume [-5]
        m   -- mute [x]
EOF
  exit 1
}

action_pamixer() {
  pamixer "${srce}" -"${1}" "${step}"
  vol=$(pamixer "${srce}" --get-volume | cat)
}

action_playerctl() {
  [ "${1}" == "i" ] && pvl="+" || pvl="-"
  playerctl --player="${srce}" volume "0.0${step}${pvl}"
  vol=$(playerctl --player="${srce}" volume | awk '{ printf "%.0f\n", $0 * 100 }')
}

select_output() {
  if [ "$@" ]; then
    desc="$*"
    device=$(pactl list sinks | grep -C2 -F "Description: $desc" | grep Name | cut -d: -f2 | xargs)
    if pactl set-default-sink "$device"; then
      notify-send -t 2000 -r 2 -u low "Activated: $desc"
    else
      notify-send -t 2000 -r 2 -u critical "Error activating $desc"
    fi
  else
    pactl list sinks | grep -ie "Description:" | awk -F ': ' '{print $2}' | sort |
      while IFS= read -r x; do echo "$x"; done
  fi
}

# eval device option

while getopts iop:s: DeviceOpt; do
  case "${DeviceOpt}" in
  i)
    nsink=$(pamixer --list-sources | awk -F '"' 'END {print $(NF - 1)}')
    [ -z "${nsink}" ] && echo "ERROR: Input device not found..." && exit 0
    ctrl="pamixer"
    srce="--default-source"
    ;;
  o)
    nsink=$(pamixer --get-default-sink | awk -F '"' 'END{print $(NF - 1)}')
    [ -z "${nsink}" ] && echo "ERROR: Output device not found..." && exit 0
    ctrl="pamixer"
    srce=""
    ;;
  p)
    player_name="${OPTARG}"
    nsink=$(playerctl --list-all | grep -w "${player_name}")
    [ -z "${nsink}" ] && echo "ERROR: Player ${player_name} not active..." && exit 0
    ctrl="playerctl"
    srce="${player_name}"
    ;;
  s)
    default_sink="$(pamixer --get-default-sink | awk -F '"' 'END{print $(NF - 1)}')"
    export selected_sink="$(select_output "${@}" | rofi -dmenu -select "${default_sink}" -config "$HOME/.config/rofi/notification.rasi")"
    select_output "$selected_sink"
    exit
    ;;
  *) print_error ;;
  esac
done

# set default variables

shift $((OPTIND - 1))
step="${2:-5}"

# execute action

case "${1}" in
i) action_${ctrl} i ;;
d) action_${ctrl} d ;;
m) "${ctrl}" "${srce}" -t && exit 0 ;;
*) print_error ;;
esac
