#!/bin/sh
# Downloads the wasmtime C API for this platform into third_party/wasmtime
# and checks its SHA-256 (golem-plugin ADR 0001: wasmtime 50.0.1).
# On musl (Alpine), for which the glibc archives cannot be linked, it uses
# the musl archives of the same release (docs/adr/0004).
#
#   fetch-wasmtime.sh             fetch, or use third_party/wasmtime
#   fetch-wasmtime.sh --expected  print the VERSION line it expects
#
# third_party/wasmtime/VERSION holds the name of the archive and its
# SHA-256. The directory is used as it is only when both are those of this
# script; otherwise the archive is unpacked again (docs/adr/0044). The
# archive is kept in GOLEM_DOWNLOADS (third_party/downloads by default),
# which CI caches; scripts/ci/fetch-url.sh fetches it, with retries, only
# when the archive there is not of the SHA-256 below (docs/adr/0243).
set -eu
EXPECTED_ONLY=false
case ${1:-} in
  --expected) EXPECTED_ONLY=true ;;
  "") ;;
  *) echo "usage: fetch-wasmtime.sh [--expected]" >&2; exit 2 ;;
esac
VERSION=50.0.1
ROOT=$(cd "$(dirname "$0")/.." && pwd)
is_musl() {
  [ -f /etc/alpine-release ] || { ldd --version 2>&1 || true; } | grep -q musl
}
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) ARCH=aarch64-macos; SHA=a49327ca596fae51cd92e230265132112bb7896c5a24e4d58cd05b56612e26bb ;;
  Linux-x86_64)
    if is_musl; then ARCH=x86_64-musl; SHA=579216d5979f3b2f0714c039e097de13f0e6af62bbaa96588a0de1b7de9c20cb; else ARCH=x86_64-linux; SHA=e2c0c26e1aef52f82f0b9918ad6f34cc30f4b557aee3e261cb127a9462be8f4d; fi ;;
  Linux-aarch64)
    if is_musl; then ARCH=aarch64-musl; SHA=3f9f1875a83a3764987e34138db364d149d75b573c3e725559b779ba781f0e2f; else ARCH=aarch64-linux; SHA=1a36140a016a9cc098f02a37bb0cc7be6451032861ba70049127928d2f31ef84; fi ;;
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
ARCHIVE=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/$NAME.tar.xz
sh "$ROOT/scripts/ci/fetch-url.sh" "$ARCHIVE" "$SHA" "https://github.com/bytecodealliance/wasmtime/releases/download/v$VERSION/$NAME.tar.xz"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/x"
tar -xf "$ARCHIVE" -C "$TMP/x"
rm -rf "${DEST:?}"
mkdir -p "$DEST"
cp -R "$TMP/x/$NAME/include" "$DEST/include"
mkdir -p "$DEST/lib"
# link statically: only the archive
cp "$TMP/x/$NAME/lib/libwasmtime.a" "$DEST/lib/"
cp "$TMP/x/$NAME/LICENSE" "$DEST/LICENSE"
echo "$NAME $SHA" > "$DEST/VERSION"
write_local
