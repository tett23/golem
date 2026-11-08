#!/bin/sh
# Downloads the toolchain of the 9.10 flavour of ghc-wasm-meta into
# third_party/ghc-wasm, for the wasm build of Golem (docs/adr/0199): the
# GHC (wasm32-wasi-ghc 9.10), wasi-sdk, libffi-wasm, cabal 3.14.2.0 and the
# Node that evaluates Template Haskell. x86-64 Linux only.
#
#   fetch-ghc-wasm.sh             fetch, or use third_party/ghc-wasm
#   fetch-ghc-wasm.sh --expected  print the VERSION line it expects
#
# Every archive is the one autogen.json of ghc-wasm-meta names at the
# commit META, checked against the SHA-256 written here and against the
# value of its SRI hash in autogen.json, written here in hex. cabal.th.config,
# which setup.sh of ghc-wasm-meta copies for the 9.10 flavour, is taken
# from the same commit and checked by its SHA-256. bootstrap.sh is not
# run: the part of setup.sh that unpacks the archives and writes env is
# copied below. Nothing is written to ~/.ghc-wasm. scripts/ci/fetch-url.sh
# fetches each file, with retries, into GOLEM_DOWNLOADS
# (third_party/downloads by default) under its name in the URL, and checks
# its SHA-256; a file there of the SHA-256 is not fetched again
# (docs/adr/0243). CI caches third_party/ghc-wasm, not these files.
#
# third_party/ghc-wasm/VERSION holds the commit and the SHA-256 of the
# archives; the directory is used as it is only when it is the line of this
# script (as scripts/fetch-wasmtime.sh does). After sourcing
# third_party/ghc-wasm/env, wasm32-wasi-ghc and wasm32-wasi-cabal are on the
# PATH; cabal keeps its files in third_party/ghc-wasm/.cabal.
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-ghc-wasm.sh [--expected]" >&2; exit 2 ;;
esac
META=8079eb96bbc63823d99ad8acaff0765532625474
META_RAW=https://gitlab.haskell.org/haskell-wasm/ghc-wasm-meta/-/raw/$META
BINDISTS=https://github.com/haskell-wasm/ghc-wasm-bindists/releases/download
# name, URL, SHA-256, and the SRI hash of autogen.json in hex
GHC_URL=$BINDISTS/20260731T193144/wasm32-wasi-ghc-9.10.tar.xz
GHC_SHA=3c78c2f632d516c622dac7efc7b0796322a5cdec8a7f6837bfa83495099ec5f1
GHC_SRI=sha256:3c78c2f632d516c622dac7efc7b0796322a5cdec8a7f6837bfa83495099ec5f1
SDK_URL=$BINDISTS/20251219T213239/wasi-sdk.tar.gz
SDK_SHA=fa1b236d847fa6ab5abecb08b8c1807178818f68b33029845eb15157d5bdbe47
SDK_SRI=sha256:fa1b236d847fa6ab5abecb08b8c1807178818f68b33029845eb15157d5bdbe47
FFI_URL=$BINDISTS/20250310T060803/libffi-wasm
FFI_SHA=526f4672ef732a5d29cc560bdd19809f2149a3338f295a2ad4d9d4da38a5234b
FFI_SRI=sha256:526f4672ef732a5d29cc560bdd19809f2149a3338f295a2ad4d9d4da38a5234b
CABAL_URL=https://downloads.haskell.org/cabal/cabal-install-3.14.2.0/cabal-install-3.14.2.0-x86_64-linux-alpine3_18.tar.xz
CABAL_SHA=7f7d7819e71dd198f47b108ce8d8a1450f38ea705f334c2e63e4d6301dc41319
CABAL_SRI=sha512:1eae393b3e93a36149b3c37f13794365d759a358c245b276fe5df5e62f86b879b70040ba32c7e9d8a87b0385236419255382fc7a185dc35f61b63af9de1c5238
NODE_URL=https://github.com/haskell-wasm/node-static/releases/download/v26.11.1/node-v26.11.1-linux-x64-static.tar.xz
NODE_SHA=21e3060c32d90c38ddcc038fbc672de63f6a29d9ec52ab9d42050acf95110acc
NODE_SRI=sha512:bb76e120b71a54f5cd816169bc7311804c9b1068ba33fdf5df2e4d96a13ebe0d4f039263c5b3fe055cd30583e8b4690c917019c0b0a132bdfad99dd8bae506da
TH_CONFIG_SHA=707f971061dea816f7dbc6eed59cc2e2e68709d8c1c147e21340d66b5659ccb5
LINE="ghc-wasm-meta-$META $GHC_SHA $SDK_SHA $FFI_SHA $CABAL_SHA $NODE_SHA $TH_CONFIG_SHA"
if [ "$EXPECTED_ONLY" = true ]; then printf '%s\n' "$LINE"; exit 0; fi
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "fetch-ghc-wasm.sh: the toolchain is fetched for x86-64 Linux only (docs/adr/0199), not $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEST=$ROOT/third_party/ghc-wasm
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$LINE" ]; then exit 0; fi

