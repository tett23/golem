#!/bin/sh
# Writes THIRD_PARTY_LICENSES/ for a release archive
# (docs/adr/0004-binary-distribution-and-release.md,
# docs/adr/0007-third-party-licenses.md).
#
#   licenses.sh PLAN_JSON OUT TAG
#
# What goes in follows the link map of golem (LINK_MAP), through
# link-components.sh:
#   haskell      every package that exe:golem depends on in PLAN_JSON
#                (dist-newstyle/cache/plan.json; the libraries it links,
#                not the build tools nor the dependencies of the tests)
#                and that does not start with golem-:
#                  - Hackage packages from the cabal package cache (CABAL_PACKAGES)
#                  - peg-hs (source-repository-package) from dist-newstyle/src/
#                  - packages that come with GHC from its share/doc (GHC_DOCDIR)
#   ghc          GHC and its RTS
#   wasmtime     licenses/wasmtime-v<version>/ of the repository, after
#                the crates and the C members of libwasmtime.a are checked
#                against it, and the LICENSE of wasmtime
#   apk:<origin> the license files of the Alpine package from APK_LICENSES,
#                or from licenses/alpine/<origin>/ of the repository
#   compiler-rt  the license of LLVM (Apache-2.0 WITH LLVM-exception)
# The C libraries and data bundled in the repository (HarfBuzz, FreeType,
# hyph-utf8; zlib comes with the haskell packages) and GMP (from the GMP
# source archive, GMP_SOURCE) are always added.
# A component without a license file is an error (exit code 1).
#
# Environment:
#   GOLEM_ROOT        the repository (default: two directories up)
#   LINK_MAP          the link map of golem (required)
#   CABAL_PACKAGES    the Hackage package cache (default: from cabal path)
#   GHC_VERSION       default 9.10.3
#   GHC_DOCDIR        share/doc/<arch>-ghc-<version> of GHC (default: found from
#                     ghc-<version> --print-libdir, or ghc --print-libdir)
#   GHC_LIBDIR        the libdir of GHC (default: ghc-<version> --print-libdir)
#   GMP_SOURCE        gmp-<version>.tar.xz, checked by fetch-gmp.sh (required)
#   GMP_VERSION       the GMP linked into the executable (default: found by gmp-version.sh)
#   APK_DB            the installed database of apk (default: /lib/apk/db/installed)
#   APK_ROOT          the root of the paths in APK_DB (default: /)
#   APK_LICENSES      the license files of the Alpine packages (default: /usr/share/licenses)
#   WASMTIME_NM       the output of nm of libwasmtime.a       (needed when
#   WASMTIME_STRINGS  the output of strings -a of libwasmtime.a  the map has
#   WASMTIME_AR       the output of ar t of libwasmtime.a        wasmtime)
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
[ -n "${LINK_MAP:-}" ] || fail "LINK_MAP (the link map of golem) is needed"
[ -f "$LINK_MAP" ] || fail "no such file: $LINK_MAP"
APK_LICENSES=${APK_LICENSES:-/usr/share/licenses}

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
if [ -z "${GHC_DOCDIR:-}" ] || [ -z "${GHC_LIBDIR:-}" ]; then
  if command -v "ghc-$GHC_VERSION" >/dev/null 2>&1; then GHC=ghc-$GHC_VERSION; else GHC=ghc; fi
  GHC_LIBDIR=${GHC_LIBDIR:-$("$GHC" --print-libdir)}
fi
export GHC_LIBDIR
if [ -z "${GHC_DOCDIR:-}" ]; then
  LIBDIR=$GHC_LIBDIR
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
mkdir -p "$OUT"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
MISSING=

# the components of the link map (docs/adr/0007)
sh "$HERE/link-components.sh" "$LINK_MAP" >"$TMP/components" || fail "cannot map $LINK_MAP to the components"
sh "$HERE/link-components.sh" "$LINK_MAP" --apk >"$TMP/apk" || fail "cannot map $LINK_MAP to the Alpine packages"
has() { cut -f1 "$TMP/components" | grep -qxF "$1"; }

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
if has haskell; then mkdir -p "$OUT/haskell"; else : >"$TMP/packages"; fi

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
if has ghc; then copy "$GHC_DOCDIR/ghc-$GHC_VERSION/LICENSE" ghc; fi
copy "$ROOT/modules/golem-font/cbits/harfbuzz/COPYING" harfbuzz
copy "$ROOT/modules/golem-font/cbits/freetype/LICENSE.TXT" freetype
copy "$ROOT/modules/golem-font/cbits/freetype/docs/FTL.TXT" freetype
copy "$ROOT/modules/golem-layout/data/hyphenation/LICENSE-hyph-en-us.txt" hyph-en-us
if has compiler-rt; then
  # compiler-rt of LLVM is under Apache-2.0 WITH LLVM-exception, the same
  # text as the LICENSE of wasmtime
  copy "$ROOT/third_party/wasmtime/LICENSE" compiler-rt
