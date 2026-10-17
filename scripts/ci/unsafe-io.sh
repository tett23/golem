#!/bin/sh
# Checks that the uses of unsafePerformIO and its kin in the sources are
# the ones listed in scripts/ci/unsafe-io-allowed.txt, each with the reason
# it is kept (docs/adr/0034-fewer-unsafe-perform-io.md).
#
#   unsafe-io.sh [ROOT]
#
# A use is FILE:NAME, NAME being the top-level definition it is in, for the
# Haskell files under ROOT/modules/*/src and ROOT/modules/*/app (tests are
# not checked). Imports and comments are not uses. A use that is not listed,
# or a listed use that is gone, is written to stderr, and the exit code is 1.
# A line of the list is FILE:NAME, then # and the reason; blank lines and
# lines that start with # are skipped.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
ROOT=$(cd "$ROOT" && pwd)
LIST=$ROOT/scripts/ci/unsafe-io-allowed.txt
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

(cd "$ROOT" && find modules -path 'modules/*/src/*' -name '*.hs' -o -path 'modules/*/app/*' -name '*.hs') | LC_ALL=C sort | while read -r f; do
  awk -v file="$f" '
    BEGIN { pat = "(^|[^A-Za-z0-9_'"'"'])(unsafePerformIO|unsafeDupablePerformIO|unsafeInterleaveIO|unsafeInterleaveST|unsafeIOToST|inlinePerformIO|accursedUnutterablePerformIO)([^A-Za-z0-9_'"'"']|$)" }
    {
      line = $0
      # block comments, which may span lines; pragmas are not comments
      out = ""
      while (line != "") {
        if (depth > 0) {
          e = index(line, "-}")
          if (e == 0) { line = ""; break }
          depth--
          line = substr(line, e + 2)
        } else {
          s = index(line, "{-")
          if (s == 0) { out = out line; line = ""; break }
          if (substr(line, s, 3) == "{-#") {
            e = index(substr(line, s), "#-}")
            if (e == 0) { out = out line; line = ""; break }
            line = substr(line, 1, s - 1) substr(line, s + e + 2)
            continue
          }
          out = out substr(line, 1, s - 1)
          depth++
          line = substr(line, s + 2)
        }
      }
      code = out
      # line comments
      c = match(code, /--/)
      if (c > 0) code = substr(code, 1, c - 1)
      if (code ~ /^import[ \t]/) next
      if (code ~ /^[a-z_][A-Za-z0-9_'"'"']*/ && code !~ /^(import|module|where|data|type|newtype|class|instance|deriving|foreign|infix|infixl|infixr|default|pattern)([ \t]|$)/) {
        match(code, /^[a-z_][A-Za-z0-9_'"'"']*/)
        current = substr(code, RSTART, RLENGTH)
      }
      if (code ~ pat) print file ":" current
    }
  ' "$ROOT/$f"
done | LC_ALL=C sort -u >"$WORK/found"

if [ -f "$LIST" ]; then
  sed -e 's/#.*$//' -e 's/[[:space:]]*$//' -e '/^$/d' "$LIST" | LC_ALL=C sort -u >"$WORK/allowed"
else
  : >"$WORK/allowed"
fi

STATUS=0
LC_ALL=C comm -23 "$WORK/found" "$WORK/allowed" | while read -r u; do
  printf 'unsafe-io: not in scripts/ci/unsafe-io-allowed.txt: %s\n' "$u" >&2
done
LC_ALL=C comm -13 "$WORK/found" "$WORK/allowed" | while read -r u; do
  printf 'unsafe-io: listed but not used: %s\n' "$u" >&2
done
if ! cmp -s "$WORK/found" "$WORK/allowed"; then STATUS=1; fi
exit "$STATUS"
