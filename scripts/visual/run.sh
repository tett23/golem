#!/bin/sh
# Runs the visual regression test on this machine
# (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md): typesets the
# inputs with build.sh, installs shem with fetch-shem.sh (unless SHEM is
# given) and compares the pages with check.sh.
#
#   run.sh            compares with the references
#   run.sh --accept   writes the references (check.sh --accept)
#
# GOLEM chooses the golem to run, as in scripts/determinism.sh.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
case "${1-}" in
  "" | --accept) ;;
  *) echo "usage: run.sh [--accept]" >&2; exit 2 ;;
esac
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
sh "$HERE/build.sh" "$WORK/pdfs"
[ -n "${SHEM-}" ] || sh "$HERE/fetch-shem.sh"
sh "$HERE/check.sh" "$@" "$WORK/pdfs"
