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
# From v1.0.0 on (docs/adr/0174-compatibility-promises-for-1-0.md), the
# VERSION X.Y.Z[-PRE] of HEAD is a patch when X and Z are 1 or more, the
# prerelease part not looked at (docs/adr/0212). A patch keeps the ABI and
# its version: abiVersion is the one of the release. A patch needs a base,
# the latest tag HEAD reaches that is not a prerelease, not vVERSION, with
# the X.Y of VERSION; without one, the check fails. The rule is copied
# from scripts/release/check-patch.sh, without a file the two share
# (docs/adr/0212); change both together.
#
# Not a patch, when the release is v1.0.0 or later and VERSION has its X
# (a minor version, or its prerelease): a new abiVersion needs the heading
# "### ABI のバージョン <new>" in the docs/compatibility.md of the release
# (the announcement). A prerelease of 1.0.0 (v1.0.0-rc1) comes before
# v1.0.0. Another X (a major version) follows the rule of one more per
# release only.
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

# since_1 TAG: the tag vX.Y.Z[-PRE] is v1.0.0 or later
since_1() {
  v=${1#v}
  core=${v%%-*}
  x=${core%%.*}
  case $x in '' | *[!0-9]*) return 1 ;; esac
  [ "$x" -ge 1 ] || return 1
  [ "$core" != 1.0.0 ] || [ "$v" = "$core" ]
}
# is_patch VERSION: X.Y.Z[-PRE], with or without v, has X and Z of 1 or more
# (docs/adr/0212)
is_patch() {
  core=${1#v}
  core=${core%%-*}
  x=${core%%.*}
  z=${core##*.}
  case $x$z in '' | *[!0-9]*) return 1 ;; esac
  [ "$x" -ge 1 ] && [ "$z" -ge 1 ]
}
# xy VERSION: X.Y of X.Y.Z[-PRE], with or without v
xy() {
  core=${1#v}
  core=${core%%-*}
  printf '%s' "${core%.*}"
}
# patch_base REV VERSION: the latest tag REV reaches, not a prerelease, not
# vVERSION, with the X.Y of VERSION; fails when there is none
patch_base() {
  b=$(git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' --exclude "v${2#v}" "$1" 2>/dev/null) || return 1
  [ "$(xy "$b")" = "$(xy "$2")" ] || return 1
  printf '%s\n' "$b"
}

if since_1 "$TAG"; then
  [ -f VERSION ] || fail "VERSION is missing"
  HEAD_VERSION=$(cat VERSION)
  RELEASE_VERSION=${TAG#v}
  if is_patch "$HEAD_VERSION"; then
    BASE=$(patch_base HEAD "$HEAD_VERSION") ||
      fail "VERSION $HEAD_VERSION is a patch, but HEAD reaches no release v$(xy "$HEAD_VERSION").N other than v$HEAD_VERSION that is not a prerelease; a patch is checked against one (docs/adr/0212)"
    [ "$NEW" -eq "$OLD" ] && [ -z "$DIFFERS" ] ||
      fail "VERSION $HEAD_VERSION is a patch of the release $BASE, and a patch version does not change the ABI (docs/compatibility.md); keep the ABI and its version $OLD of the release $TAG"
  elif [ "${HEAD_VERSION%%.*}" = "${RELEASE_VERSION%%.*}" ]; then
    if [ "$NEW" -ne "$OLD" ]; then
      HEADING="### ABI のバージョン $NEW"
      git show "$TAG:docs/compatibility.md" 2>/dev/null | grep -qxF -- "$HEADING" ||
        fail "the ABI version is $NEW, but the docs/compatibility.md of the release $TAG does not announce it (no heading \"$HEADING\"); a minor version changes the ABI only after a release announced it"
    fi
  fi
fi

if [ -z "$DIFFERS" ]; then
  [ "$NEW" -eq "$OLD" ] || fail "the ABI version is $NEW, but the release $TAG has $OLD and the ABI has not changed since; keep $OLD"
  echo "abi-version: $NEW, the same ABI as the release $TAG"
else
  [ "$NEW" -eq $((OLD + 1)) ] || fail "the ABI version is $NEW, but the release $TAG has $OLD and the ABI has changed since (in$DIFFERS); make it $((OLD + 1))"
  echo "abi-version: $NEW, one more than the release $TAG, as the ABI has changed (in$DIFFERS)"
fi
