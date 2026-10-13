#!/bin/sh
# Writes licenses/wasmtime-v<version>/: the license documents of the Rust
# crates, the Rust standard library and compiler-rt in libwasmtime.a
# (docs/adr/0007-third-party-licenses.md). Run it by hand when the version
# of wasmtime changes, and commit the output. It connects to the network:
# GitHub (the wasmtime C API archives and source, the license of
# compiler-rt), crates.io (through cargo), and the Rust toolchain (rustup).
#
#   scripts/wasmtime-licenses.sh
#
# Needs a POSIX shell, curl, git, jq, nm, strings, ar, cargo and rustup.
#
# Environment:
#   WORK       a directory to keep the downloads in between runs (default: a
#              temporary directory, removed at the end)
#   SKIP_RUST  1 to skip step 6 (the Rust standard library and compiler-rt)
#              when the toolchain cannot be installed. The output then has
#              no rust/, step 7 only reports, and licenses.sh rejects the
#              output until the script runs in full.
#   NM         the nm to use (default: nm; it must read ELF and Mach-O)
#
# Steps (the numbers of the ADR):
#   1. the C API archives of the three platforms, by the SHA-256 of
#      scripts/fetch-wasmtime.sh; their file lists go to ARCHIVES
#   2. the crates and the rustc of each libwasmtime.a (release/rust-crates.sh)
#   3. the source of wasmtime at the commit of the tag, checked by its hash
#   4. cargo metadata of crates/c-api for each target: the closure of the
#      normal dependencies of wasmtime-c-api, their union
#   5. the license files of each crate (and of the bundled C sources of the
#      crates with links, by the table below)
#   6. the license files of the Rust standard library, of the crates.io
#      crates it depends on, and of compiler-rt
#   7. every crate of 2 is in 4 or 6
#   8. c-objects.tsv: the C and assembly members of each libwasmtime.a; the
#      component column is filled by hand and kept from the previous output
set -eu
VERSION=49.0.2
# the commit of the tag v49.0.2 (git ls-remote, 2026-10-13)
COMMIT=3c8a3e79aa3188a1a12b3aebbaa097abccceac92
RUSTC_VERSION=1.98.0
# the SHA-256 of compiler-rt/LICENSE.TXT of llvm-project at the version
# of LLVM of rustc $RUSTC_VERSION; recorded at the first full run
COMPILER_RT_LICENSE_SHA256=
ARCHES="aarch64-macos x86_64-musl aarch64-musl"
LICENSE_RE='^(LICEN[CS]E|COPYING|COPYRIGHT|NOTICE)([._-][^/]*)?$'

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
OUT=$ROOT/licenses/wasmtime-v$VERSION
NM=${NM:-nm}

fail() {
  printf 'wasmtime-licenses: %s\n' "$*" >&2
  exit 1
}
for c in curl git jq "$NM" strings ar cargo; do
  command -v "$c" >/dev/null 2>&1 || fail "$c is needed"
done
if [ -n "${WORK:-}" ]; then
  mkdir -p "$WORK"
else
  WORK=$(mktemp -d)
  trap 'rm -rf "${WORK:?}"' EXIT
