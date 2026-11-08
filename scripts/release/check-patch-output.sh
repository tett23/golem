#!/bin/sh
# Checks that the golem of a patch release builds the inputs of its base
# release as the base release did
# (docs/adr/0212-patch-release-check-on-the-inputs-of-the-previous-release.md,
# docs/adr/0174-compatibility-promises-for-1-0.md). The patch job of the
# release workflow runs it with the base of scripts/release/check-patch.sh.
#
#   check-patch-output.sh BASE GOLEM
#
# BASE is the tag of the base release, GOLEM the path of the golem of the
# patch. The tree of BASE is taken out with git worktree, and its own
# scripts run there with GOLEM:
#
#   - scripts/visual/fetch-shem.sh (unless SHEM is given), then
#     scripts/visual/build.sh and scripts/visual/check.sh, which compares
#     the pages with the scripts/visual/pages/ of BASE (docs/adr/0094);
#   - when BASE has scripts/determinism/hashes.txt (docs/adr/0173),
#     scripts/determinism.sh --no-manuals, whose list is compared with that
#     hashes.txt but the lines of PDF files: the Producer and the instance
#     ID of a PDF hold the version of Golem.
#
# The inputs are those of BASE, so a manual or a fixture fixed after BASE
# changes nothing here; only the golem of the patch is checked.
#
# Exit code 0: the same output. Exit code 1: the pages and the lines that
# differ go to stderr. Exit code 2: a wrong argument, or a script of BASE
# that cannot run.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
cd "$ROOT" || exit 2

[ $# -eq 2 ] || {
  echo "usage: check-patch-output.sh BASE GOLEM" >&2
  exit 2
}
BASE=$1
case $2 in
  /*) GOLEM=$2 ;;
  *) GOLEM=$(pwd)/$2 ;;
esac
git rev-parse -q --verify "refs/tags/$BASE" >/dev/null || {
  printf 'check-patch-output: no tag %s\n' "$BASE" >&2
  exit 2
}
[ -x "$GOLEM" ] || {
  printf 'check-patch-output: no golem at %s\n' "$GOLEM" >&2
  exit 2
}

W=$(mktemp -d)
TREE=$W/base
cleanup() {
  git worktree remove --force "$TREE" >/dev/null 2>&1 || true
  git worktree prune >/dev/null 2>&1 || true
  rm -rf "${W:?}"
}
trap cleanup EXIT
git worktree add -q --detach "$TREE" "$BASE" >/dev/null 2>&1 || {
  printf 'check-patch-output: cannot take out the tree of %s\n' "$BASE" >&2
  exit 2
}

STATUS=0
if [ -z "${SHEM-}" ]; then
  sh "$TREE/scripts/visual/fetch-shem.sh" >&2 || {
    printf 'check-patch-output: the scripts/visual/fetch-shem.sh of %s failed\n' "$BASE" >&2
    exit 2
  }
fi
GOLEM=$GOLEM sh "$TREE/scripts/visual/build.sh" "$W/pdfs" >&2 || {
  printf 'check-patch-output: the scripts/visual/build.sh of %s failed with %s\n' "$BASE" "$GOLEM" >&2
  exit 1
}
if ! sh "$TREE/scripts/visual/check.sh" "$W/pdfs" >"$W/pages" 2>"$W/pages.err"; then
  printf 'check-patch-output: the golem of the patch builds the inputs of %s to other pages than its references (a patch does not change the output):\n' "$BASE" >&2
  sed 's/^/  /' "$W/pages" "$W/pages.err" >&2
  STATUS=1
fi

HASHES=$TREE/scripts/determinism/hashes.txt
if [ -f "$HASHES" ]; then
  GOLEM=$GOLEM sh "$TREE/scripts/determinism.sh" --no-manuals >"$W/list" || {
    printf 'check-patch-output: the scripts/determinism.sh of %s failed with %s\n' "$BASE" "$GOLEM" >&2
    exit 1
  }
  grep -v '\.pdf$' "$HASHES" >"$W/old" || true
  grep -v '\.pdf$' "$W/list" >"$W/new" || true
  if ! cmp -s "$W/old" "$W/new"; then
    printf 'check-patch-output: the golem of the patch builds the inputs of %s to other outputs than its scripts/determinism/hashes.txt, the PDF lines left out (- %s, + the patch):\n' "$BASE" "$BASE" >&2
    diff "$W/old" "$W/new" | grep '^[<>]' | sed 's/^</  -/; s/^>/  +/' >&2
    STATUS=1
  fi
fi

[ "$STATUS" -ne 0 ] || printf 'check-patch-output: the golem of the patch builds the inputs of %s to the same output\n' "$BASE"
exit "$STATUS"
