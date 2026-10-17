#!/bin/sh
# Checks that each outlined figure of the developer manual was made from
# its source as it is (golem-pdf ADR 0009): the comment at the top of
# manual-dev/images/NAME.svg names the SHA-256 of manual-dev/images/src/NAME.svg.
# It does not run Inkscape. After editing a source, run
# scripts/manual/outline-figures.sh and commit both files.
#
#   check-figures.sh [DIR]    DIR is manual-dev by default
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DIR=${1:-$HERE/../../manual-dev}
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
status=0
for src in "$DIR"/images/src/*.svg; do
  name=${src##*/}
  out=$DIR/images/$name
  want=$($SHA "$src" | cut -d ' ' -f 1)
  if [ ! -f "$out" ]; then
    echo "check-figures: images/$name is missing; run scripts/manual/outline-figures.sh ${name%.svg}" >&2
    status=1
    continue
  fi
  got=$(sed -n 's/.*from images\/src\/[^ ]* (sha256 \([0-9a-f]*\)).*/\1/p' "$out" | head -n 1)
  if [ "$got" != "$want" ]; then
    echo "check-figures: images/$name was not made from images/src/$name as it is; run scripts/manual/outline-figures.sh ${name%.svg}" >&2
    status=1
  fi
done
exit $status