fi
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
archive_sha() {
  case "$1" in
    aarch64-macos) echo f7000ab1661495d09b9dc87a11b356941b4e6097f295434bcb30a8cf1393b0d5 ;;
    x86_64-musl) echo c7039fec0ac87b4f65e6f893c8bad7fb4f5e1c2e3e10d0e927828bd075ac2e17 ;;
    aarch64-musl) echo a67c334d594d05d6059c7e4cbf8fe4c73c0e9dbb049f18e9729d93bc71c3206a ;;
  esac
}
triple() {
  case "$1" in
    aarch64-macos) echo aarch64-apple-darwin ;;
    x86_64-musl) echo x86_64-unknown-linux-musl ;;
    aarch64-musl) echo aarch64-unknown-linux-musl ;;
  esac
}
# the license files of the C sources bundled in the crates with links,
# relative to the crate: name<TAB>files
LINKS_TABLE='zstd-sys	zstd/LICENSE zstd/COPYING
ring	third_party/fiat/LICENSE src/polyfill/once_cell/LICENSE-APACHE src/polyfill/once_cell/LICENSE-MIT
capstone-sys	capstone/LICENSE.TXT capstone/LICENSE_LLVM.TXT'
# crates with links that bundle no C sources of others
LINKS_TOP='rayon-core wasmtime-c-api-impl'
# crates published without a license file: <name>-<version><TAB>files of
# another crate of the same project or of the same license text, relative
# to the registry (the license chosen is in NOTE)
NOFILE_TABLE='fxprof-processed-profile-0.8.1	anyhow-1.0.103/LICENSE-APACHE	MIT OR Apache-2.0: Apache-2.0; the text from anyhow 1.0.103
souper-ir-2.1.0	anyhow-1.0.103/LICENSE-APACHE	MIT OR Apache-2.0: Apache-2.0; the text from anyhow 1.0.103
wast-35.0.2	wast-258.0.3/LICENSE-Apache-2.0_WITH_LLVM-exception	the text from wast 258.0.3 of the same project (wasm-tools)
ittapi-0.4.0	ittapi-sys-0.4.0/LICENSES/BSD-3-Clause.txt ittapi-sys-0.4.0/LICENSES/GPL-2.0-only.txt	the texts from ittapi-sys 0.4.0 of the same project (intel/ittapi)'

NEW=$WORK/out
rm -rf "${NEW:?}"
mkdir -p "$NEW/crates"

