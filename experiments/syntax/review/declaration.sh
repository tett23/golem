#!/bin/sh
set -eu
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
src=modules/golem-parser/grammar/Golem.hpeg
parser=modules/golem-parser/src/Golem/Parser.hs
mkdir -p "$build/$(dirname "$src")" "$build/$(dirname "$parser")"
cp "$parser" "$build/$parser"
cp "$src" "$build/$src"
if [ "${1:-}" != baseline ]; then
  patch -s -d "$build" -p1 < experiments/syntax/review/declaration.patch
  patch -s -d "$build" -p1 < experiments/syntax/review/line-parser.patch
fi
peg-hs gen "$build/$src" --export parseSyntaxRecover --export nameOfSyntaxKind -o "$build/Generated.hs"
ghc-9.10.3 --make -v0 -XGHC2021 -XOverloadedStrings -XLambdaCase -XDerivingStrategies   -package-db "${GOLEM_STORE_DB:?}" -package-db "${GOLEM_LOCAL_DB:?}"   -package peg-runtime -package-id golem-parser-0.1.0-inplace -package-id golem-syntax-0.1.0-inplace   -odir "$build" -hidir "$build" -o "$build/declaration"   "$build/Generated.hs" modules/golem-parser/src/Golem/Parser/Convert.hs "$build/$parser" experiments/syntax/review/Declaration.hs
"$build/declaration"
