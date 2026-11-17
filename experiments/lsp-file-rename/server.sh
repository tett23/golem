#!/bin/sh
set -eu
db="${BUILT_TREE:?Cabal build tree}/dist-newstyle/packagedb/ghc-9.10.3"
storedb=$(ls -d "${CABAL_DIR:-$HOME/.cabal}/store"/ghc-9.10.3*/package.db | head -1)
out=${PROBE_BUILD:?temporary build directory}
mkdir -p "$out/Golem/Lsp"
cp "$BUILT_TREE/modules/golem-lsp/src/Golem/Lsp/Server.hs" "$out/Golem/Lsp/Server.hs"
(cd "$out" && patch -s -p0) < server.patch
printf '%s\n' 'module Main where' 'import Golem.Lsp.Server (runGolemLsp)' 'import System.Exit (exitFailure)' 'main = runGolemLsp >>= \code -> if code == 0 then pure () else exitFailure' > "$out/Main.hs"
deps=$(ghc-pkg-9.10.3 --package-db "$storedb" --package-db "$db" field --ipid golem-lsp-0.1.0-inplace depends --simple-output)
for dep in $deps; do set -- "$@" -package-id "$dep"; done
ghc-9.10.3 -threaded -v0 -hide-all-packages -package-db "$storedb" -package-db "$db" "$@" -package-id golem-lsp-0.1.0-inplace -package-id golem-parser-0.1.0-inplace -package-id golem-project-0.1.0-inplace -XGHC2021 -XLambdaCase -XOverloadedStrings -XDerivingStrategies -i"$out" -i. -outputdir "$out" "$out/Main.hs" -o "$out/server"