# ---- 1. the archives
: >"$NEW/ARCHIVES"
for a in $ARCHES; do
  name=wasmtime-v$VERSION-$a-c-api
  f=$WORK/$name.tar.xz
  if [ ! -f "$f" ] || [ "$(sha256 "$f")" != "$(archive_sha "$a")" ]; then
    curl -sSfL -o "$f" "https://github.com/bytecodealliance/wasmtime/releases/download/v$VERSION/$name.tar.xz"
  fi
  [ "$(sha256 "$f")" = "$(archive_sha "$a")" ] || fail "SHA-256 mismatch for $name"
  rm -rf "${WORK:?}/x-$a"
  mkdir -p "$WORK/x-$a"
  tar -xf "$f" -C "$WORK/x-$a"
  {
    printf '%s.tar.xz\t%s\n' "$name" "$(archive_sha "$a")"
    tar -tf "$f" | LC_ALL=C sort | sed 's/^/  /'
  } >>"$NEW/ARCHIVES"
  # license lists in the archive besides the LICENSE of wasmtime
  for g in "$WORK/x-$a/$name"/*; do
    [ -f "$g" ] || continue
    b=$(basename "$g")
    [ "$b" != LICENSE ] || continue
    if printf '%s\n' "$b" | grep -Eiq 'licen[cs]e|notice|third'; then
      mkdir -p "$NEW/archive-licenses/$a"
      cp "$g" "$NEW/archive-licenses/$a/"
    fi
  done
done

# ar_members ARCHIVE: ar t, with the long names of a GNU archive (/<offset>,
# which the ar of macOS does not resolve) looked up in its // member
ar_members() {
  ar t "$1" >"$WORK/ar-raw"
  if ! grep -qx '/[0-9][0-9]*' "$WORK/ar-raw"; then
    cat "$WORK/ar-raw"
    return
  fi
  off=8
  table=
  while :; do
    hdr=$(dd if="$1" bs=1 skip="$off" count=60 2>/dev/null | tr -d '\000')
    [ -n "$hdr" ] || break
    name=$(printf '%s' "$hdr" | cut -c1-16 | sed 's/ *$//')
    size=$(printf '%s' "$hdr" | cut -c49-58 | tr -d ' ')
    if [ "$name" = // ]; then
      dd if="$1" bs=4096 iflag=skip_bytes,count_bytes skip=$((off + 60)) count="$size" 2>/dev/null >"$WORK/ar-names" ||
        dd if="$1" bs=1 skip=$((off + 60)) count="$size" 2>/dev/null >"$WORK/ar-names"
      table=1
      break
    fi
    off=$((off + 60 + size + size % 2))
  done
  [ -n "$table" ] || fail "no long name table in $1"
  awk -v names="$WORK/ar-names" '
    BEGIN {
      RS = "\n"; o = 0
      while ((getline line < names) > 0) { n = line; sub(/\/$/, "", n); at[o] = n; o += length(line) + 1 }
    }
    /^\/[0-9]+$/ { k = substr($0, 2) + 0; print (k in at) ? at[k] : $0; next }
    { print }' "$WORK/ar-raw"
}

# ---- 2. the crates of each libwasmtime.a
RUSTCS=
for a in $ARCHES; do
  lib=$WORK/x-$a/wasmtime-v$VERSION-$a-c-api/lib/libwasmtime.a
  # nm of Xcode cannot read the bitcode of some members and exits with 1;
  # the symbols of the other members are enough
  "$NM" "$lib" >"$WORK/nm-$a" 2>/dev/null || true
  grep -q ' _\{1,2\}R' "$WORK/nm-$a" || fail "$NM cannot read $lib"
  strings -a "$lib" >"$WORK/strings-$a"
  ar_members "$lib" >"$WORK/ar-$a"
  sh "$ROOT/scripts/release/rust-crates.sh" "$WORK/nm-$a" "$WORK/strings-$a" >"$WORK/crates-$a"
  RUSTCS="$RUSTCS $(sed -n 's/^rustc	//p' "$WORK/crates-$a")"
done
set -- $RUSTCS
[ $# -eq 3 ] && [ "$1" = "$2" ] && [ "$2" = "$3" ] || fail "the archives were built by different rustc:$RUSTCS"
[ "$1" = "$RUSTC_VERSION" ] || fail "the archives were built by rustc $1, not $RUSTC_VERSION (update RUSTC_VERSION)"

# ---- 3. the source of wasmtime
SRC=$WORK/wasmtime
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin https://github.com/bytecodealliance/wasmtime
fi
TAGGED=$(git ls-remote https://github.com/bytecodealliance/wasmtime "refs/tags/v$VERSION^{}" "refs/tags/v$VERSION" |
  awk '$2 ~ /\^\{\}$/ { peeled = $1; next } { tag = $1 } END { print (peeled != "" ? peeled : tag) }')
[ "$TAGGED" = "$COMMIT" ] || fail "the tag v$VERSION is at $TAGGED, not $COMMIT"
if [ "$(git -C "$SRC" rev-parse -q --verify HEAD 2>/dev/null || true)" != "$COMMIT" ]; then
  git -C "$SRC" fetch -q --depth 1 origin "$COMMIT"
  git -C "$SRC" -c advice.detachedHead=false checkout -q "$COMMIT"
fi
[ "$(git -C "$SRC" rev-parse HEAD)" = "$COMMIT" ] || fail "the source is not at $COMMIT"

# ---- 4. the dependencies of wasmtime-c-api
# package id<TAB>name<TAB>version<TAB>library<TAB>license<TAB>links<TAB>directory<TAB>source
: >"$WORK/packages"
for a in $ARCHES; do
  # the release archives are built by CMake with the features of
  # WASMTIME_FEATURE_LIST on (logging pulls in env_logger and regex), so
  # every feature is on here; a crate too many does no harm
  (cd "$SRC/crates/c-api" && cargo metadata --locked --all-features --format-version 1 --filter-platform "$(triple "$a")") >"$WORK/metadata-$a.json"
  jq -r '
    (.packages | map({key: .id, value: .}) | from_entries) as $pkgs
    | (.resolve.nodes | map({key: .id, value: .}) | from_entries) as $nodes
    | [.packages[] | select(.name == "wasmtime-c-api") | .id] as $root
    | def step: . + [.[] | $nodes[.].deps[]? | select(any(.dep_kinds[]; .kind == null)) | .pkg] | unique;
      def fix(f): (f) as $n | if $n == . then . else ($n | fix(f)) end;
      $root | fix(step) | .[] | $pkgs[.]
    | [.id, .name, .version,
       ([.targets[] | select(any(.kind[]; . == "lib" or . == "rlib" or . == "staticlib" or . == "proc-macro")) | .name] | first // (.name | gsub("-"; "_"))),
       (.license // "-"), (.links // "-"), (.manifest_path | sub("/Cargo.toml$"; "")), (.source // "path")]
    | @tsv' "$WORK/metadata-$a.json" >>"$WORK/packages"
done
LC_ALL=C sort -u "$WORK/packages" -o "$WORK/packages"
(cd "$SRC" && cargo fetch --locked >/dev/null)

# ---- 5. the license files of the crates
# copy_licenses DIR DEST: the license files at the top of DIR, and the
# directory LICENSES/ of the REUSE convention
copy_licenses() {
  found=
  for f in "$1"/*; do
    [ -f "$f" ] || continue
    if basename "$f" | grep -Eiq "$LICENSE_RE"; then
      mkdir -p "$2"
      cp "$f" "$2/"
      found=1
    fi
  done
  if [ -d "$1/LICENSES" ] && [ -n "$(ls "$1/LICENSES")" ]; then
    mkdir -p "$2"
    cp -R "$1/LICENSES" "$2/LICENSES"
    found=1
  fi
  [ -n "$found" ]
}
# write_manifest PACKAGES OUTDIR: MANIFEST.tsv and crates/ of OUTDIR
write_manifest() {
  printf 'package\tversion\tlibrary\tlicense\tfiles\n' >"$2/MANIFEST.tsv"
  missing=
  while IFS='	' read -r id name ver lib license links dir source; do
    dest=$2/crates/$name-$ver
    rm -rf "${dest:?}"
    if ! copy_licenses "$dir" "$dest"; then
      # a crate of the wasmtime workspace without its own license file is
      # under the license of the repository
      case "$dir" in
        "$SRC"/*) copy_licenses "$SRC" "$dest" || true ;;
      esac
    fi
    if [ ! -d "$dest" ]; then
      row=$(printf '%s\n' "$NOFILE_TABLE" | awk -F '\t' -v n="$name-$ver" '$1 == n')
      if [ -n "$row" ]; then
        registry=$(dirname "$dir")
        mkdir -p "$dest"
        for f in $(printf '%s\n' "$row" | cut -f2); do
          [ -f "$registry/$f" ] || fail "no $f for $name-$ver (NOFILE_TABLE)"
          cp "$registry/$f" "$dest/"
        done
        printf '%s %s is published without a license file. Its license is %s.\n%s\n' \
          "$name" "$ver" "$license" "$(printf '%s\n' "$row" | cut -f3)" >"$dest/NOTE"
      fi
    fi
    if [ "$links" != - ]; then
      extra=$(printf '%s\n' "$LINKS_TABLE" | awk -F '\t' -v n="$name" '$1 == n { print $2 }')
      if [ -n "$extra" ]; then
        for f in $extra; do
          [ -f "$dir/$f" ] || fail "no $f in $name-$ver (links = $links)"
          mkdir -p "$dest/$(dirname "$f")"
          cp "$dir/$f" "$dest/$f"
        done
      elif ! printf ' %s \n' "$LINKS_TOP" | grep -q " $name "; then
        fail "$name-$ver has links = $links and bundles C sources; add its license files to LINKS_TABLE or LINKS_TOP"
      fi
    fi
    if [ ! -d "$dest" ]; then
      missing="$missing $name-$ver"
      continue
    fi
    files=$(cd "$dest" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$ver" "$lib" "$license" "$files" >>"$2/MANIFEST.tsv"
  done <"$1"
  [ -z "$missing" ] || fail "no license file for:$missing"
}
write_manifest "$WORK/packages" "$NEW"

# ---- 6. the Rust standard library and compiler-rt
if [ "${SKIP_RUST:-}" != 1 ]; then
  command -v rustup >/dev/null 2>&1 || fail "rustup is needed"
  rustup toolchain install "$RUSTC_VERSION" --profile minimal --component rust-src >/dev/null
  SYSROOT=$(rustc "+$RUSTC_VERSION" --print sysroot)
  mkdir -p "$NEW/rust"
  echo "$RUSTC_VERSION" >"$NEW/rust/VERSION"
  docs=$SYSROOT/share/doc/rust
  found=
  for f in "$docs"/COPYRIGHT* "$docs"/LICENSE*; do
    [ -f "$f" ] || continue
    cp "$f" "$NEW/rust/"
    found=1
  done
  if [ -d "$docs/licenses" ]; then
    cp -R "$docs/licenses" "$NEW/rust/licenses"
    found=1
  fi
  [ -n "$found" ] || fail "no license file in $docs"
  LIBRARY=$SYSROOT/lib/rustlib/src/rust/library
  [ -f "$LIBRARY/Cargo.lock" ] || fail "no $LIBRARY/Cargo.lock (rust-src)"
  : >"$WORK/std-packages"
  for a in $ARCHES; do
    cargo "+$RUSTC_VERSION" metadata --locked --format-version 1 --manifest-path "$LIBRARY/Cargo.toml" \
      --filter-platform "$(triple "$a")" >"$WORK/std-metadata-$a.json"
    jq -r '
      (.packages | map({key: .id, value: .}) | from_entries) as $pkgs
      | (.resolve.nodes | map({key: .id, value: .}) | from_entries) as $nodes
      | [.packages[] | select(.name == "std") | .id] as $root
      | def step: . + [.[] | $nodes[.].deps[]? | select(any(.dep_kinds[]; .kind == null)) | .pkg] | unique;
        def fix(f): (f) as $n | if $n == . then . else ($n | fix(f)) end;
        $root | fix(step) | .[] | $pkgs[.]
      | [.id, .name, .version,
         ([.targets[] | select(any(.kind[]; . == "lib" or . == "rlib")) | .name] | first // (.name | gsub("-"; "_"))),
         (.license // "-"), (.links // "-"), (.manifest_path | sub("/Cargo.toml$"; "")), (.source // "path")]
      | @tsv' "$WORK/std-metadata-$a.json" >>"$WORK/std-packages"
  done
  LC_ALL=C sort -u "$WORK/std-packages" -o "$WORK/std-packages"
  # the crates of the library workspace are the standard library
  awk -F '\t' '$8 == "path" { print $4 }' "$WORK/std-packages" | LC_ALL=C sort -u >"$NEW/rust/STD_CRATES"
  awk -F '\t' '$8 != "path"' "$WORK/std-packages" >"$WORK/std-registry"
  mkdir -p "$NEW/rust/crates"
  write_manifest "$WORK/std-registry" "$NEW/rust"
  LLVM=$(rustc "+$RUSTC_VERSION" -vV | sed -n 's/^LLVM version: //p')
  [ -n "$LLVM" ] || fail "the version of LLVM of rustc $RUSTC_VERSION is not found"
  curl -sSfL -o "$WORK/compiler-rt-LICENSE.TXT" "https://raw.githubusercontent.com/llvm/llvm-project/llvmorg-$LLVM/compiler-rt/LICENSE.TXT"
  ACTUAL=$(sha256 "$WORK/compiler-rt-LICENSE.TXT")
  [ -n "$COMPILER_RT_LICENSE_SHA256" ] || fail "record COMPILER_RT_LICENSE_SHA256=$ACTUAL (llvmorg-$LLVM) in this script after reading the file"
  [ "$ACTUAL" = "$COMPILER_RT_LICENSE_SHA256" ] || fail "SHA-256 mismatch for compiler-rt/LICENSE.TXT of llvmorg-$LLVM: $ACTUAL"
  mkdir -p "$NEW/rust/compiler-rt"
  cp "$WORK/compiler-rt-LICENSE.TXT" "$NEW/rust/compiler-rt/LICENSE.TXT"
  echo "llvmorg-$LLVM" >"$NEW/rust/compiler-rt/VERSION"
fi

# ---- 7. every crate of libwasmtime.a is in 4 or 6
{
  for m in "$NEW/MANIFEST.tsv" "$NEW/rust/MANIFEST.tsv"; do
    [ -f "$m" ] || continue
    awk -F '\t' 'NR > 1 { p = $1; gsub(/-/, "_", p); print p "\t" $2; print $3 "\t" $2 }' "$m"
  done
  if [ -f "$NEW/rust/STD_CRATES" ]; then sed 's/$/	*/' "$NEW/rust/STD_CRATES"; fi
} >"$WORK/known"
: >"$WORK/unknown"
for a in $ARCHES; do
  awk -F '\t' -v a="$a" '
    FNR == NR { if ($2 == "*") any[$1] = 1; else { pair[$1 "\t" $2] = 1; name[$1] = 1 } next }
    $1 != "crate" { next }
    $2 in any { next }
    $3 == "-" && ($2 in name) { next }
    ($2 "\t" $3) in pair { next }
    { print a ": " $2 ($3 == "-" ? "" : " " $3) }' "$WORK/known" "$WORK/crates-$a" >>"$WORK/unknown"
