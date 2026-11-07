#!/bin/sh
# Checks the promise on diagnostic codes from v1.0.0 on
# (docs/adr/0174-compatibility-promises-for-1-0.md, docs/compatibility.md):
# a G code in use in the last release is still in use, and its severity has
# not gone up toward an error. The last release is the latest tag v* that
# HEAD reaches; its docs/diagnostics.md is compared with the one of the
# working tree, by the lines "- 重大度:" and "- 状態:" of each section.
#
# Severities go up in this order: info (情報), notice (お知らせ), warning
# (警告), a warning in dev and an error in prod, error (エラー). A code whose
# severity is set by the preflight settings is compared by the default of
# the built-in setting print, off coming before info. E codes (Emet) are not
# compared: Emet is experimental in 1.x.
#
# The check passes without comparing when there is no tag v*, when the tag
# comes before v1.0.0 (a prerelease of 1.0.0 does), and when the X of
# VERSION is not the one of the tag (a major version).
#
# A broken promise or a severity the script does not know goes to stderr,
# and the exit code is 1.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || exit 2

DOC=docs/diagnostics.md

fail() {
  printf 'diagnostic-codes: %s\n' "$*" >&2
  exit 1
}

if ! TAG=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null); then
  echo "diagnostic-codes: no release (no tag v*); the codes are not compared"
  exit 0
fi

# since_1 TAG: the tag vX.Y.Z[-PRE] is v1.0.0 or later
since_1() {
  v=${1#v}
  core=${v%%-*}
  x=${core%%.*}
  case $x in '' | *[!0-9]*) return 1 ;; esac
  [ "$x" -ge 1 ] || return 1
  [ "$core" != 1.0.0 ] || [ "$v" = "$core" ]
}

if ! since_1 "$TAG"; then
  echo "diagnostic-codes: the release $TAG comes before v1.0.0; the codes are not compared"
  exit 0
fi
[ -f VERSION ] || fail "VERSION is missing"
VERSION=$(cat VERSION)
RELEASE=${TAG#v}
if [ "${VERSION%%.*}" != "${RELEASE%%.*}" ]; then
  echo "diagnostic-codes: VERSION $VERSION is a major version after the release $TAG; the codes are not compared"
  exit 0
fi

# codes: "CODE RANK STATE" for each G section of the document on stdin;
# RANK is ? for a severity it does not know
codes() {
  awk '
    function flush() {
      if (code != "") print code, rank, state
      code = ""; rank = "?"; state = "?"
    }
    function rank_of(s,   p) {
      if (s == "情報") return 1
      if (s == "お知らせ") return 2
      if (s == "警告") return 3
      if (s == "dev では警告、prod ではエラー") return 4
      if (s == "エラー") return 5
      p = "プリフライトの設定による（"
      if (index(s, p) == 1) {
        if (index(s, "エラー") > 0) return 5
        if (index(s, "警告") > 0) return 3
        if (index(s, "off") > 0) return 0
      }
      return "?"
    }
    /^## / { flush(); if ($0 ~ /^## G[0-9][0-9][0-9][0-9][0-9]$/) code = substr($0, 4); next }
    code != "" && /^- 重大度: / { rank = rank_of(substr($0, length("- 重大度: ") + 1)); next }
    code != "" && /^- 状態: / { state = substr($0, length("- 状態: ") + 1); next }
    END { flush() }
  '
}

T=$(mktemp -d)
trap 'rm -rf "${T:?}"' EXIT
git show "$TAG:$DOC" >"$T/release.md" 2>/dev/null || fail "$DOC is not in the release $TAG"
[ -f "$DOC" ] || fail "$DOC is missing"
codes <"$T/release.md" >"$T/old" || fail "cannot read $DOC of the release $TAG"
codes <"$DOC" >"$T/new" || fail "cannot read $DOC"

awk -v tag="$TAG" '
  function name(r) {
    if (r == 0) return "off"
    if (r == 1) return "info"
    if (r == 2) return "notice"
    if (r == 3) return "warning"
    if (r == 4) return "a warning in dev and an error in prod"
    return "error"
  }
  NR == FNR { if ($3 == "使用中") { old[$1] = $2 } next }
  {
    seen[$1] = 1
    if ($2 == "?") { print $1 ": a severity this check does not know"; next }
    if (!($1 in old)) next
    if ($3 != "使用中") { print $1 ": in use in the release " tag ", now " $3 "; 1.x does not make a code obsolete"; next }
    if (old[$1] != "?" && $2 + 0 > old[$1] + 0) print $1 ": the severity went up from " name(old[$1]) " in the release " tag " to " name($2) "; 1.x does not raise a severity"
  }
  END {
    for (c in old) if (!(c in seen)) print c ": in use in the release " tag ", now not in the document; 1.x keeps a code in use"
  }
' "$T/old" "$T/new" | sort >"$T/broken"

if [ -s "$T/broken" ]; then
  echo "diagnostic-codes: the codes break the promise of 1.x (docs/compatibility.md):" >&2
  sed 's/^/  /' "$T/broken" >&2
  exit 1
fi
echo "diagnostic-codes: the G codes in use in the release $TAG are in use, with no severity raised"
