#!/bin/sh
# Stops a push when the wasmtime that the build of this checkout links is not
# the one that scripts/fetch-wasmtime.sh pins (docs/adr/0418). .githooks/pre-push
# runs it once per push.
#
# The linked wasmtime is the parent of the extra-lib-dirs entry of
# cabal.project.local that ends in third_party/wasmtime/lib; without one, it
# is third_party/wasmtime of this checkout. A worktree whose
# cabal.project.local was copied from the main checkout links the main
# checkout's wasmtime. It compares the VERSION line there with the line of
# fetch-wasmtime.sh --expected, and exits 1 when they differ, when there is no
# VERSION, or when --expected fails. It neither uses the network nor writes a
# file, and nothing skips it: fetch wasmtime again instead.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SUFFIX=third_party/wasmtime/lib
# the first extra-lib-dirs entry ending in third_party/wasmtime/lib
LIB=
if [ -f "$ROOT/cabal.project.local" ]; then
  LIB=$(sed -n 's/^[[:space:]]*extra-lib-dirs[[:space:]]*:[[:space:]]*//p' "$ROOT/cabal.project.local" |
    tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s:/*$::' |
    grep -E "(^|/)$SUFFIX\$" | head -n 1 || :)
fi
case $LIB in
  "") DEST=$ROOT/third_party/wasmtime ;;
  /*) DEST=$(dirname "$LIB") ;;
  *) DEST=$ROOT/$(dirname "$LIB") ;;
esac
how() {
  cat >&2 <<MSG
check-local-wasmtime: fetch the pinned wasmtime into $DEST:
  (cd $(dirname "$(dirname "$DEST")") && sh scripts/fetch-wasmtime.sh)
To push from a worktree a branch that changes the pinned wasmtime, run
scripts/fetch-wasmtime.sh in that worktree and point the extra-include-dirs
and extra-lib-dirs of its cabal.project.local at its own third_party/wasmtime.
MSG
}
if ! EXPECTED=$(sh "$ROOT/scripts/fetch-wasmtime.sh" --expected); then
  echo "check-local-wasmtime: scripts/fetch-wasmtime.sh --expected failed; wasmtime has no archive for this platform, so the push stops (docs/adr/0418)" >&2
  exit 1
fi
if [ ! -f "$DEST/VERSION" ]; then
  echo "check-local-wasmtime: $DEST/VERSION does not exist; wasmtime has not been fetched (docs/adr/0418)" >&2
  how
  exit 1
fi
ACTUAL=$(cat "$DEST/VERSION")
if [ "$ACTUAL" != "$EXPECTED" ]; then
  printf 'check-local-wasmtime: the build links another wasmtime than the pinned one (docs/adr/0418)\n  linked: %s (%s/VERSION)\n  pinned: %s (scripts/fetch-wasmtime.sh --expected)\n' "$ACTUAL" "$DEST" "$EXPECTED" >&2
  how
  exit 1
fi
