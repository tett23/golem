#!/bin/sh
# Checks that the uses of unsafePerformIO and its kin in the sources are
# the ones listed in scripts/ci/unsafe-io-allowed.txt, each with the reason
# it is kept (docs/adr/0034-fewer-unsafe-perform-io.md).
#
#   unsafe-io.sh [ROOT]
#
# A use is FILE:NAME, NAME being the top-level definition it is in, for the
# Haskell files under ROOT/modules/*/src and ROOT/modules/*/app (tests are
# not checked). A use in an instance, a class or another declaration is
# FILE:DECLARATION, the line that starts it up to its where (FILE:instance
# Show T, say). Imports, comments, strings and characters are not uses; a
# name quoted for Template Haskell ('unsafePerformIO) is
# (docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md). The source is
# read by an approximation of the lexer of Haskell, not by a parser. A use
# that is not listed, or a listed use that is gone, is written to stderr,
# and the exit code is 1. A line of the list is FILE:NAME, then # and the
# reason; blank lines and lines that start with # are skipped.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
ROOT=$(cd "$ROOT" && pwd)
LIST=$ROOT/scripts/ci/unsafe-io-allowed.txt
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

(cd "$ROOT" && find modules -path 'modules/*/src/*' -name '*.hs' -o -path 'modules/*/app/*' -name '*.hs') | LC_ALL=C sort | while read -r f; do
  LC_ALL=C awk -v file="$f" -v q="'" '
    BEGIN {
      ident = "[A-Za-z0-9_" q "]"
      pat = "(^|[^A-Za-z0-9_" q "])(unsafePerformIO|unsafeDupablePerformIO|unsafeInterleaveIO|unsafeInterleaveST|unsafeIOToST|inlinePerformIO|accursedUnutterablePerformIO)([^A-Za-z0-9_" q "]|$)"
      special = "[-{\"" q "]"
      symbols = "!#$%&*+./<=>?@\\^|~:-"
      depth = 0; instr = 0
    }
    # the code of a line: block comments (which may span lines and nest),
    # line comments, strings (which may go on to the next line after a
    # backslash) and characters are taken out; a quote of Template Haskell
    # before a name becomes a space; pragmas are dropped
    function lex(s,   out, a, b, k, n, c, m, len, nc, pc) {
      out = ""
      while (s != "") {
        if (depth > 0) {
          a = index(s, "{-"); b = index(s, "-}")
          if (a == 0 && b == 0) break
          if (a > 0 && (b == 0 || a < b)) { depth++; s = substr(s, a + 2) }
          else { depth--; s = substr(s, b + 2) }
          continue
        }
        if (instr) {
          n = length(s); k = 1
          while (k <= n) {
            c = substr(s, k, 1)
            if (c == "\\") k += 2
            else if (c == "\"") break
            else k++
          }
          if (k > n) {
            # a backslash at the end is a gap: the string goes on
            instr = (k == n + 2)
            if (!instr) out = out "\""
            break
          }
          instr = 0; out = out "\""; s = substr(s, k + 1)
          continue
        }
        m = match(s, special)
        if (m == 0) { out = out s; break }
        out = out substr(s, 1, m - 1); s = substr(s, m)
        c = substr(s, 1, 1)
        pc = substr(out, length(out), 1)
        if (c == "{") {
          if (substr(s, 1, 3) == "{-#") {
            k = index(s, "#-}")
            if (k == 0) { out = out s; break }
            s = substr(s, k + 3)
          } else if (substr(s, 1, 2) == "{-") { depth++; s = substr(s, 3) }
          else { out = out "{"; s = substr(s, 2) }
        } else if (c == "-") {
          match(s, /^-+/); len = RLENGTH
          nc = substr(s, len + 1, 1)
          # two or more dashes not in an operator start a comment
          if (len >= 2 && (pc == "" || index(symbols, pc) == 0) && (nc == "" || index(symbols, nc) == 0)) break
          out = out substr(s, 1, len); s = substr(s, len + 1)
        } else if (c == "\"") {
          instr = 1; out = out "\""; s = substr(s, 2)
        } else if (pc ~ ident) {
          # a prime of a name
          out = out q; s = substr(s, 2)
        } else if (substr(s, 2, 1) == "\\" && (k = index(substr(s, 4), q)) > 0) {
          # a character with an escape
          out = out " "; s = substr(s, k + 4)
        } else if (substr(s, 2, 1) != "" && substr(s, 3, 1) == q) {
          # a character
          out = out " "; s = substr(s, 4)
        } else {
          # a quote of Template Haskell: the name after it is a use
          out = out " "; s = substr(s, 2)
        }
      }
      return out
    }
    {
      code = lex($0)
      if (code ~ /^import[ \t]/) next
      if (code ~ /^(instance|class|data|newtype|type|pattern)([ \t]|$)/) {
        head = code
        if (match(head, /[ \t]where([ \t]|$)/)) head = substr(head, 1, RSTART - 1)
        gsub(/[ \t]+/, " ", head); sub(/ $/, "", head)
        current = head
      } else if (code ~ /^[a-z_]/ && code !~ /^(module|where|deriving|foreign|infix|infixl|infixr|default)([ \t]|$)/) {
        match(code, "^[a-z_]" ident "*")
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
