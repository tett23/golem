#!/bin/sh
# Checks that every component of every package under modules/ is built with
# -Werror=incomplete-patterns (docs/adr/0027-exhaustive-command-dispatch-by-types.md),
# so that a package added without the flag fails CI.
#
#   incomplete-patterns.sh [ROOT]
#
# A component (library, executable, test-suite, benchmark) passes when its
# own ghc-options have the flag, or when it imports a common stanza whose
# ghc-options have it. A component that does not is written to stderr as
# FILE: COMPONENT, and the exit code is 1; so is a directory under
# ROOT/modules without a .cabal file.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
FLAG=-Werror=incomplete-patterns
STATUS=0
for dir in "$ROOT"/modules/*/; do
  [ -d "$dir" ] || continue
  set -- "$dir"*.cabal
  if [ ! -f "$1" ]; then
    printf '%s: no .cabal file\n' "$dir" >&2
    STATUS=1
    continue
  fi
  for cabal in "$@"; do
    missing=$(awk -v flag="$FLAG" '
      function close_component() {
        if (component != "") { own[component] = has_own; imports[component] = imported }
      }
      /^[^ \t-]/ {
        close_component()
        component = ""; common = ""; has_own = 0; imported = ""
        if ($1 == "common") { common = $2 }
        else if ($1 ~ /^(library|executable|test-suite|benchmark|foreign-library)$/) {
          component = $0; order[++n] = component
        }
        next
      }
      /^[ \t]+ghc-options:/ {
        found = index($0, flag) > 0
        if (common != "" && found) { common_ok[common] = 1 }
        if (component != "" && found) { has_own = 1 }
        next
      }
      /^[ \t]+import:/ {
        line = $0; sub(/^[ \t]+import:[ \t]*/, "", line); gsub(/[ \t,]+/, " ", line)
        imported = imported " " line
        next
      }
      END {
        close_component()
        for (i = 1; i <= n; i++) {
          c = order[i]; ok = own[c]
          m = split(imports[c], names, " ")
          for (j = 1; j <= m; j++) if (names[j] in common_ok) ok = 1
          if (!ok) print c
        }
      }
    ' "$cabal")
    if [ -n "$missing" ]; then
      printf '%s\n' "$missing" | sed "s|^|${cabal#"$ROOT"/}: |" >&2
      STATUS=1
    fi
  done
done
exit "$STATUS"
