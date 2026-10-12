#!/bin/sh
# Downloads the wasmtime C API for this platform into third_party/wasmtime
# and checks its SHA-256 (golem-plugin ADR 0001: wasmtime 49.0.2).
# On musl (Alpine), for which the glibc archives cannot be linked, it
# builds the C API from the source of the v49.0.2 tag, checked by the
# hash of its commit (docs/adr/0004).
set -eu
VERSION=49.0.2
# the commit of the v49.0.2 tag of wasmtime, for the build from source
COMMIT=
ROOT=$(cd "$(dirname "$0")/.." && pwd)
is_musl() {
  [ -f /etc/alpine-release ] || { ldd --version 2>&1 || true; } | grep -q musl
}
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) ARCH=aarch64-macos; SHA=f7000ab1661495d09b9dc87a11b356941b4e6097f295434bcb30a8cf1393b0d5 ;;
  Linux-x86_64)
    if is_musl; then ARCH=x86_64-musl; SHA=; else ARCH=x86_64-linux; SHA=4818e139aeb83b7adbaaf41b267bf18992c18463ae26d1a9acdcfc63ea9eb316; fi ;;
  Linux-aarch64)
    if is_musl; then ARCH=aarch64-musl; SHA=; else ARCH=aarch64-linux; SHA=a97a874152b5fb49c4720b39b96a71d00ba61eab5ad59976163b7ddd1a3b14c0; fi ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
NAME=wasmtime-v$VERSION-$ARCH-c-api
DEST=$ROOT/third_party/wasmtime
write_local() {
  # cabal needs absolute paths for libraries of a registered package
  LOCAL=$ROOT/cabal.project.local
  if ! grep -q "third_party/wasmtime" "$LOCAL" 2>/dev/null; then
    printf '\n-- written by scripts/fetch-wasmtime.sh\npackage golem-plugin\n  extra-include-dirs: %s/include\n  extra-lib-dirs: %s/lib\n' "$DEST" "$DEST" >> "$LOCAL"
  fi
}
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$NAME" ]; then write_local; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

if [ -z "$SHA" ]; then
  # musl: no archive of the C API is pinned, so build it from the source
  # (needs git, cargo, cmake and a C compiler)
  if [ -z "$COMMIT" ]; then
    echo "the commit of wasmtime v$VERSION is not pinned: set COMMIT in scripts/fetch-wasmtime.sh (docs/adr/0004)" >&2
    exit 1
  fi
  git clone --quiet --depth 1 --branch "v$VERSION" --recurse-submodules --shallow-submodules \
    https://github.com/bytecodealliance/wasmtime.git "$TMP/src"
  ACTUAL=$(git -C "$TMP/src" rev-parse HEAD)
  if [ "$ACTUAL" != "$COMMIT" ]; then echo "the tag v$VERSION of wasmtime is $ACTUAL, not $COMMIT" >&2; exit 1; fi
  # CMake builds libwasmtime.a with cargo (Cargo.lock of the tag) and
  # installs the headers with the generated wasmtime/conf.h
  cmake -S "$TMP/src/crates/c-api" -B "$TMP/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$TMP/install"
  cmake --build "$TMP/build" --config Release
  cmake --install "$TMP/build" --config Release
  mkdir -p "$TMP/x/$NAME/lib"
  cp -R "$TMP/install/include" "$TMP/x/$NAME/include"
  cp "$TMP/install/lib/libwasmtime.a" "$TMP/x/$NAME/lib/"
  cp "$TMP/src/LICENSE" "$TMP/x/$NAME/LICENSE"
else
  curl -sSfL -o "$TMP/$NAME.tar.xz" "https://github.com/bytecodealliance/wasmtime/releases/download/v$VERSION/$NAME.tar.xz"
  if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$TMP/$NAME.tar.xz" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$TMP/$NAME.tar.xz" | cut -d' ' -f1); fi
  if [ "$ACTUAL" != "$SHA" ]; then echo "SHA-256 mismatch for $NAME: $ACTUAL" >&2; exit 1; fi
  mkdir -p "$TMP/x"
  tar -xf "$TMP/$NAME.tar.xz" -C "$TMP/x"
fi
rm -rf "${DEST:?}"
mkdir -p "$DEST"
cp -R "$TMP/x/$NAME/include" "$DEST/include"
mkdir -p "$DEST/lib"
# link statically: only the archive
cp "$TMP/x/$NAME/lib/libwasmtime.a" "$DEST/lib/"
cp "$TMP/x/$NAME/LICENSE" "$DEST/LICENSE"
echo "$NAME" > "$DEST/VERSION"
write_local