fi

# ---- wasmtime: the crates and the C members of libwasmtime.a against
# licenses/wasmtime-v<version>/ (docs/adr/0007)
if has wasmtime; then
  [ -f "$ROOT/third_party/wasmtime/VERSION" ] || fail "no third_party/wasmtime/VERSION (run scripts/fetch-wasmtime.sh)"
  WNAME=$(cat "$ROOT/third_party/wasmtime/VERSION")
  WVER=$(printf '%s\n' "$WNAME" | sed -n 's/^\(wasmtime-v[0-9][0-9.]*\)-.*-c-api$/\1/p')
  WPLATFORM=$(printf '%s\n' "$WNAME" | sed -n 's/^wasmtime-v[0-9][0-9.]*-\(.*\)-c-api$/\1/p')
  [ -n "$WVER" ] && [ -n "$WPLATFORM" ] || fail "not the name of a wasmtime C API archive: $WNAME"
  WDIR=$ROOT/licenses/$WVER
  for f in MANIFEST.tsv rust/MANIFEST.tsv rust/VERSION rust/STD_CRATES c-objects.tsv; do
    [ -f "$WDIR/$f" ] || fail "no $WDIR/$f (run scripts/wasmtime-licenses.sh)"
  done
  for v in WASMTIME_NM WASMTIME_STRINGS WASMTIME_AR; do
    eval "f=\${$v:-}"
    [ -n "$f" ] && [ -f "$f" ] || fail "$v is needed for wasmtime"
  done
  sh "$HERE/rust-crates.sh" "$WASMTIME_NM" "$WASMTIME_STRINGS" >"$TMP/crates" || fail "cannot list the crates of libwasmtime.a"
  # the known crates: name<TAB>version, by the library name and by the
  # package name with - replaced by _, and name<TAB>* for the standard library
  {
    for m in "$WDIR/MANIFEST.tsv" "$WDIR/rust/MANIFEST.tsv"; do
      awk -F '\t' 'NR > 1 { p = $1; gsub(/-/, "_", p); print p "\t" $2; print $3 "\t" $2 }' "$m"
    done
    sed 's/$/	*/' "$WDIR/rust/STD_CRATES"
  } >"$TMP/known"
  awk -F '\t' '
    FNR == NR { if ($2 == "*") any[$1] = 1; else { pair[$1 "\t" $2] = 1; name[$1] = 1 } next }
    $1 != "crate" { next }
    $2 in any { next }
    $3 == "-" && ($2 in name) { next }
    ($2 "\t" $3) in pair { next }
    { print $2 ($3 == "-" ? "" : " " $3) }' "$TMP/known" "$TMP/crates" >"$TMP/unknown-crates"
  if [ -s "$TMP/unknown-crates" ]; then
    {
      echo "licenses: crates of libwasmtime.a not in $WDIR (run scripts/wasmtime-licenses.sh):"
      sed 's/^/  /' "$TMP/unknown-crates"
    } >&2
    exit 1
  fi
  RUSTC=$(sed -n 's/^rustc	//p' "$TMP/crates")
  [ "$RUSTC" = "$(cat "$WDIR/rust/VERSION")" ] ||
    fail "libwasmtime.a was built by rustc '$RUSTC', not $(cat "$WDIR/rust/VERSION") of $WDIR/rust/VERSION"
  # the C and assembly members, without the hash of the cc crate
  grep -v -e '\.rcgu\.o$' -e '^__\.SYMDEF' -e '^/' "$WASMTIME_AR" | grep '\.o$' |
    sed 's/^[0-9a-f]\{16\}-//' | LC_ALL=C sort -u >"$TMP/c-members" || true
  awk -F '\t' -v p="$WPLATFORM" 'NR > 1 && $1 == p { print $2 }' "$WDIR/c-objects.tsv" | LC_ALL=C sort -u >"$TMP/c-known"
  LC_ALL=C comm -23 "$TMP/c-members" "$TMP/c-known" >"$TMP/c-unknown"
  if [ -s "$TMP/c-unknown" ]; then
    {
      echo "licenses: C members of libwasmtime.a not in $WDIR/c-objects.tsv for $WPLATFORM:"
      sed 's/^/  /' "$TMP/c-unknown"
    } >&2
    exit 1
  fi
  mkdir -p "$OUT/wasmtime"
  cp -R "$WDIR/." "$OUT/wasmtime/"
  copy "$ROOT/third_party/wasmtime/LICENSE" wasmtime
