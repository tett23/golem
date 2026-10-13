#!/bin/sh
# Regenerates the Golem parser from its grammar (golem-parser ADR 0002).
set -eu
cd "$(dirname "$0")/.."
CABAL=${CABAL:-cabal}
"$CABAL" build -v0 peg-cli:exe:peg-hs
PEG=$("$CABAL" list-bin -v0 peg-cli:exe:peg-hs)
"$PEG" gen modules/golem-parser/grammar/Golem.hpeg --Werror -o modules/golem-parser/src/Golem/Parser/Generated.hs
# the grammar without its labels, for the label safety test (golem-parser ADR 0007)
"$PEG" gen modules/golem-parser/grammar/Golem.hpeg --Werror --strip-labels StrippedGrammar \
  -o modules/golem-parser/test/StrippedGrammar.hs
