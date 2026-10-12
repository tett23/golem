#!/bin/sh
# Writes THIRD_PARTY_LICENSES/ for a release archive
# (docs/adr/0004-binary-distribution-and-release.md).
#
#   licenses.sh PLAN_JSON OUT TAG
#
# PLAN_JSON is dist-newstyle/cache/plan.json of the build. Every package that
# exe:golem depends on (the libraries it links, not the build tools nor the
# dependencies of the tests) and that does not start with golem- gets its
# license files:
#   - Hackage packages from the cabal package cache (CABAL_PACKAGES)
#   - peg-hs (source-repository-package) from dist-newstyle/src/
#   - packages that come with GHC from its share/doc (GHC_DOCDIR)
# and the C libraries and data bundled in the repository, GHC and its RTS,
# and GMP (from the GMP source archive, GMP_SOURCE) are added.
# A dependency without a license file is an error (exit code 1).
#
# Environment:
#   GOLEM_ROOT      the repository (default: two directories up)
#   CABAL_PACKAGES  the Hackage package cache (default: from cabal path)
#   GHC_VERSION     default 9.10.3
#   GHC_DOCDIR      share/doc/<arch>-ghc-<version> of GHC (default: found from
#                   ghc-<version> --print-libdir, or ghc --print-libdir)
#   GMP_SOURCE      gmp-<version>.tar.xz, checked by fetch-gmp.sh (required)
#   GMP_VERSION     the GMP linked into the executable (default: found by gmp-version.sh)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GOLEM_ROOT:-$(cd "$HERE/../.." && pwd)}
GHC_VERSION=${GHC_VERSION:-9.10.3}
REPO_URL=https://github.com/tett23/golem

fail() {
  printf 'licenses: %s\n' "$*" >&2
  exit 1
}

[ $# -eq 3 ] || {
  echo "usage: licenses.sh PLAN_JSON OUT TAG" >&2
  exit 2
}
PLAN=$1
OUT=$2
TAG=$3
[ -f "$PLAN" ] || fail "no such file: $PLAN"
command -v jq >/dev/null 2>&1 || fail "jq is needed"

if [ -z "${CABAL_PACKAGES:-}" ]; then
  CACHE=$(cabal path --remote-repo-cache 2>/dev/null || true)
  if [ -n "$CACHE" ] && [ -d "$CACHE/hackage.haskell.org" ]; then
    CABAL_PACKAGES=$CACHE/hackage.haskell.org
  elif [ -d "$HOME/.cabal/packages/hackage.haskell.org" ]; then
    CABAL_PACKAGES=$HOME/.cabal/packages/hackage.haskell.org
  else
    CABAL_PACKAGES=${XDG_CACHE_HOME:-$HOME/.cache}/cabal/packages/hackage.haskell.org
  fi
