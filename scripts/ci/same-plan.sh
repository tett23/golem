#!/bin/sh
# Compares two plans of cabal (dist-newstyle/cache/plan.json) by the IDs of
# the elements of their install-plan, in any order
# (docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md, item 1).
#
#   same-plan.sh PLAN_JSON OTHER_PLAN_JSON
#
# A runner of ci.yml that builds some targets alone compares the plan it
# built with the plan of cabal build all, so that test-only-deps.sh and
# doc-deps.sh read every component. Exit code 0 for the same elements; 1
# with the lines of diff (< in the first only, > in the second only)
# otherwise; 2 for a wrong argument.
set -eu
[ $# -eq 2 ] || { echo "usage: same-plan.sh PLAN_JSON OTHER_PLAN_JSON" >&2; exit 2; }
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
jq -r '."install-plan"[].id' "$1" | LC_ALL=C sort >"$TMP/a"
jq -r '."install-plan"[].id' "$2" | LC_ALL=C sort >"$TMP/b"
[ -s "$TMP/a" ] || { echo "same-plan: no element in $1" >&2; exit 1; }
if diff "$TMP/a" "$TMP/b" >"$TMP/diff"; then exit 0; fi
grep '^[<>]' "$TMP/diff"
exit 1
