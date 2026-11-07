#!/bin/sh
# build.sh: rebuilds every target whose prerequisites are newer than it
set -eu
while read -r target deps; do
  for dep in $deps; do
    if [ ! -e "$target" ] || [ "$dep" -nt "$target" ]; then
      echo "rebuild $target because $dep is newer than the target or the target does not exist yet"
      sh "rules/$target.sh"
      break
    fi
  done
done <deps.txt
