#!/bin/sh
# Checks the release archive of golem.wasm that package-wasm.sh makes
# (docs/adr/0230, docs/adr/0199):
#
#   check-wasm-archive.sh ARCHIVE
#
# ARCHIVE is golem-<tag>-wasm32-wasi.tar.gz, with ARCHIVE.sha256 beside it.
# The top directory of the archive (the name of ARCHIVE without .tar.gz)
# must have golem.wasm, LICENSE, README and THIRD_PARTY_LICENSES/, and
# THIRD_PARTY_LICENSES/ the documents of the components that 8 of
# docs/adr/0199 names, by the names licenses.sh --wasm writes them under:
# the wasm GHC and its RTS, the boot packages, HarfBuzz, FreeType, hyph-utf8,
# zlib, wasi-libc, libc++ and GMP. ARCHIVE.sha256 must be the SHA-256 of
# ARCHIVE. Every missing name is written on stderr, and the exit code is 1.
set -eu
[ $# -eq 1 ] || {
  echo "usage: check-wasm-archive.sh ARCHIVE" >&2
  exit 2
}
ARCHIVE=$1
[ -f "$ARCHIVE" ] || {
  echo "check-wasm-archive: no such file: $ARCHIVE" >&2
  exit 1
}
NAME=$(basename "$ARCHIVE" .tar.gz)
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
tar -tzf "$ARCHIVE" >"$TMP/list" || {
  echo "check-wasm-archive: cannot list $ARCHIVE" >&2
  exit 1
}
# the files, without the top directory; a leading ./ is dropped
sed -n "s|^\(\./\)\{0,1\}$NAME/||p" "$TMP/list" | grep -v '/$' >"$TMP/files" || true

FAILED=0
missing() {
  echo "check-wasm-archive: $ARCHIVE has no $1" >&2
  FAILED=1
}
# a file, by its name under the top directory
for f in golem.wasm LICENSE README; do
  grep -qxF "$f" "$TMP/files" || missing "$f"
done
grep -q '^THIRD_PARTY_LICENSES/' "$TMP/files" || missing THIRD_PARTY_LICENSES/
# the documents that licenses.sh --wasm writes (docs/adr/0199, 8)
#   ghc/            the wasm GHC and its RTS
#   harfbuzz/       HarfBuzz
#   freetype/       FreeType, with the FreeType License
#   hyph-en-us/     the hyph-utf8 patterns
#   wasi-sdk/       wasi-libc, and libc++ and libc++abi of LLVM
#   gmp/            GMP
for f in ghc/LICENSE harfbuzz/COPYING freetype/LICENSE.TXT freetype/FTL.TXT \
  hyph-en-us/LICENSE-hyph-en-us.txt \
  wasi-sdk/wasi-libc/COPYRIGHT-musl wasi-sdk/wasi-libc/LICENSE-APACHE \
  wasi-sdk/wasi-libc/LICENSE-APACHE-LLVM wasi-sdk/wasi-libc/LICENSE-MIT \
  wasi-sdk/llvm/libcxx-LICENSE.TXT wasi-sdk/llvm/libcxxabi-LICENSE.TXT \
  gmp/COPYINGv3 gmp/COPYING.LESSERv3; do
  grep -qxF "THIRD_PARTY_LICENSES/$f" "$TMP/files" || missing "THIRD_PARTY_LICENSES/$f"
done
# the packages of Haskell, haskell/<package>-<version>/ with a document:
# the boot packages of the wasm GHC (base, ghc-prim, ghc-bignum,
# ghc-internal), and zlib-clib, which has zlib
for p in base ghc-prim ghc-bignum ghc-internal zlib-clib; do
  grep -Eq "^THIRD_PARTY_LICENSES/haskell/$p-[0-9][0-9.]*/[^/]+\$" "$TMP/files" ||
    missing "THIRD_PARTY_LICENSES/haskell/$p-<version>/"
done

# the .sha256 of package-wasm.sh: "<SHA-256>  <name of the archive>"
if [ -f "$ARCHIVE.sha256" ]; then
  if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$ARCHIVE" | cut -d' ' -f1); else SUM=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1); fi
  [ "$(cat "$ARCHIVE.sha256")" = "$SUM  $NAME.tar.gz" ] || {
    echo "check-wasm-archive: $ARCHIVE.sha256 is not the SHA-256 of $ARCHIVE ($SUM)" >&2
    FAILED=1
  }
else
  echo "check-wasm-archive: no $ARCHIVE.sha256" >&2
  FAILED=1
fi
[ "$FAILED" -eq 0 ] || exit 1
echo "check-wasm-archive: $ARCHIVE has golem.wasm, LICENSE, README and the documents of THIRD_PARTY_LICENSES/"
