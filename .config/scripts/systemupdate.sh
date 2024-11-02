#!/usr/bin/env bash

# Check release
if [ ! -f /etc/arch-release ]; then
  exit 0
fi

# Check for AUR updates
aur=$(yay -Qua | wc -l)
ofc=$(checkupdates | wc -l)

# trap 'pkill -RTMIN+20 waybar' EXIT

command="
fastfetch
printf '[Official] %-10s\n[AUR]      %-10s\n' '$ofc' '$aur'
yay -Syu
read -n 1 -p 'Press any key to continue...'
"
kitty --title systemupdate sh -c "${command}"
exit 0
