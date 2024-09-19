#!/usr/bin/sh

printf '\n\n'

case $1 in
c) # current weather
  curl "wttr.in/?0QF"
  ;;

t) # current weather + today's forecast
  curl "wttr.in/?1QF"
  ;;

tn) # same as above but shows only day and night
  curl "wttr.in/?1nQF"
  ;;

tt) # + tomorrow's forecast
  curl "wttr.in/?2QF"
  ;;

ttn) # same as above but shows only day and night
  curl "wttr.in/?2nQF"
  ;;

m) # moon phase
  curl "wttr.in/moon?F"
  ;;

*) # show error
  printf "wttr.sh [OPTIONS]\nOPTIONS:\n\tc -> current weather\n\tt -> c + today's forecast\n\ttn -> same as t but shows only day and night\n\ttt -> c + tomorrow's forecast\n\tttn -> same as tt but shows only day and night\n\tm -> moon phase\n"
  exit 0
  ;;
esac

printf '\n\n'
