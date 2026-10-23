#!/bin/sh
# Whether the nightly run of .github/workflows/race.yml runs the race tests
# (docs/adr/0075-race-search-repetitions.md):
#
#   race-needed.sh SHA
#
# prints false when SHA, the commit the run started on, is the head of the
# last successful run of race.yml on main, and true when it is not, or when
# there is no successful run yet. The commits are compared, not a window
# of time: a scheduled run may start late, and a window would miss a commit
# at its edge or count it twice.
#
# GH chooses the gh to run (for the tests). A gh that fails, or an answer
# that is not a commit, fails the script: it does not guess.
set -eu
[ $# -eq 1 ] || { echo "usage: race-needed.sh SHA" >&2; exit 2; }
SHA=$1
case "$SHA" in
  *[!0-9a-f]* | "") echo "race-needed: not a commit: $SHA" >&2; exit 2 ;;
esac
[ ${#SHA} -eq 40 ] || { echo "race-needed: not a commit: $SHA" >&2; exit 2; }
GH=${GH:-gh}
LAST=$($GH run list --workflow race.yml --branch main --status success --limit 1 --json headSha --jq '.[0].headSha')
case "$LAST" in
  "" | null) echo true; exit 0 ;;
  *[!0-9a-f]*) echo "race-needed: gh answered with what is not a commit: $LAST" >&2; exit 1 ;;
esac
[ ${#LAST} -eq 40 ] || { echo "race-needed: gh answered with what is not a commit: $LAST" >&2; exit 1; }
if [ "$LAST" = "$SHA" ]; then echo false; else echo true; fi
