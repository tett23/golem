#!/bin/sh
# Regenerates the Golem parser from its grammar (golem-parser ADR 0002),
# and the parser of .gmx from its own (docs/adr/0148).
# Each module exports only the names that Golem uses (peg-hs ADR 0061):
# Golem.Parser uses parseSyntaxRecover, Golem.Parser.Convert uses
# nameOfSyntaxKind, and LabelSafetySpec uses parse of StrippedGrammar.
set -eu
cd "$(dirname "$0")/.."
CABAL=${CABAL:-cabal}
"$CABAL" build -v0 peg-cli:exe:peg-hs
PEG=$("$CABAL" list-bin -v0 peg-cli:exe:peg-hs)
"$PEG" gen modules/golem-parser/grammar/Golem.hpeg --Werror \
  --export parseSyntaxRecover --export nameOfSyntaxKind \
  -o modules/golem-parser/src/Golem/Parser/Generated.hs
# the grammar without its labels, for the label safety test (golem-parser ADR 0007)
"$PEG" gen modules/golem-parser/grammar/Golem.hpeg --Werror --strip-labels StrippedGrammar \
  --export parse -o modules/golem-parser/test/StrippedGrammar.hs
# the parser of .gmx: the AST, and the lossless tree for golem fmt
"$PEG" gen modules/golem-gmx/grammar/Gmx.hpeg --Werror \
  --export parse --export parseSyntax --export nameOfSyntaxKind \
  -o modules/golem-gmx/src/Golem/Gmx/Generated.hs
