#!/bin/sh
# Writes licenses/plugins/: the copyright notices and license documents of
# what the sample plugins plugins/wasm/<name>.wasm hold, the crates.io crates
# they depend on and the Rust standard library
# (docs/adr/0133-third-party-licenses-of-sample-plugins.md). Run it when
# plugins/Cargo.lock or plugins/rust-toolchain.toml changes, and commit the
# output with them; the plugins job of ci.yml runs it with --check.
#
#   scripts/plugin-licenses.sh           rewrite licenses/plugins/
#   scripts/plugin-licenses.sh --check   fail when what it writes differs
#                                        from licenses/plugins/
#
# Needs a POSIX shell, awk, diff, strings, cargo and rustc (the toolchain of
# plugins/rust-toolchain.toml), and curl for a crate of UPSTREAM whose
# document is not in licenses/plugins/ yet. --check never uses curl.
#
# Environment (the tests give small inputs through these):
#   CARGO_HOME                 the registry of the crates (default ~/.cargo)
#   PLUGIN_LICENSES_TREE       a file with the output of the cargo tree of step 1
#   PLUGIN_LICENSES_RUST_DOC   the share/doc/rust/ of the toolchain
#   PLUGIN_LICENSES_RUSTC_VV   a file with the output of rustc -vV
#   PLUGIN_LICENSES_WASM       the directory of the wasm (default plugins/wasm)
#   curl is looked up in PATH.
#
# Steps (the numbers of the ADR):
#   1. the crates.io crates of each plugin, from cargo tree
#   2. the license files of each crate, from the registry
#   3. the crates without one: the document of UPSTREAM, by its SHA-256
#   4. the documents of the standard library, from the toolchain
#   5. the strings of each wasm agree with 1 and 4
#   6. MANIFEST.tsv and README
set -eu
CHECK=false
case ${1:-} in
  --check) CHECK=true ;;
  "") ;;
  *) echo "usage: plugin-licenses.sh [--check]" >&2; exit 2 ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PLUGINS=$ROOT/plugins
OUT=$ROOT/licenses/plugins
CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}
WASM=${PLUGIN_LICENSES_WASM:-$PLUGINS/wasm}
LICENSE_RE='^(LICEN[CS]E|COPYING|COPYRIGHT|NOTICE|UNLICENSE)([._-][^/]*)?$'
# crates published without a license file:
# <name>-<version> <repository> <commit> <path> <SHA-256>
UPSTREAM='lindera-6.2.0 lindera/lindera 0482efcc46b5ec518b7238efae55e9fed9bba0c0 LICENSE d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4
lindera-dictionary-6.2.0 lindera/lindera 0482efcc46b5ec518b7238efae55e9fed9bba0c0 LICENSE d37249886de3136db31717f15f6ade215a36fbed1c782381e38b2bf6047e8ec4'

fail() {
  printf 'plugin-licenses: %s\n' "$*" >&2
  exit 1
}
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }

WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
NEW=$WORK/out
mkdir -p "$NEW/crates" "$NEW/rust"

# ---- 1. the crates of each plugin: lines "<plugin> <name> <version> <license>"
if [ -n "${PLUGIN_LICENSES_TREE:-}" ]; then
  cp "$PLUGIN_LICENSES_TREE" "$WORK/tree"
else
  # --no-dedupe: a crate shown before is otherwise written without its
  # dependencies, also under another plugin
  (cd "$PLUGINS" && cargo tree --offline --locked --workspace --no-dedupe -e normal,build \
    --target wasm32-unknown-unknown --prefix depth --format '{p}|{l}') >"$WORK/tree"
fi
# the plugins: the packages of the workspace whose Cargo.toml has cdylib
# (plugins/build.sh)
awk '/^0/ { sub(/^0/, ""); print $1 }' "$WORK/tree" | LC_ALL=C sort -u >"$WORK/roots"
: >"$WORK/plugin-list"
while read -r p; do
  if grep -q cdylib "$PLUGINS/$p/Cargo.toml" 2>/dev/null; then echo "$p" >>"$WORK/plugin-list"; fi
