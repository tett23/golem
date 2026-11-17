#!/bin/sh
set -eu
build=$(mktemp -d)
trap 'rm -rf "$build"' EXIT
ghc-9.10.3 --make -v0 -XGHC2021 -XOverloadedStrings -XLambdaCase -XDerivingStrategies \
  -package-db "${GOLEM_STORE_DB:?}" -package-db "${GOLEM_LOCAL_DB:?}" \
  -package-id golem-project-0.1.0-inplace -package-id golem-syntax-0.1.0-inplace -package-id golem-assemble-0.1.0-inplace -package-id golem-parser-0.1.0-inplace \
  -package-id golem-length-0.1.0-inplace -package-id golem-regex-0.1.0-inplace -package-id tml-prsr-2.0.2.0-ba3eb5c2 \
  -odir "$build" -hidir "$build" -o "$build/dimensions" \
  modules/golem-project/src/Golem/Project/Style.hs experiments/syntax/Dimensions.hs
"$build/dimensions"
