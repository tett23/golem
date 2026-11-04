#!/bin/sh
# Downloads the wasmtime C API for this platform into third_party/wasmtime
# and checks its SHA-256 (golem-plugin ADR 0001: wasmtime 49.0.5).
# On musl (Alpine), for which the glibc archives cannot be linked, it uses
# the musl archives of the same release (docs/adr/0004).
#
#   fetch-wasmtime.sh             fetch, or use third_party/wasmtime
#   fetch-wasmtime.sh --expected  print the VERSION line it expects
#
# third_party/wasmtime/VERSION holds the name of the archive and its
# SHA-256. The directory is used as it is only when both are those of this
# script; otherwise the archive is fetched again (docs/adr/0044).
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-wasmtime.sh [--expected]" >&2; exit 2 ;;
esac
VERSION=49.0.5
ROOT=$(cd "$(dirname "$0")/.." && pwd)
is_musl() {
  [ -f /etc/alpine-release ] || { ldd --version 2>&1 || true; } | grep -q musl
}
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) ARCH=aarch64-macos; SHA=16bf4584b586bf18c708bf7b98cb94c415c0201575d5ad24860dcbdf83c213e5 ;;
  Linux-x86_64)
    if is_musl; then ARCH=x86_64-musl; SHA=a56728962f434ad6eed02c6b9313069b0044e2ac3143574bc9fa2c0f5cb2cebc; else ARCH=x86_64-linux; SHA=9dd9a5b4d29bfe172656e9c060ab494ce8db2c15e659351bd86ae891bb3bd330; fi ;;
  Linux-aarch64)
    if is_musl; then ARCH=aarch64-musl; SHA=2e2a6cb8cabf22f88f2dc52018ac0b048bfc9ba45b09455bb5b17af6588239b1; else ARCH=aarch64-linux; SHA=e9286bc2ec8e216aa63c7b4004fa1a7a786bd9e0b7541e70247210ec83f452ed; fi ;;
  *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
NAME=wasmtime-v$VERSION-$ARCH-c-api
if [ "$EXPECTED_ONLY" = true ]; then printf '%s %s\n' "$NAME" "$SHA"; exit 0; fi
DEST=$ROOT/third_party/wasmtime
write_local() {
  # cabal needs absolute paths for libraries of a registered package
  LOCAL=$ROOT/cabal.project.local
  if ! grep -q "third_party/wasmtime" "$LOCAL" 2>/dev/null; then
    printf '\n-- written by scripts/fetch-wasmtime.sh\npackage golem-plugin\n  extra-include-dirs: %s/include\n  extra-lib-dirs: %s/lib\n' "$DEST" "$DEST" >> "$LOCAL"
  fi
}
if [ -f "$DEST/VERSION" ] && [ "$(cat "$DEST/VERSION")" = "$NAME $SHA" ]; then write_local; exit 0; fi
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

curl -sSfL -o "$TMP/$NAME.tar.xz" "https://github.com/bytecodealliance/wasmtime/releases/download/v$VERSION/$NAME.tar.xz"
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$TMP/$NAME.tar.xz" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$TMP/$NAME.tar.xz" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA" ]; then echo "SHA-256 mismatch for $NAME: $ACTUAL" >&2; exit 1; fi
mkdir -p "$TMP/x"
tar -xf "$TMP/$NAME.tar.xz" -C "$TMP/x"
rm -rf "${DEST:?}"
mkdir -p "$DEST"
cp -R "$TMP/x/$NAME/include" "$DEST/include"
mkdir -p "$DEST/lib"
# link statically: only the archive
cp "$TMP/x/$NAME/lib/libwasmtime.a" "$DEST/lib/"
cp "$TMP/x/$NAME/LICENSE" "$DEST/LICENSE"
echo "$NAME $SHA" > "$DEST/VERSION"
write_local
