#!/bin/sh
# Checks that each outlined figure of the manuals was made from its source
# as it is (golem-pdf ADR 0009): the comment at the top of
# PROJECT/images/NAME.svg names the SHA-256 of PROJECT/images/src/NAME.svg.
# It does not run Inkscape. After editing a source, run
# scripts/manual/outline-figures.sh and commit both files.
#
#   check-figures.sh [DIR...]    DIR is manual and manual-dev by default
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -gt 0 ] || set -- "$HERE/../../manual" "$HERE/../../manual-dev"
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
status=0
for DIR in "$@"; do
  for src in "$DIR"/images/src/*.svg; do
    [ -f "$src" ] || continue
    name=${src##*/}
    out=$DIR/images/$name
    want=$($SHA "$src" | cut -d ' ' -f 1)
    if [ ! -f "$out" ]; then
      echo "check-figures: ${DIR##*/}/images/$name is missing; run scripts/manual/outline-figures.sh ${DIR##*/} ${name%.svg}" >&2
      status=1
      continue
    fi
    got=$(sed -n 's/.*from images\/src\/[^ ]* (sha256 \([0-9a-f]*\)).*/\1/p' "$out" | head -n 1)
    if [ "$got" != "$want" ]; then
      echo "check-figures: ${DIR##*/}/images/$name was not made from images/src/$name as it is; run scripts/manual/outline-figures.sh ${DIR##*/} ${name%.svg}" >&2
      status=1
    fi
  done
done
exit $status
