#!/bin/sh
# Prints the version of the GMP that GHC links into golem
# (docs/adr/0004-binary-distribution-and-release.md). GHC with its own GMP
# (macOS) installs the GMP header as ghc-gmp.h; GHC with the system GMP
# (Alpine) has ghc-gmp.h include <gmp.h>, which is looked for in the
# folders of GMP_INCLUDE_DIRS (by default /usr/include /usr/local/include;
# the tests set it, docs/adr/0078).
set -eu
GHC_VERSION=${GHC_VERSION:-9.10.3}
if command -v "ghc-$GHC_VERSION" >/dev/null 2>&1; then GHC=ghc-$GHC_VERSION; else GHC=ghc; fi
LIBDIR=$("$GHC" --print-libdir)
version() { # version HEADER
  major=$(sed -n 's/^#define __GNU_MP_VERSION[[:space:]]*\([0-9]*\)$/\1/p' "$1")
  minor=$(sed -n 's/^#define __GNU_MP_VERSION_MINOR[[:space:]]*\([0-9]*\)$/\1/p' "$1")
  patch=$(sed -n 's/^#define __GNU_MP_VERSION_PATCHLEVEL[[:space:]]*\([0-9]*\)$/\1/p' "$1")
  if [ -n "$major" ] && [ -n "$minor" ] && [ -n "$patch" ]; then
    echo "$major.$minor.$patch"
    return 0
  fi
  return 1
}
HEADER=$(find "$LIBDIR" -name ghc-gmp.h | head -1)
[ -n "$HEADER" ] || {
  echo "gmp-version: ghc-gmp.h is not found under $LIBDIR" >&2
  exit 1
}
version "$HEADER" && exit 0
for d in ${GMP_INCLUDE_DIRS:-/usr/include /usr/local/include}; do
  if [ -f "$d/gmp.h" ] && version "$d/gmp.h"; then exit 0; fi
done
echo "gmp-version: the version of GMP is not found" >&2
exit 1