done
if [ -s "$WORK/unknown" ]; then
  echo "wasmtime-licenses: crates of libwasmtime.a not in the dependencies:" >&2
  sed 's/^/  /' "$WORK/unknown" >&2
  [ "${SKIP_RUST:-}" = 1 ] || exit 1
  echo "wasmtime-licenses: SKIP_RUST=1; the standard library is not checked" >&2
fi

# ---- 8. the C and assembly members
printf 'platform\tmember\tcomponent\n' >"$NEW/c-objects.tsv"
for a in $ARCHES; do
  grep -v -e '\.rcgu\.o$' -e '^__\.SYMDEF' -e '^/' "$WORK/ar-$a" | grep '\.o$' |
    sed 's/^[0-9a-f]\{16\}-//' | LC_ALL=C sort -u |
    awk -F '\t' -v a="$a" -v old="$OUT/c-objects.tsv" '
      BEGIN { while ((getline line < old) > 0) { split(line, f, "\t"); comp[f[1] "\t" f[2]] = f[3] } }
      { print a "\t" $0 "\t" comp[a "\t" $0] }' >>"$NEW/c-objects.tsv"
done
EMPTY=$(awk -F '\t' 'NR > 1 && $3 == ""' "$NEW/c-objects.tsv" | wc -l | tr -d ' ')

