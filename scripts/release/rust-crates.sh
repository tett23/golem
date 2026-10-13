#!/bin/sh
# Lists the Rust crates in libwasmtime.a and the rustc that built it
# (docs/adr/0007-third-party-licenses.md).
#
#   rust-crates.sh NM_OUTPUT STRINGS_OUTPUT
#
# NM_OUTPUT is the output of nm, STRINGS_OUTPUT of strings -a, both of
# libwasmtime.a. The crates come from two places:
#   - the roots of the v0 mangled symbols (_R or __R): Cs<id>_<length><name>
#   - the paths of the panic locations: index.crates.io-<hash>/<name>-<version>/,
#     the - in the name replaced with _
# Output, sorted, one line each:
#   crate<TAB><library name><TAB><version, or - when only a symbol has it>
#   rustc<TAB><version>
set -eu
[ $# -eq 2 ] || {
  echo "usage: rust-crates.sh NM_OUTPUT STRINGS_OUTPUT" >&2
  exit 2
}
for f in "$1" "$2"; do
  [ -f "$f" ] || {
    printf 'rust-crates: no such file: %s\n' "$f" >&2
    exit 1
  }
done
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

# the crate roots of the symbols
awk '
  {
    s = $NF
    if (s !~ /^_?_R/) next
    while (match(s, /Cs[0-9A-Za-z]*_[0-9]+/)) {
      m = substr(s, RSTART, RLENGTH)
      sub(/^Cs[0-9A-Za-z]*_/, "", m)
      len = m + 0
      rest = substr(s, RSTART + RLENGTH)
      name = substr(rest, 1, len)
      if (length(name) == len && name !~ /^_/) print name "\t-"
      s = substr(rest, len + 1)
    }
  }' "$1" >"$TMP/crates"

# the paths of the panic locations
grep -oE 'index\.crates\.io-[0-9a-f]+/[^/[:space:]]+' "$2" |
  sed -n 's|^[^/]*/||; s/^\([A-Za-z0-9_-]*\)-\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[0-9A-Za-z.+-]*\)$/\1	\2/p' |
  awk -F '\t' '{ gsub(/-/, "_", $1); print $1 "\t" $2 }' >>"$TMP/crates" || true

# a name with a version drops the - of the same name
awk -F '\t' '
  { rows[NR] = $0; if ($2 != "-") versioned[$1] = 1; name[NR] = $1; ver[NR] = $2 }
  END { for (i = 1; i <= NR; i++) if (ver[i] != "-" || !(name[i] in versioned)) print "crate\t" rows[i] }' "$TMP/crates" |
  LC_ALL=C sort -u

sed -n 's/.*rustc version \([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*[0-9A-Za-z.-]*\).*/rustc	\1/p' "$2" | LC_ALL=C sort -u
