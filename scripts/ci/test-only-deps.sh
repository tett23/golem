#!/bin/sh
# Checks that no library nor executable of the repository depends on
# golem-test-support, the package that only the test suites use
# (docs/adr/0028-shared-test-support-package.md).
#
#   test-only-deps.sh PLAN_JSON
#
# PLAN_JSON is the plan that cabal resolved (dist-newstyle/cache/plan.json),
# after the conditionals and the imports of the common stanzas.
# The starting points are the libraries (lib, lib:*) and the executables
# (exe:*) of the local packages, both of the per-component elements
# (component-name) and of the per-package ones (the components table),
# except those of golem-test-support itself. From each, the closure follows
# depends, and the depends of the lib components of a per-package element,
# not exe-depends (the build tools) nor setup: the rule of
# scripts/release/licenses.sh for exe:golem.
#
# Exit code 0: no starting point reaches golem-test-support.
# Exit code 1: some do; each is one line on stderr.
# Exit code 2: the plan cannot be read (no file, not JSON, no install-plan).
set -eu

cannot() {
  printf 'test-only-deps: %s\n' "$*" >&2
  exit 2
}

[ $# -eq 1 ] || cannot "usage: test-only-deps.sh PLAN_JSON"
PLAN=$1
command -v jq >/dev/null 2>&1 || cannot "jq is needed"
[ -f "$PLAN" ] || cannot "no such file: $PLAN"
jq empty "$PLAN" >/dev/null 2>&1 || cannot "not JSON: $PLAN"
jq -e '(type == "object") and (."install-plan" | type == "array")' "$PLAN" >/dev/null 2>&1 ||
  cannot "no install-plan in $PLAN"

FOUND=$(jq -r '
  def starts: test("^(lib|lib:.*|exe:.*)$");
  ."install-plan" as $plan
  | (reduce $plan[] as $e ({}; .[$e.id] = $e)) as $by
  | def deps: (.depends // []) + [(.components // {}) | to_entries[] | select(.key | startswith("lib")) | .value.depends[]?];
    def fix(f): (f) as $n | if $n == . then . else ($n | fix(f)) end;
    def closure: fix(. + [.[] | $by[.] // empty | deps[]] | unique);
  [ $plan[]
    | select(.style == "local" and ."pkg-name" != "golem-test-support")
    | ."pkg-name" as $pkg
    | if has("component-name") then
        select(."component-name" | starts) | {name: ($pkg + ":" + ."component-name"), depends: (.depends // [])}
      else
        (.components // {}) | to_entries[] | select(.key | starts) | {name: ($pkg + ":" + .key), depends: (.value.depends // [])}
      end
    | select(.depends | unique | closure | any(.[]; ($by[.] // {})."pkg-name" == "golem-test-support"))
    | .name ]
  | unique[]' "$PLAN") || cannot "cannot read the dependencies from $PLAN"

[ -n "$FOUND" ] || exit 0
printf '%s\n' "$FOUND" | while IFS= read -r c; do
  printf 'test-only-deps: %s depends on golem-test-support, which only test suites may use\n' "$c" >&2
done
exit 1
