#!/usr/bin/env sh

print_error() {
  cat <<"EOF"
    ./volumecontrol.sh -[device] <actions>
    ...valid device are...
        i   -- input device
        o   -- output device
    ...valid actions are...
        i   -- increase volume [+5]
        d   -- decrease volume [-5]
        m   -- mute [x]
EOF
  exit 1
}

# eval device
while getopts io DeviceOpt; do
  case "$DeviceOpt" in
  i)
    srce="--default-source"
    ;;
  o)
    srce=""
    ;;
  *)
    print_error
    ;;
  esac
done

shift $((OPTIND - 1))
step="${2:-5}"

# eval action
case "$1" in
i)
  pamixer "${srce}" -i "${step}"
  ;;
d)
  pamixer "${srce}" -d "${step}"
  ;;
m)
  pamixer "${srce}" -t
  ;;
*)
  print_error
  ;;
esac
