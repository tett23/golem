#!/bin/sh
# Decides whether a release is a patch, and the release a patch is checked
# against (docs/adr/0174-compatibility-promises-for-1-0.md,
# docs/adr/0212-patch-release-check-on-the-inputs-of-the-previous-release.md,
# docs/compatibility.md).
#
#   check-patch.sh TAG
#
# TAG vX.Y.Z[-PRE] is a patch when X and Z are 1 or more; the prerelease
# part is not looked at (v1.0.1-rc1 is a patch). The base of a patch is the
# latest tag that the commit of TAG reaches, not a prerelease, other than
# TAG, with the X.Y of TAG. For a patch with a base, the base is the one
# line of stdout; the patch job of the release workflow builds the inputs
# of the base with the golem of TAG and compares the result with the
# references of the base (scripts/release/check-patch-output.sh).
#
# Not a patch: one line on stdout says why, and nothing is compared.
# A patch without a base (no v1.0.0 before v1.0.1) is a mistake of the
# tags: it is said on stderr, and the exit code is 1. A missing TAG is exit
# code 2.
#
# The rule is copied in scripts/ci/abi-version.sh, without a file the two
# share (docs/adr/0212); change both together.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || exit 2

[ $# -eq 1 ] || {
  echo "usage: check-patch.sh TAG" >&2
  exit 2
}
TAG=$1
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || {
  printf 'check-patch: no tag %s\n' "$TAG" >&2
  exit 2
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

if ! is_patch "$TAG"; then
  echo "check-patch: $TAG is not a patch (X or Z is 0); the output is not compared"
  exit 0
fi
if ! BASE=$(patch_base "$TAG" "$TAG"); then
  printf 'check-patch: %s is a patch, but it reaches no release v%s.N other than itself that is not a prerelease; a patch is compared with one, so tag it first (docs/adr/0212)\n' "$TAG" "$(xy "$TAG")" >&2
  exit 1
fi
printf '%s\n' "$BASE"
