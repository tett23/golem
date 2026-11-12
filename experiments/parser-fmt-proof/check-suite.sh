#!/bin/sh
# Run the CLI checks even when the suite's unit tests fail.
set -eu
suite=$1
bound=$2
status=0
node --test experiments/parser-fmt-proof/"$suite"/*.test.mjs || status=1
case "$suite" in
  manuscripts) node experiments/parser-fmt-proof/manuscripts/check.mjs "$bound" || status=1 ;;
  tables) node experiments/parser-fmt-proof/tables/check.mjs || status=1 ;;
  arguments|eval) ;;
  *) exit 1 ;;
esac
exit "$status"
