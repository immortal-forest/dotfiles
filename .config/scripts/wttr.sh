#!/usr/bin/sh

print_weather() {
  printf '\n\n'
  curl "wttr.in/$1"
  printf '\n\n'
}

case $1 in
c) # current weather
  print_weather "?0QF"
  ;;

t) # current weather + today's forecast
  print_weather "?1QF"
  ;;

tn) # same as above but shows only day and night
  print_weather "?1nQF"
  ;;

tt) # + tomorrow's forecast
  print_weather "?2QF"
  ;;

ttn) # same as above but shows only day and night
  print_weather "?2nQF"
  ;;

m) # moon phase
  print_weather "moon?F"
  ;;

*) # show error
  printf "wttr.sh [OPTIONS]\nOPTIONS:\n\tc -> current weather\n\tt -> c + today's forecast\n\ttn -> same as t but shows only day and night\n\ttt -> c + tomorrow's forecast\n\tttn -> same as tt but shows only day and night\n\tm -> moon phase\n"
  exit 0
  ;;
esac
