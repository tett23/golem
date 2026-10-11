#!/bin/sh
# Regenerates the Golem parser from its grammar (golem-parser ADR 0002).
set -eu
cd "$(dirname "$0")/.."
CABAL=${CABAL:-cabal}
"$CABAL" build -v0 peg-cli:exe:peg-hs
PEG=$("$CABAL" list-bin -v0 peg-cli:exe:peg-hs)
"$PEG" modules/golem-parser/grammar/Golem.peg -o modules/golem-parser/src/Golem/Parser/Generated.hs
