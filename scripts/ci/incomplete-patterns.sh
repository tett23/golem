#!/bin/sh
# Checks that every component of every package under modules/ is built with
# -Werror=incomplete-patterns (docs/adr/0027-exhaustive-command-dispatch-by-types.md),
# so that a package added without the flag fails CI.
#
#   incomplete-patterns.sh [ROOT]
#
# A component (library, executable, test-suite, benchmark) passes when its
# ghc-options (those of the common stanzas it imports, then its own) have
# the flag, and no -Wno-error=incomplete-patterns,
# -Wno-incomplete-patterns or -Wwarn=incomplete-patterns after it. A
# component that does not is written to stderr as FILE: COMPONENT, and the
# exit code is 1; so is a directory under ROOT/modules without a .cabal
# file. The same three options take the flag back elsewhere, and fail the
# check there too: in an OPTIONS_GHC pragma of a Haskell file under
# ROOT/modules (written as FILE:LINE), and in the ghc-options of
# ROOT/cabal.project and ROOT/cabal.project.local, which cabal gives after
# those of the .cabal files (written as FILE: SECTION)
# (docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md).
# The cabal files are read as cabal reads them: the names of sections and
# fields in any case, and a field on the lines indented under its name.
# rts-capabilities.sh reads them the same way, with its own code, so that
# the two checks stay apart.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
FLAG=-Werror=incomplete-patterns
STATUS=0
# the awk program that reads a cabal file; with -v project=1, it writes the
# sections whose ghc-options take the flag back, else the components that
# are not built with the flag
READ='
  # the state after the options: "1" the flag is on, "0" it was taken
  # back, else the state before
  function state(v, before,   n, w, i, s) {
    s = before
    gsub(/"/, " ", v)
    n = split(v, w, " ")
    for (i = 1; i <= n; i++) {
      if (w[i] == flag) s = "1"
      else if (w[i] == "-Wno-error=incomplete-patterns" || w[i] == "-Wno-incomplete-patterns" || w[i] == "-Wwarn=incomplete-patterns") s = "0"
    }
    return s
  }
  # the end of a field: its value is all of its lines
  function close_field(   line) {
    if (field == "ghc-options") {
      if (project) { if (state(value, "") == "0") back[section] = 1 }
      else if (scope != "") st[scope] = state(value, st[scope])
    } else if (field == "import" && scope != "") {
      line = value; gsub(/[ \t,]+/, " ", line)
      imports[scope] = imports[scope] " " line
    }
    field = ""; value = ""
  }
  /^[ \t]*--/ || /^[ \t]*$/ { next }
  /^[^ \t]/ {
    close_field()
    scope = ""
    section = $0; sub(/[ \t]+$/, "", section)
    kind = tolower($1)
    if (project) {
      if (match($0, /^[A-Za-z][A-Za-z0-9_-]*[ \t]*:/)) {
        # a field at the top of cabal.project
        section = "(top)"; field = tolower(substr($1, 1, index($1 ":", ":") - 1)); field_indent = 0
        value = substr($0, RLENGTH + 1)
      } else order[++n] = section
    } else if (kind == "common") { scope = "common " $2 }
    else if (kind ~ /^(library|executable|test-suite|benchmark|foreign-library)$/) {
      scope = section; order[++n] = scope
    }
    next
  }
  {
    match($0, /^[ \t]*/); indent = RLENGTH
    if (field != "" && indent > field_indent) { value = value " " substr($0, indent + 1); next }
    close_field()
    if (match($0, /^[ \t]+[A-Za-z][A-Za-z0-9_-]*[ \t]*:/)) {
      name = substr($0, indent + 1, RLENGTH - indent); sub(/[ \t]*:$/, "", name)
      field = tolower(name); field_indent = indent
      value = substr($0, RLENGTH + 1)
    }
  }
  END {
    close_field()
    if (project) {
      if ("(top)" in back) print "(top)"
      for (i = 1; i <= n; i++) if (order[i] in back) print order[i]
      exit
    }
    for (i = 1; i <= n; i++) {
      c = order[i]; s = ""
      m = split(imports[c], names, " ")
      for (j = 1; j <= m; j++) if (st["common " names[j]] != "") s = st["common " names[j]]
      if (st[c] != "") s = st[c]
      if (s != "1") print c
    }
  }
'
for dir in "$ROOT"/modules/*/; do
  [ -d "$dir" ] || continue
  set -- "$dir"*.cabal
  if [ ! -f "$1" ]; then
    printf '%s: no .cabal file\n' "$dir" >&2
    STATUS=1
    continue
  fi
  for cabal in "$@"; do
    missing=$(awk -v flag="$FLAG" -v project=0 "$READ" "$cabal")
    if [ -n "$missing" ]; then
      printf '%s\n' "$missing" | sed "s|^|${cabal#"$ROOT"/}: |" >&2
      STATUS=1
    fi
  done
done
for project in cabal.project cabal.project.local; do
  [ -f "$ROOT/$project" ] || continue
  back=$(awk -v flag="$FLAG" -v project=1 "$READ" "$ROOT/$project")
  if [ -n "$back" ]; then
    printf '%s\n' "$back" | sed "s|^|$project: |" >&2
    STATUS=1
  fi
done
# OPTIONS_GHC pragmas, which may span lines; the name of a pragma is in any
# case
if [ -d "$ROOT/modules" ]; then
  pragmas=$(find "$ROOT/modules" -type f -name '*.hs' -not -path '*/dist-newstyle/*' -exec awk '
    FNR == 1 { on = 0 }
    !on && /^[ \t]*--/ { next }
    !on {
      k = index(tolower($0), "{-#")
      if (k == 0) next
      rest = substr($0, k + 3)
      if (tolower(rest) !~ /^[ \t]*options_ghc([ \t]|$)/) next
      on = 1; at = FNR; text = ""
      line = rest
    }
    on && line == "" { line = $0 }
    on {
      e = index(line, "#-}")
      text = text " " (e > 0 ? substr(line, 1, e - 1) : line)
      line = ""
      if (e > 0) {
        on = 0
        if (text ~ /(^|[ \t])-W(no-error=|no-|warn=)incomplete-patterns([ \t]|$)/) print FILENAME ":" at
      }
    }
  ' {} +)
  if [ -n "$pragmas" ]; then
    printf '%s\n' "$pragmas" | LC_ALL=C sort | sed "s|^${ROOT}/||" >&2
    STATUS=1
  fi
fi
exit "$STATUS"