done <"$WORK/roots"
[ -s "$WORK/plugin-list" ] || fail "no plugin in the output of cargo tree"
awk -v plugins="$WORK/plugin-list" '
  BEGIN { while ((getline p < plugins) > 0) is[p] = 1 }
  /^[0-9]/ {
    match($0, /^[0-9]+/)
    depth = substr($0, 1, RLENGTH) + 0
    line = substr($0, RLENGTH + 1)
    bar = index(line, "|")
    if (bar == 0) { print "a line without |: " $0 > "/dev/stderr"; bad = 1; next }
    pkg = substr(line, 1, bar - 1)
    lic = substr(line, bar + 1)
    sub(/ \(\*\)$/, "", lic)
    sub(/ \(\*\)$/, "", pkg)
    sub(/ \(proc-macro\)/, "", pkg)
    if (depth == 0) { split(pkg, w, " "); cur = (w[1] in is) ? w[1] : ""; next }
    if (cur == "") next
    if (pkg ~ / \(\//) next                      # a crate of the repository
    if (pkg ~ /\(/) { print "a crate not from crates.io: " pkg > "/dev/stderr"; bad = 1; next }
    split(pkg, w, " ")
    ver = w[2]; sub(/^v/, "", ver)
    printf "%s\t%s\t%s\t%s\n", cur, w[1], ver, lic
  }
  END { exit bad }
' "$WORK/tree" | LC_ALL=C sort -u >"$WORK/deps" || fail "cannot read the output of cargo tree"

# ---- 2. and 3. the license files of each crate
registry() {
  for d in "$CARGO_HOME"/registry/src/index.crates.io-*/"$1"; do
    if [ -d "$d" ]; then
      echo "$d"
      return 0
    fi
  done
  return 1
}
upstream() {
  printf '%s\n' "$UPSTREAM" | awk -v c="$1" '$1 == c'
}
cut -f2,3 "$WORK/deps" | LC_ALL=C sort -u | tr '\t' '-' >"$WORK/crates"
missing=
while read -r c; do
  src=$(registry "$c") || fail "$c is not in $CARGO_HOME/registry/src; build the plugins first (plugins/build.sh)"
  dst=$NEW/crates/$c
  mkdir -p "$dst"
  for f in "$src"/*; do
    [ -e "$f" ] || continue
    b=$(basename "$f")
    if [ -f "$f" ] && printf '%s\n' "$b" | grep -Eiq "$LICENSE_RE"; then cp "$f" "$dst/$b"; fi
  done
  # REUSE
  if [ -d "$src/LICENSES" ]; then cp -R "$src/LICENSES" "$dst/LICENSES"; fi
  [ -z "$(ls -A "$dst")" ] || continue
  row=$(upstream "$c")
  if [ -z "$row" ]; then
    missing="$missing $c"
    continue
  fi
  set -- $row
  repo=$2 commit=$3 path=$4 sum=$5
  vcs=$(sed -n 's/.*"sha1": *"\([0-9a-f]*\)".*/\1/p' "$src/.cargo_vcs_info.json" 2>/dev/null || true)
  [ "$vcs" = "$commit" ] || fail "$c: .cargo_vcs_info.json names the commit '$vcs', not $commit of UPSTREAM"
  url=https://raw.githubusercontent.com/$repo/$commit/$path
  name=$(basename "$path")
  if [ -f "$OUT/crates/$c/$name" ] && [ "$(sha256 "$OUT/crates/$c/$name")" = "$sum" ]; then
    cp "$OUT/crates/$c/$name" "$dst/$name"
  elif $CHECK; then
    fail "$c: licenses/plugins/crates/$c/$name is not the document of SHA-256 $sum; run scripts/plugin-licenses.sh"
  else
    curl -sSfL -o "$dst/$name" "$url" || fail "$c: cannot fetch $url"
    [ "$(sha256 "$dst/$name")" = "$sum" ] || fail "$c: SHA-256 mismatch for $url"
  fi
  printf 'The crate is published without a license file; %s is the one of its\nrepository at the commit of the crate (.cargo_vcs_info.json).\n\nsource: %s\nSHA-256: %s\n' \
    "$name" "$url" "$sum" >"$dst/NOTE"
done <"$WORK/crates"
if [ -n "$missing" ]; then
  for c in $missing; do printf 'plugin-licenses: %s has no license file and is not in UPSTREAM\n' "$c" >&2; done
  exit 1
fi

# ---- 4. the standard library
if [ -n "${PLUGIN_LICENSES_RUSTC_VV:-}" ]; then
  cp "$PLUGIN_LICENSES_RUSTC_VV" "$WORK/rustc-vV"
else
  (cd "$PLUGINS" && rustc -vV) >"$WORK/rustc-vV"
fi
DOC=${PLUGIN_LICENSES_RUST_DOC:-$(cd "$PLUGINS" && rustc --print sysroot)/share/doc/rust}
release=$(sed -n 's/^release: //p' "$WORK/rustc-vV")
hash=$(sed -n 's/^commit-hash: //p' "$WORK/rustc-vV")
[ -n "$release" ] && [ -n "$hash" ] || fail "no release or commit-hash in rustc -vV"
[ -f "$DOC/COPYRIGHT-library.html" ] && [ -d "$DOC/licenses" ] || fail "$DOC has no COPYRIGHT-library.html or licenses/"
cp "$DOC/COPYRIGHT-library.html" "$NEW/rust/COPYRIGHT-library.html"
cp -R "$DOC/licenses" "$NEW/rust/licenses"
printf 'release: %s\ncommit-hash: %s\n' "$release" "$hash" >"$NEW/rust/VERSION"

# ---- 5. the strings of the wasm
# a "<name>-<version>" to "<name> <version>"
split_version() { sed 's/-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9]\)/ \1/'; }
bad=false
while read -r p; do
  w=$WASM/$p.wasm
  [ -f "$w" ] || fail "no $w"
  strings -a "$w" >"$WORK/strings"
  for h in $(grep -o '/rustc/[0-9a-f]*/' "$WORK/strings" | sed 's,^/rustc/,,; s,/$,,' | LC_ALL=C sort -u); do
    if [ "$h" != "$hash" ]; then
      printf 'plugin-licenses: %s.wasm is built by the rustc %s, not %s; rebuild the plugins or rerun with the toolchain of plugins/rust-toolchain.toml\n' "$p" "$h" "$hash" >&2
      bad=true
    fi
  done
  for c in $(grep -o '/rust/deps/[A-Za-z0-9_.-]*' "$WORK/strings" | sed 's,^/rust/deps/,,' | LC_ALL=C sort -u); do
    if ! grep -o '📦 [A-Za-z0-9_.+-]*' "$NEW/rust/COPYRIGHT-library.html" | grep -qxF "📦 $c"; then
      printf 'plugin-licenses: %s.wasm has %s of the standard library, not in COPYRIGHT-library.html\n' "$p" "$c" >&2
      bad=true
    fi
  done
  for c in $(grep -o 'index\.crates\.io-[0-9a-f]*/[A-Za-z0-9_.-]*' "$WORK/strings" | sed 's,^[^/]*/,,' | LC_ALL=C sort -u); do
    nv=$(printf '%s\n' "$c" | split_version)
    if ! awk -F'\t' -v p="$p" -v nv="$nv" '$1 == p && ($2 " " $3) == nv { found = 1 } END { exit !found }' "$WORK/deps"; then
      printf 'plugin-licenses: %s.wasm has %s, which is not a dependency of %s in cargo tree\n' "$p" "$c" "$p" >&2
      bad=true
    fi
  done
done <"$WORK/plugin-list"
if $bad; then exit 1; fi

# ---- 6. MANIFEST.tsv and README
{
  printf 'plugin\tpackage\tversion\tlicense\tfiles\n'
  while IFS='	' read -r p n v l; do
    files=$(cd "$NEW/crates/$n-$v" && find . -type f ! -name NOTE | sed 's,^\./,,' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
    printf '%s\t%s\t%s\t%s\t%s\n' "$p" "$n" "$v" "$l" "$files"
  done <"$WORK/deps"
} >"$NEW/MANIFEST.tsv"
{
  cat <<EOF
The copyright notices and license documents of what the sample plugins
plugins/wasm/<name>.wasm hold: the crates.io crates each plugin depends on,
with its build and procedural-macro dependencies, and the Rust standard
library (docs/adr/0133-third-party-licenses-of-sample-plugins.md).
Generated; do not edit.

command: scripts/plugin-licenses.sh
rustc: $release, commit $hash

MANIFEST.tsv   the plugin, the crate, its version, its license expression
               and its files under crates/<name>-<version>/, a line for
               each plugin and crate
crates/        the license files of each crate; NOTE tells where a document
               comes from when the crate is published without one
rust/          COPYRIGHT-library.html and licenses/ of the toolchain: the
               standard library and the crates.io crates it includes

The crates.io crates of each plugin:

EOF
  while read -r p; do
    list=$(awk -F'\t' -v p="$p" '$1 == p { printf "%s%s %s", (n++ ? ", " : ""), $2, $3 }' "$WORK/deps")
    if [ -z "$list" ]; then
      printf '%s: the Rust standard library only\n' "$p"
    else
      printf '%s: %s\n' "$p" "$list"
    fi
  done <"$WORK/plugin-list"
} >"$NEW/README"

if $CHECK; then
  if [ -d "$OUT" ] && diff -r "$NEW" "$OUT" >/dev/null 2>&1; then exit 0; fi
  echo "plugin-licenses: licenses/plugins/ is not what the sources give; run scripts/plugin-licenses.sh and commit it:" >&2
  if [ -d "$OUT" ]; then
    diff -rq "$NEW" "$OUT" 2>&1 | sed "s|$NEW|(regenerated)|g; s|$ROOT/||g" >&2 || true
  else
    echo "no licenses/plugins/" >&2
  fi
  exit 1
fi
rm -rf "${OUT:?}"
mkdir -p "$(dirname "$OUT")"
cp -R "$NEW" "$OUT"
