#!/bin/sh
set -eu
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
src=modules/golem-eval/src/Golem/Eval/File.hs
mkdir -p "$build/$(dirname "$src")"
cp "$src" "$build/$src"
if [ "${1:-}" != baseline ]; then
  patch -s -d "$build" -p1 < experiments/syntax/review/review.patch
fi
ghc-9.10.3 --make -v0 -XGHC2021 -XOverloadedStrings -XLambdaCase -XDerivingStrategies \
  -package-db "${GOLEM_STORE_DB:?}" -package-db "${GOLEM_LOCAL_DB:?}" \
  -package-id golem-project-0.1.0-inplace -package-id golem-syntax-0.1.0-inplace -package-id golem-assemble-0.1.0-inplace -package-id golem-parser-0.1.0-inplace \
  -package-id golem-length-0.1.0-inplace -package-id golem-regex-0.1.0-inplace -package-id golem-eval-0.1.0-inplace -package-id golem-doc-0.1.0-inplace \
  -odir "$build" -hidir "$build" -o "$build/sources" \
  "$build/$src" modules/golem-eval/test/Support.hs experiments/syntax/review/Sources.hs
"$build/sources"