fi

# ---- the Alpine packages (docs/adr/0007)
cut -f1 "$TMP/apk" | awk '!seen[$0]++' >"$TMP/origins"
APK_MISSING=
while IFS= read -r origin; do
  dest=$OUT/$origin
  [ ! -e "$dest" ] || fail "the directory of the Alpine package $origin is taken by another component"
  found=
  for name in "$origin" $(awk -F '\t' -v o="$origin" '$1 == o { print $2 }' "$TMP/apk"); do
    d=$APK_LICENSES/$name
    [ -d "$d" ] || continue
    if [ -n "$(find "$d" -type f | head -n 1)" ]; then
      mkdir -p "$dest"
      cp -R "$d/." "$dest/"
      found=1
    fi
  done
  if [ -z "$found" ] && [ -d "$ROOT/licenses/alpine/$origin" ]; then
    ldir=$ROOT/licenses/alpine/$origin
    [ -f "$ldir/VERSION" ] || fail "no $ldir/VERSION"
    want=$(cat "$ldir/VERSION")
    have=$(awk -F '\t' -v o="$origin" '$1 == o { print $3; exit }' "$TMP/apk" | sed 's/-r[0-9]*$//')
    [ "$want" = any ] || [ "$want" = "$have" ] ||
      fail "licenses/alpine/$origin is of $want, but the linked $origin is $have"
    mkdir -p "$dest"
    for f in "$ldir"/*; do
      [ "$(basename "$f")" = VERSION ] || cp -R "$f" "$dest/"
    done
    found=1
  fi
  [ -n "$found" ] || APK_MISSING="$APK_MISSING $origin"
done <"$TMP/origins"
[ -z "$APK_MISSING" ] || fail "no license document for the Alpine packages:$APK_MISSING (in $APK_LICENSES or licenses/alpine/)"
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

# the list of the components, from the directories written above
{
  line() { printf '  %-30s%s\n' "$1" "$2"; }
  if [ -d "$OUT/haskell" ]; then
    line 'haskell/<package>-<version>/' 'Haskell packages: the dependencies on Hackage,'
    line '' 'peg-hs, and the libraries that come with GHC'
  fi
  [ ! -d "$OUT/ghc" ] || line ghc/ "GHC $GHC_VERSION and its runtime system (RTS)"
  line harfbuzz/ HarfBuzz
  line freetype/ 'FreeType, used under the FreeType License (FTL.TXT)'
  if [ -d "$OUT/wasmtime" ]; then
    line wasmtime/ 'the wasmtime C API (LICENSE), and the Rust crates'
    line '' 'and the Rust standard library in it (MANIFEST.tsv,'
    line '' 'crates/<crate>-<version>/, rust/)'
  fi
  line hyph-en-us/ 'the US English hyphenation patterns of hyph-utf8'
  line gmp/ 'GNU MP (GMP)'
  if ls -d "$OUT"/haskell/zlib-clib-* >/dev/null 2>&1; then line 'haskell/zlib-clib-*/' 'zlib, through the zlib-clib package'; fi
  [ ! -d "$OUT/compiler-rt" ] || line compiler-rt/ 'compiler-rt of LLVM (Apache-2.0 WITH LLVM-exception)'
  while IFS= read -r origin; do
    line "$origin/" "the Alpine Linux package of $origin:"
    awk -F '\t' -v o="$origin" '$1 == o && !seen[$2]++ { printf "  %-30s  %s %s (%s)\n", "", $2, $3, $4 }' "$TMP/apk"
  done <"$TMP/origins"
} >"$TMP/list"

if grep -qx gcc "$TMP/origins"; then
  cat >"$TMP/gcc" <<'EOF'

GCC runtime libraries
---------------------

libgcc and libstdc++ are under the GNU General Public License, version 3
(gcc/COPYING3), with the GCC Runtime Library Exception, version 3.1
(gcc/COPYING.RUNTIME). golem is compiled with GCC, an Eligible Compilation
Process, and the exception permits distributing it under the terms of its
own license.
EOF
else
  : >"$TMP/gcc"
fi

cat >"$OUT/README" <<EOF
THIRD-PARTY LICENSES OF GOLEM $TAG

The golem executable is distributed under the MIT License (LICENSE-golem).
It contains the following software, linked statically, and data. Each
directory holds the license of one component.

$(cat "$TMP/list")$(cat "$TMP/gcc")

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
