#!/bin/sh
# Checks that the two sources of the manual have the same headings
# (docs/adr/0022-manual-as-typesetting-sample.md): the headings (# to ###)
# of docs/manual.md, and those of the .gm files of manual/ joined in the
# order of the chapters of manual/manifest.toml. The headings of manual/
# are compared as text, without the notation of Golem (inline commands,
# escapes, comments). Lines in code blocks are not headings.
#
#   check-headings.sh [ROOT]    ROOT is the repository (by default, this one)
#
# The first heading that differs is written to stderr, and the exit code is 1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
MD=$ROOT/docs/manual.md
MANIFEST=$ROOT/manual/manifest.toml
for f in "$MD" "$MANIFEST"; do
  [ -f "$f" ] || { echo "check-headings: no $f" >&2; exit 1; }
done
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# headings KIND FILE: "LEVEL<TAB>TEXT<TAB>FILE:LINE" for each heading
headings() {
  awk -v kind="$1" -v name="$2" '
    function strip(s,    out, m, inner, cmd, body) {
      # escapes: \x is the character x; keep it from the patterns below
      gsub(/\\\\/, "\001", s); gsub(/\\\[/, "\002", s); gsub(/\\\]/, "\003", s)
      gsub(/\\\|/, "|", s); gsub(/\\%/, "%", s); gsub(/\\/, "", s)
      gsub(/%%[^%]*%%/, "", s)
      # the innermost [...] first, until none is left
      while (match(s, /\[[^][]*\]/)) {
        inner = substr(s, RSTART + 1, RLENGTH - 2)
        cmd = inner; sub(/[ :].*$/, "", cmd)
        body = ""
        if (cmd !~ /^(=|note|sidenote|index)$/ && index(inner, ":") > 0) {
          body = substr(inner, index(inner, ":") + 1)
          sub(/\|.*$/, "", body)
          sub(/^ +/, "", body); sub(/ +$/, "", body)
          if (cmd == "ruby") gsub(/\//, "", body)
        }
        s = substr(s, 1, RSTART - 1) body substr(s, RSTART + RLENGTH)
      }
      gsub(/\001/, "\\", s); gsub(/\002/, "[", s); gsub(/\003/, "]", s)
      return s
    }
    /^(```|~~~)/ { code = !code; next }
    code { next }
    /^#+ / && match($0, /^#+/) && RLENGTH <= 3 {
      level = $0; sub(/ .*$/, "", level)
      text = substr($0, length(level) + 2)
      if (kind == "md") gsub(/`/, "", text); else text = strip(text)
      sub(/^[ \t]+/, "", text); sub(/[ \t]+$/, "", text)
      printf "%s\t%s\t%s:%d\n", level, text, name, NR
    }
  ' "$2"
}

# the chapter files, in the order of manifest.toml: the strings that end in
# .gm in the array chapters (nested arrays and { file = ... } included)
CHAPTERS=$(awk '
  !on && /^[ \t]*chapters[ \t]*=/ { on = 1; sub(/^[^=]*=/, "") }
  on {
    line = $0
    while (match(line, /"[^"]*"/)) {
      s = substr(line, RSTART + 1, RLENGTH - 2)
      if (s ~ /\.gm$/) print s
      line = substr(line, RSTART + RLENGTH)
    }
    t = $0; gsub(/"[^"]*"/, "", t)
    depth += gsub(/\[/, "[", t) - gsub(/\]/, "]", t)
    if (depth <= 0) exit
  }
' "$MANIFEST")
[ -n "$CHAPTERS" ] || { echo "check-headings: no chapters in $MANIFEST" >&2; exit 1; }

(cd "$ROOT" && headings md docs/manual.md) >"$WORK/md"
: >"$WORK/gm"
printf '%s\n' "$CHAPTERS" | while IFS= read -r c; do
  [ -f "$ROOT/manual/$c" ] || { echo "check-headings: no manual/$c" >&2; exit 1; }
  (cd "$ROOT" && headings gm "manual/$c") >>"$WORK/gm"
done

# the first line where the levels or the texts differ
awk -F '\t' -v mdfile="$WORK/md" '
  BEGIN { while ((getline l < mdfile) > 0) md[++n] = l }
  {
    m++
    if (m > n) { gm_extra = $0; exit }
    split(md[m], a, "\t")
    if (a[1] != $1 || a[2] != $2) { printf "%s\n%s\n", md[m], $0; bad = 1; exit }
  }
  END {
    if (bad) exit 1
    if (gm_extra != "") { printf "(none)\n%s\n", gm_extra; exit 1 }
    if (m < n) { printf "%s\n(none)\n", md[m + 1]; exit 1 }
  }
' "$WORK/gm" >"$WORK/diff" || {
  {
    echo "check-headings: the headings of docs/manual.md and manual/ differ (docs/adr/0022)"
    sed -n 1p "$WORK/diff" | awk -F '\t' '{ if ($0 == "(none)") print "  docs/manual.md: (no more headings)"; else printf "  %s: %s %s\n", $3, $1, $2 }'
    sed -n 2p "$WORK/diff" | awk -F '\t' '{ if ($0 == "(none)") print "  manual/: (no more headings)"; else printf "  %s: %s %s\n", $3, $1, $2 }'
    echo "  Make the two the same: docs/manual.md is the source, manual/ follows it."
  } >&2
  exit 1
}