fi
if [ -z "${GHC_DOCDIR:-}" ]; then
  if command -v "ghc-$GHC_VERSION" >/dev/null 2>&1; then GHC=ghc-$GHC_VERSION; else GHC=ghc; fi
  LIBDIR=$("$GHC" --print-libdir)
  for d in "$LIBDIR"/../../../share/doc/*-ghc-"$GHC_VERSION" "$LIBDIR"/../../share/doc/*-ghc-"$GHC_VERSION" "$LIBDIR"/../share/doc/*-ghc-"$GHC_VERSION"; do
    if [ -d "$d" ]; then
      GHC_DOCDIR=$d
      break
    fi
  done
  [ -n "${GHC_DOCDIR:-}" ] || fail "share/doc of GHC $GHC_VERSION is not found from $LIBDIR (set GHC_DOCDIR)"
fi
[ -n "${GMP_SOURCE:-}" ] && [ -f "$GMP_SOURCE" ] || fail "GMP_SOURCE (the GMP source archive) is needed"
GMP_VERSION=${GMP_VERSION:-$(GHC_VERSION=$GHC_VERSION sh "$HERE/gmp-version.sh")}

# the license files at the top of a directory or an archive listing
# (case-insensitive)
LICENSE_RE='^(LICEN[CS]E|COPYING|COPYRIGHT|NOTICE)([._-][^/]*)?$'

rm -rf "${OUT:?}"
mkdir -p "$OUT/haskell"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
MISSING=

# One line per package that exe:golem depends on, directly or not:
# type<TAB>source type<TAB>name<TAB>version. The closure follows the
# libraries (depends, and the depends of the lib components), not the
# build tools (exe-depends) nor Setup.hs (setup).
jq -r '
  ."install-plan" as $plan
  | (reduce $plan[] as $e ({}; .[$e.id] = $e)) as $by
  | def deps: (.depends // []) + [(.components // {}) | to_entries[] | select(.key | startswith("lib")) | .value.depends[]?];
    def fix(f): (f) as $n | if $n == . then . else ($n | fix(f)) end;
    [$plan[] | select(."pkg-name" == "golem-cli" and ."component-name" == "exe:golem") | .id]
  | if length == 0 then error("exe:golem of golem-cli is not in the plan") else . end
  | fix(. + [.[] | $by[.] // empty | deps[]] | unique)
  | [.[] | $by[.] // empty | select((."pkg-name" | startswith("golem-")) | not)
     | [.type, (."pkg-src".type // "-"), ."pkg-name", ."pkg-version"] | @tsv]
  | unique[]' "$PLAN" >"$TMP/packages" || fail "cannot read the dependencies of exe:golem from $PLAN"

while IFS='	' read -r type src name version; do
  dest=$OUT/haskell/$name-$version
  case "$type/$src" in
    pre-existing/*)
      if [ "$name" = rts ]; then
        # the RTS is part of GHC and under its license
        [ -f "$GHC_DOCDIR/ghc-$GHC_VERSION/LICENSE" ] || MISSING="$MISSING $name-$version"
        continue
      fi
      found=
      for f in "$GHC_DOCDIR/$name-$version"/*; do
        [ -f "$f" ] || continue
        if basename "$f" | grep -Eiq "$LICENSE_RE"; then
          mkdir -p "$dest"
          cp "$f" "$dest/"
          found=1
        fi
      done
      [ -n "$found" ] || MISSING="$MISSING $name-$version"
      ;;
    configured/repo-tar)
      archive=$CABAL_PACKAGES/$name/$version/$name-$version.tar.gz
      if [ ! -f "$archive" ]; then
        MISSING="$MISSING $name-$version"
        continue
      fi
      files=$(tar -tzf "$archive" | sed -n "s|^$name-$version/||p" | grep -Ei "$LICENSE_RE" || true)
      if [ -z "$files" ]; then
        MISSING="$MISSING $name-$version"
        continue
      fi
      mkdir -p "$TMP/x" "$dest"
      for f in $files; do
        tar -xzf "$archive" -C "$TMP/x" "$name-$version/$f"
        cp "$TMP/x/$name-$version/$f" "$dest/"
      done
      ;;
    configured/source-repo)
      found=
      for d in "$ROOT"/dist-newstyle/src/peg-hs-*/packages/"$name" "$ROOT"/dist-newstyle/src/peg-hs-*; do
        [ -d "$d" ] || continue
        for f in "$d"/*; do
          [ -f "$f" ] || continue
          if basename "$f" | grep -Eiq "$LICENSE_RE"; then
            mkdir -p "$dest"
            cp "$f" "$dest/"
            found=1
          fi
        done
        [ -z "$found" ] || break
      done
      [ -n "$found" ] || MISSING="$MISSING $name-$version"
      ;;
    *)
      MISSING="$MISSING $name-$version"
      ;;
  esac
done <"$TMP/packages"

[ -z "$MISSING" ] || fail "no license file for:$MISSING"

copy() { # copy SOURCE DIR
  [ -f "$1" ] || fail "no license file: $1"
  mkdir -p "$OUT/$2"
  cp "$1" "$OUT/$2/"
}
copy "$GHC_DOCDIR/ghc-$GHC_VERSION/LICENSE" ghc
copy "$ROOT/modules/golem-font/cbits/harfbuzz/COPYING" harfbuzz
copy "$ROOT/modules/golem-font/cbits/freetype/LICENSE.TXT" freetype
copy "$ROOT/modules/golem-font/cbits/freetype/docs/FTL.TXT" freetype
copy "$ROOT/third_party/wasmtime/LICENSE" wasmtime
copy "$ROOT/modules/golem-layout/data/hyphenation/LICENSE-hyph-en-us.txt" hyph-en-us
[ -f "$ROOT/LICENSE" ] || fail "no LICENSE in $ROOT"
cp "$ROOT/LICENSE" "$OUT/LICENSE-golem"

mkdir -p "$TMP/gmp" "$OUT/gmp"
tar -xJf "$GMP_SOURCE" -C "$TMP/gmp"
for f in COPYINGv3 COPYING.LESSERv3; do
  [ -f "$TMP/gmp/gmp-$GMP_VERSION/$f" ] || fail "no $f in $GMP_SOURCE (is it gmp-$GMP_VERSION?)"
  cp "$TMP/gmp/gmp-$GMP_VERSION/$f" "$OUT/gmp/"
done

FREETYPE_YEAR=$(sed -n 's/.*Copyright (C) 1996-\([0-9]\{4\}\).*/\1/p' "$ROOT/modules/golem-font/cbits/freetype/include/freetype/freetype.h" | head -1)
[ -n "$FREETYPE_YEAR" ] || fail "the copyright year of FreeType is not found"

cat >"$OUT/README" <<EOF
THIRD-PARTY LICENSES OF GOLEM $TAG

The golem executable is distributed under the MIT License (LICENSE-golem).
It contains the following software, linked statically, and data. Each
directory holds the license of one component.

  haskell/<package>-<version>/  Haskell packages: the dependencies on Hackage,
                                peg-hs, and the libraries that come with GHC
  ghc/                          GHC $GHC_VERSION and its runtime system (RTS)
  harfbuzz/                     HarfBuzz
  freetype/                     FreeType, used under the FreeType License (FTL.TXT)
  wasmtime/                     the wasmtime C API
  hyph-en-us/                   the US English hyphenation patterns of hyph-utf8
  gmp/                          GNU MP (GMP)
  haskell/zlib-clib-*/          zlib, through the zlib-clib package

FreeType
--------

Portions of this software are copyright © $FREETYPE_YEAR The FreeType Project (https://freetype.org).
All rights reserved.

GNU MP
------

This executable links GNU MP $GMP_VERSION statically. GNU MP is free
software under the GNU Lesser General Public License, version 3
(gmp/COPYING.LESSERv3), which builds on the GNU General Public License,
version 3 (gmp/COPYINGv3).

The source of that GNU MP is attached to the GitHub release of golem $TAG
as gmp-$GMP_VERSION.tar.xz. The source of golem at this version, which
you can build and link with another version of GNU MP, is at
$REPO_URL/tree/$TAG
EOF
