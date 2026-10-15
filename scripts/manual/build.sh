#!/bin/sh
# Typesets the manuals (docs/adr/0022-manual-as-typesetting-sample.md,
# docs/adr/0024-manual-audiences-and-policy.md): the user manual manual/
# and the developer manual manual-dev/.
#
#   build.sh [PROJECT...]     PROJECT is manual or manual-dev; both by default
#
# For each project it writes common/build-info.gm (build-info.sh), fetches
# the fonts into its fonts/ (or checks them, if they are there) and builds
# the PDF and the HTML into its build/. GOLEM chooses the golem to run, as
# in scripts/determinism.sh.
#
# A manual must build without a single diagnostic: an error, a warning or a
# notice fails it. A manifest with silence-notices fails before golem runs:
# a manual does not hide its notices.
#
# For the tests: GOLEM_MANUAL_ROOT is the folder that holds the projects
# (the root of the repository by default), and GOLEM_MANUAL_SKIP_FONTS=1
# does not fetch the fonts.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GOLEM_MANUAL_ROOT:-$HERE/../..}
ROOT=$(cd "$ROOT" && pwd)
GOLEM=${GOLEM:-golem}
[ $# -gt 0 ] || set -- manual manual-dev
for project in "$@"; do
  case "$project" in
    manual | manual-dev) ;;
    *) echo "usage: build.sh [manual|manual-dev]...; unknown: $project" >&2; exit 2 ;;
  esac
done

OUT=$(mktemp)
trap 'rm -f "$OUT"' EXIT
for project in "$@"; do
  DIR=$ROOT/$project
  if grep -qE '^[[:space:]]*silence-notices[[:space:]]*=' "$DIR/manifest.toml"; then
    echo "build: $project/manifest.toml has silence-notices; a manual must build without notices, not hide them (docs/adr/0024)" >&2
    exit 1
  fi
  sh "$HERE/build-info.sh" "$DIR"
  [ "${GOLEM_MANUAL_SKIP_FONTS-}" = 1 ] || sh "$HERE/fetch-fonts.sh" "$DIR/fonts"
  rm -rf "$DIR/build"
  CODE=0
  (cd "$DIR" && "$GOLEM" build --target pdf --target html) >"$OUT" 2>&1 || CODE=$?
  if [ "$CODE" -ne 0 ] || [ -s "$OUT" ]; then
    cat "$OUT" >&2
    echo "build: golem build of $project/ exited with $CODE and wrote the diagnostics above; a manual must build without any" >&2
    exit 1
  fi
done
