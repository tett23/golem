#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
reject() {
  area=$1
  change=$2
  marker=$3
  sed "$change" "experiments/formal/$area.hs" >"$tmp/$area.hs"
  if experiments/formal/compile.sh -imodules/golem-layout/test "$tmp/$area.hs" >"$tmp/log" 2>&1; then
    echo "$area: mutation survived" >&2
    exit 1
  fi
  grep -F "$marker" "$tmp/log" >/dev/null
  echo "$area: rejected"
}
reject Parser 's/TE.encodeUtf8 p) + 6/TE.encodeUtf8 p) + 7/' 'G01012'
reject Position 's/(TE.encodeUtf16LE current) `div` 2/(TE.encodeUtf8 current)/' 'user error'
reject Length 's/r == 1 \&\& odd q/r == 1/' 'rounding counterexample'
reject Pagination 's/ids (SLine i) = \[i\]/ids (SLine _) = []/' 'Rule'
reject Shape 's/width t = advance t %/width t = sum [advance (Data.Text.singleton c) | c <- Data.Text.unpack t] %/; /import Data.Ratio/a\
import Data.Text qualified
' 'H1 fixture has no pair adjustment'
sed 's/w1 + w2 + adv (bcText c1 <> bcText c2) - adv (bcText c1) - adv (bcText c2)/w1 + w2/' modules/golem-layout/test/NoBreakEnum.hs >"$tmp/NoBreakEnum.hs"
if experiments/formal/compile.sh -i"$tmp" -imodules/golem-layout/test experiments/formal/Shape.hs >"$tmp/join.log" 2>&1; then
  echo 'S1: uncorrected widths survived' >&2
  exit 1
fi
grep -F '684851' "$tmp/join.log" >/dev/null
grep -F '694026' "$tmp/join.log" >/dev/null
echo 'S1: rejected uncorrected AV width (684851 versus 694026 sp)'
