#!/bin/sh
# Checks the direction of the dependencies of the four packages split from
# golem-doc (docs/adr/0173): the library of golem-doc, the semantic IR and
# the plugin ABI, depends on none of golem-assemble, golem-bibliography and
# golem-numerals, and the libraries of golem-bibliography and
# golem-numerals do not depend on golem-doc.
#
#   doc-deps.sh PLAN_JSON
#
# PLAN_JSON is the plan that cabal resolved (dist-newstyle/cache/plan.json).
# The library of a package is the element of style local with its pkg-name
# and the component-name lib, or the lib of the components table of a
# per-package element. From it, the closure follows depends, and the
# depends of the lib components of a per-package element, as
# scripts/ci/test-only-deps.sh does; the test suites are not followed.
#
# Exit code 0: no library reaches a package it must not.
# Exit code 1: some do; each is one line on stderr,
#   `doc-deps: <package> depends on <package>`.
# Exit code 2: the plan cannot be read, or one of the four libraries is
# not in it.
set -eu

cannot() {
  printf 'doc-deps: %s\n' "$*" >&2
  exit 2
}

[ $# -eq 1 ] || cannot "usage: doc-deps.sh PLAN_JSON"
PLAN=$1
command -v jq >/dev/null 2>&1 || cannot "jq is needed"
[ -f "$PLAN" ] || cannot "no such file: $PLAN"
jq empty "$PLAN" >/dev/null 2>&1 || cannot "not JSON: $PLAN"
jq -e '(type == "object") and (."install-plan" | type == "array")' "$PLAN" >/dev/null 2>&1 ||
  cannot "no install-plan in $PLAN"

# the package, then the packages its library must not reach
RULES='golem-doc golem-assemble golem-bibliography golem-numerals
golem-bibliography golem-doc
golem-numerals golem-doc'

# reached PACKAGE: the pkg-names of the local packages that the library of
# PACKAGE reaches, one per line; exit code 3 when it has no library
reached() {
  jq -r --arg pkg "$1" '
    ."install-plan" as $plan
    | (reduce $plan[] as $e ({}; .[$e.id] = $e)) as $by
    | def deps: (.depends // []) + [(.components // {}) | to_entries[] | select(.key | startswith("lib")) | .value.depends[]?];
      def fix(f): (f) as $n | if $n == . then . else ($n | fix(f)) end;
      def closure: fix(. + [.[] | $by[.] // empty | deps[]] | unique);
    [ $plan[]
      | select(.style == "local" and ."pkg-name" == $pkg)
      | if has("component-name") then
          select(."component-name" == "lib") | (.depends // [])
        else
          (.components.lib // empty) | (.depends // [])
        end ] as $starts
    | if ($starts | length) == 0 then halt_error(3) else . end
    | [ $starts[][] ] | unique | closure
    | [ .[] | $by[.] // empty | select(.style == "local") | ."pkg-name" ]
    | unique[]' "$PLAN" 2>/dev/null
}

FOUND=0
printf '%s\n' "$RULES" | {
  while read -r pkg forbidden; do
    code=0
    got=$(reached "$pkg") || code=$?
    [ "$code" = 0 ] || cannot "no library of $pkg in $PLAN"
    for f in $forbidden; do
      if printf '%s\n' "$got" | grep -qxF "$f"; then
        printf 'doc-deps: %s depends on %s\n' "$pkg" "$f" >&2
        FOUND=1
      fi
    done
  done
  exit "$FOUND"
}
