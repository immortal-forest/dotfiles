#! /usr/bin/sh

languages=$(echo "bash awk kotlin lua python python3 java c js" | tr ' ' '\n' | sort)
other=$(echo "git flask django" | tr ' ' '\n' | sort)
core="$(compgen -c | grep -v '^_' | tr ' ' '\n')"

opt=$(echo "language core other" | tr ' ' '\n' | sort)
opt_selected=$(printf "$opt" | fzf)

if [[ $opt_selected == "language" ]]; then
  selected=$(printf "$languages" | fzf)
elif [[ $opt_selected == "core" ]]; then
  selected=$(printf "$core" | fzf)
elif [[ $opt_selected == "other" ]]; then
  selected=$(printf "$other" | fzf)
else
  exit 1
fi

if [[ $selected == "" ]]; then
  exit 1
fi

read -p "Enter Query: " query
query=$(echo $query | tr ' ' '+')
clear

if [[ $opt_selected == "language" ]]; then
  echo "curl cht.sh/$selected/$query" && curl -s cht.sh/$selected/$query | less -R
elif [[ $opt_selected == "other" ]]; then
  curl -s cht.sh/$selected-$query | less -R
else
  curl -s cht.sh/$selected~$query | less -R
fi