# ---- README
CRATES=$(($(wc -l <"$NEW/MANIFEST.tsv") - 1))
{
  echo "The license documents of the Rust crates, the Rust standard library and"
  echo "compiler-rt in libwasmtime.a of the wasmtime $VERSION C API"
  echo "(docs/adr/0007-third-party-licenses.md). Generated; do not edit, except"
  echo "the component column of c-objects.tsv."
  echo
  echo "generated: $(date -u +%Y-%m-%d)"
  echo "command: scripts/wasmtime-licenses.sh${SKIP_RUST:+ (SKIP_RUST=$SKIP_RUST)}"
  echo "wasmtime: v$VERSION, commit $COMMIT"
  echo "rustc: $RUSTC_VERSION"
  echo "cargo: $(cargo --version)"
  echo
  echo "crates in MANIFEST.tsv: $CRATES"
  for a in $ARCHES; do
    echo "crates found in libwasmtime.a of $a: $(grep -c '^crate' "$WORK/crates-$a")"
  done
  if [ -s "$WORK/unknown" ]; then
    echo "not found in the dependencies (step 7):"
    sed 's/^/  /' "$WORK/unknown"
  else
    echo "step 7: every crate found in the three archives is listed"
  fi
  echo "members of c-objects.tsv without a component: $EMPTY"
} >"$NEW/README"

rm -rf "${OUT:?}"
mkdir -p "$(dirname "$OUT")"
cp -R "$NEW" "$OUT"
echo "wrote $OUT"
[ "$EMPTY" -eq 0 ] || echo "wasmtime-licenses: fill in the component of $EMPTY members of c-objects.tsv" >&2