digest() { # ALG FILE: the hex digest
  openssl dgst "-$1" "$2" | sed 's/^.*= *//'
}
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
DOWNLOADS=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}
# fetch URL SHA256 SRI FILE: the file of the URL in DOWNLOADS, checked by
# both values, linked as FILE in TMP
fetch() {
  f=$DOWNLOADS/${1##*/}
  sh "$ROOT/scripts/ci/fetch-url.sh" "$f" "$2" "$1"
  alg=${3%%:*}
  got=$(digest "$alg" "$f")
  if [ "$got" != "${3#*:}" ]; then echo "the SRI hash of autogen.json ($alg) does not match $1: $got" >&2; exit 1; fi
  ln -s "$f" "$TMP/$4"
  echo "fetched $1 (sha256 $2)"
}
fetch "$GHC_URL" "$GHC_SHA" "$GHC_SRI" ghc.tar.xz
fetch "$SDK_URL" "$SDK_SHA" "$SDK_SRI" wasi-sdk.tar.gz
fetch "$FFI_URL" "$FFI_SHA" "$FFI_SRI" libffi-wasm.zip
fetch "$CABAL_URL" "$CABAL_SHA" "$CABAL_SRI" cabal.tar.xz
fetch "$NODE_URL" "$NODE_SHA" "$NODE_SRI" node.tar.xz
sh "$ROOT/scripts/ci/fetch-url.sh" "$DOWNLOADS/cabal.th.config" "$TH_CONFIG_SHA" "$META_RAW/cabal.th.config"
ln -s "$DOWNLOADS/cabal.th.config" "$TMP/cabal.th.config"

# what setup.sh does for the 9.10 flavour on x86-64 Linux, without
# wasmtime, binaryen, wasm-run and the npm packages for browsers
rm -rf "${DEST:?}"
mkdir -p "$DEST/wasi-sdk" "$DEST/nodejs" "$DEST/cabal/bin" "$DEST/wasm32-wasi-cabal/bin" "$DEST/wasm32-wasi-ghc" "$DEST/.cabal" "$TMP/ghc" "$TMP/ffi"
tar -xzf "$TMP/wasi-sdk.tar.gz" -C "$DEST/wasi-sdk" --no-same-owner --strip-components=1
(cd "$TMP/ffi" && unzip -q "$TMP/libffi-wasm.zip")
cp -R "$TMP/ffi/out/libffi-wasm/include/." "$DEST/wasi-sdk/share/wasi-sysroot/include/wasm32-wasi"
cp -R "$TMP/ffi/out/libffi-wasm/lib/." "$DEST/wasi-sdk/share/wasi-sysroot/lib/wasm32-wasi"
tar -xJf "$TMP/node.tar.xz" -C "$DEST/nodejs" --no-same-owner --strip-components=1
mkdir -p "$DEST/nodejs/lib/node_modules"
tar -xJf "$TMP/cabal.tar.xz" -C "$DEST/cabal/bin" --no-same-owner cabal

ENV=$DEST/env
: >"$ENV"
for p in wasm32-wasi-cabal/bin nodejs/lib/node_modules/.bin nodejs/bin wasi-sdk/bin wasm32-wasi-ghc/bin; do
  echo "export PATH=$DEST/$p:\$PATH" >>"$ENV"
done
S=$DEST/wasi-sdk/bin
cat >>"$ENV" <<EOF
export AR=$S/llvm-ar
export CC=$S/wasm32-wasi-clang
export CC_FOR_BUILD=cc
export CXX=$S/wasm32-wasi-clang++
export LD=$S/wasm-ld
export NM=$S/llvm-nm
export OBJCOPY=$S/llvm-objcopy
export OBJDUMP=$S/llvm-objdump
export RANLIB=$S/llvm-ranlib
export SIZE=$S/llvm-size
export STRINGS=$S/llvm-strings
export STRIP=$S/llvm-strip
export LLC=/bin/false
export OPT=/bin/false
export CONF_CC_OPTS_STAGE2="-Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
export CONF_CXX_OPTS_STAGE2="-fno-exceptions -Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
export CONF_GCC_LINKER_OPTS_STAGE2="-Wl,--error-limit=0,--keep-section=ghc_wasm_jsffi,--keep-section=target_features,--stack-first,--strip-debug "
export CONF_CC_OPTS_STAGE1="-Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
export CONF_CXX_OPTS_STAGE1="-fno-exceptions -Wno-error=int-conversion -O3 -mcpu=lime1 -mreference-types -msimd128"
export CONF_GCC_LINKER_OPTS_STAGE1="-Wl,--error-limit=0,--keep-section=ghc_wasm_jsffi,--keep-section=target_features,--stack-first,--strip-debug "
export CONFIGURE_ARGS="--host=x86_64-linux --target=wasm32-wasi --with-intree-gmp --with-system-libffi"
export NODE_PATH=$DEST/nodejs/lib/node_modules
EOF

tar -xJf "$TMP/ghc.tar.xz" -C "$TMP/ghc" --no-same-owner --strip-components=1
(cd "$TMP/ghc" && sh -c ". \"$ENV\" && ./configure \$CONFIGURE_ARGS --prefix=\"$DEST/wasm32-wasi-ghc\" && RelocatableBuild=YES exec make install") >"$TMP/ghc-install.log" 2>&1 || { tail -50 "$TMP/ghc-install.log" >&2; exit 1; }
# relocatable, as setup.sh makes it: the prefix becomes $topdir/../..
grep -lrIF "$DEST" "$DEST/wasm32-wasi-ghc" | while read -r f; do
  sed "s@$DEST@\$topdir/../..@g" "$f" >"$TMP/reloc"
  cat "$TMP/reloc" >"$f"
done
"$DEST/wasm32-wasi-ghc/bin/wasm32-wasi-ghc-pkg" recache

W=$DEST/wasm32-wasi-cabal/bin/wasm32-wasi-cabal
cat >"$W" <<'EOF'
#!/bin/sh
PREFIX=$(realpath "$(dirname "$0")"/../..)
CABAL_DIR=$PREFIX/.cabal exec $PREFIX/cabal/bin/cabal --with-compiler=$PREFIX/wasm32-wasi-ghc/bin/wasm32-wasi-ghc --with-hc-pkg=$PREFIX/wasm32-wasi-ghc/bin/wasm32-wasi-ghc-pkg --with-hsc2hs=$PREFIX/wasm32-wasi-ghc/bin/wasm32-wasi-hsc2hs --with-haddock=$PREFIX/wasm32-wasi-ghc/bin/wasm32-wasi-haddock ${1+"$@"}
EOF
chmod 755 "$W"
cp "$TMP/cabal.th.config" "$DEST/.cabal/config"
echo "$LINE" >"$DEST/VERSION"
