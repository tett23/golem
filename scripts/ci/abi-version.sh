#!/bin/sh
# Checks the ABI version of plugins against the last release
# (docs/adr/0052-plugin-abi-version-bump-rule.md). The last release is the
# latest tag v* that HEAD reaches. The files that stand for the ABI, the
# CDDL of the IR and Golem.Doc.Validate, are compared without their
# comments and blanks between the release and the working tree:
#
#   the same          abiVersion of Golem.Doc.IR is the one of the release
#   one of them not   abiVersion is the one of the release plus one
#
# Anything else is an error: the two versions and the files that differ go
# to stderr, and the exit code is 1. A file the release does not have is an
# error too: when a file moves, change the paths here in the same change.
# Without a tag v* there is nothing to compare, and the check passes.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || exit 2

CDDL=modules/golem-doc/schema/golem-doc.cddl
VALIDATE=modules/golem-doc/src/Golem/Doc/Validate.hs
IR=modules/golem-doc/src/Golem/Doc/IR.hs

fail() {
  printf 'abi-version: %s\n' "$*" >&2
  exit 1
}

if ! TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null); then
  echo "abi-version: no release (no tag v*); the ABI version is not checked"
  exit 0
fi

# the CDDL without its comments (; to the end of the line) and blanks
strip_cddl() { sed 's/;.*$//' | tr -d ' \t\r\n'; }

# Haskell without its comments ({- -}, nested, and -- to the end of the
# line, outside strings and characters) and blanks
strip_hs() {
  awk '
    BEGIN { depth = 0; out = ""; q = sprintf("%c", 39) }
    {
      line = $0; n = length(line); i = 1; instr = 0
      while (i <= n) {
        c = substr(line, i, 1); c2 = substr(line, i, 2)
        if (depth > 0) {
          if (c2 == "{-") { depth++; i += 2 }
          else if (c2 == "-}") { depth--; i += 2 }
          else i++
          continue
        }
        if (instr) {
          out = out c
          if (c == "\\") { out = out substr(line, i + 1, 1); i += 2; continue }
          if (c == "\"") instr = 0
          i++
          continue
        }
        if (c2 == "{-") { depth = 1; i += 2; continue }
        if (c2 == "--") {
          # a line comment is two or more dashes not followed by a symbol
          j = i
          while (substr(line, j, 1) == "-") j++
          if (substr(line, j, 1) !~ /[!#$%&*+.\/<=>?@\\^|~:]/) break
          out = out substr(line, i, j - i); i = j
          continue
        }
        # a double quote as a character starts no string
        if (substr(line, i, 3) == q "\"" q) { out = out substr(line, i, 3); i += 3; continue }
        if (substr(line, i, 4) == q "\\\"" q) { out = out substr(line, i, 4); i += 4; continue }
        if (c == "\"") instr = 1
        out = out c
        i++
      }
    }
    END { gsub(/[ \t\r]/, "", out); printf "%s", out }
  '
}

version_of() { sed -n 's/^abiVersion = \([0-9][0-9]*\).*/\1/p'; }

for f in "$CDDL" "$VALIDATE" "$IR"; do
  git cat-file -e "$TAG:$f" 2>/dev/null || fail "$f is not in the release $TAG; when it moved, change the paths of scripts/ci/abi-version.sh"
  [ -f "$f" ] || fail "$f is missing"
done

T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT
# same STRIP FILE: FILE of the release and of the working tree are the same
# after STRIP; a failing STRIP is an error, not a match of two empty texts
same() {
  git show "$TAG:$2" >"$T/release" || fail "cannot read $2 of the release $TAG"
  "$1" <"$T/release" >"$T/a" || fail "cannot read $2 of the release $TAG"
  "$1" <"$2" >"$T/b" || fail "cannot read $2"
  cmp -s "$T/a" "$T/b"
}
DIFFERS=
same strip_cddl "$CDDL" || DIFFERS="$DIFFERS $CDDL"
same strip_hs "$VALIDATE" || DIFFERS="$DIFFERS $VALIDATE"

OLD=$(git show "$TAG:$IR" | version_of)
NEW=$(version_of <"$IR")
[ -n "$OLD" ] || fail "no abiVersion in $IR of the release $TAG"
[ -n "$NEW" ] || fail "no abiVersion in $IR"

if [ -z "$DIFFERS" ]; then
  [ "$NEW" -eq "$OLD" ] || fail "the ABI version is $NEW, but the release $TAG has $OLD and the ABI has not changed since; keep $OLD"
  echo "abi-version: $NEW, the same ABI as the release $TAG"
else
  [ "$NEW" -eq $((OLD + 1)) ] || fail "the ABI version is $NEW, but the release $TAG has $OLD and the ABI has changed since (in$DIFFERS); make it $((OLD + 1))"
  echo "abi-version: $NEW, one more than the release $TAG, as the ABI has changed (in$DIFFERS)"
fi
