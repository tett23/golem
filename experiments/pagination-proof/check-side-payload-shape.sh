#!/bin/sh
# Tie fresh and reused payload construction to the modeled producer boundary.
set -eu
root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
source=${1:-$root/modules/golem-typeset/src/Golem/Typeset/Flow.hs}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
awk '
  /^composeBeside fe widths unitAt i pf = go / { body = 1 }
  body && /^[ ]+c <- forceComposed / { capture = 1 }
  capture && /^[ ]+\| free,/ { exit }
  capture { sub(/--.*/, ""); print }
' "$source" | tr -d '[:space:]' >"$tmp/fresh"
cat <<'EXPECTED' | tr -d '[:space:]' >"$tmp/expected-fresh"
c <- forceComposed (composeUnit fe widths (lineWidths !!) u)
((j, (c, offset)) :) <$> go (j + 1) (offset + length (cLines c)) (distance + fromIntegral (length (cLines c)) * unitPitch u)
EXPECTED
diff -u "$tmp/expected-fresh" "$tmp/fresh"
awk '
  /^buildFlow inp geom fonts images prev assumed = do$/ { body = 1 }
  body && /^      reusedBeside i = do$/ { capture = 1 }
  capture && /^      mapper ::/ { exit }
  capture { sub(/--.*/, ""); print }
' "$source" | tr -d '[:space:]' >"$tmp/cached"
cat <<'EXPECTED' | tr -d '[:space:]' >"$tmp/expected-cached"
reusedBeside i = do
  p <- prev
  let before = cuBesides (bComposed p)
      js = besideParagraphs unitAt before i
      around = [k | k <- [i .. maybe (i + 1) (+ 1) (listToMaybe (reverse js))], k < length units]
  if all (`Set.member` unchanged) around then Just [(j, before Map.! j) | j <- js] else Nothing
EXPECTED
diff -u "$tmp/expected-cached" "$tmp/cached"
