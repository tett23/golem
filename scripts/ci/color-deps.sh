#!/bin/sh
# root ADR 0474 I6: the library of golem-color depends only on base.
set -eu

[ "$#" -eq 1 ] || { echo 'color-deps: usage: color-deps.sh PLAN_JSON' >&2; exit 2; }
PLAN=$1
[ -f "$PLAN" ] || { echo "color-deps: no such file: $PLAN" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo 'color-deps: jq is needed' >&2; exit 2; }
jq -e '
  ."install-plan" as $plan
  | ($plan | map({key: .id, value: ."pkg-name"}) | from_entries) as $names
  | [ $plan[]
      | select(.style == "local" and ."pkg-name" == "golem-color")
      | if has("component-name") then
          select(."component-name" == "lib") | (.depends // [])
        else
          (.components.lib // empty) | (.depends // [])
        end ] as $libs
  | ($libs | length) == 1 and ($libs[0] | map($names[.]) | sort) == ["base"]
' "$PLAN" >/dev/null || { echo 'color-deps: golem-color library must depend only on base' >&2; exit 1; }
