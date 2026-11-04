#!/bin/sh
# Checks the pinned version of wasmtime against the security advisories of
# bytecodealliance/wasmtime (docs/adr/0157, docs/adr/0166).
#
#   wasmtime-advisories.sh [ADVISORIES_JSON]
#
# ADVISORIES_JSON is the answer of the API (a JSON array of advisories);
# without it, gh fetches the published advisories of the repository. The
# pinned version V is the one of fetch-wasmtime.sh --expected (or
# WASMTIME_VERSION), and the version of each package is read from
# licenses/wasmtime-vV/MANIFEST.tsv (or the file WASMTIME_MANIFEST).
#
# For each element of vulnerabilities of an advisory:
#
# - the ecosystem is rust or crates.io, and the package is in the manifest;
#   anything else is an error.
# - the range (vulnerable_version_range) loses a trailing
#   "(excluding A, B ...)", whose versions never match. The rest is split
#   at ",", "&&" and the word "and" into items >=V, >V, <=V, <V, =V or V
#   (V is <number>.<number>.<number>; blanks around an item and after its
#   operator are dropped, empty items too). The items are sorted by
#   version (a version twice is an error) and read in that order: a lower
#   bound opens an interval, an upper bound closes the open one (or, before
#   any interval, makes one with no lower bound), a version alone is an
#   interval of itself; an interval left open has no upper bound. Anything
#   else is an error.
# - a version of the package in no interval does not match. In an interval
#   with an upper bound, it matches. In an interval [L, inf), it does not
#   match when patched_versions (split at "," and "and"; an item is V or
#   ">= V") has a version P with L <= P <= the version, and P is in the same
#   series as the version (the major, or 0.minor) or is the greatest of
#   them; then it writes "note: GHSA<TAB>package<TAB>version<TAB>range<TAB>
#   patched" to the standard error.
#
# It writes one line "GHSA<TAB>severity<TAB>package<TAB>range<TAB>summary"
# for each advisory that matches, and exits 0 when none matches and there
# is no error, 1 when one matches, and 2 on an error.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
die() { echo "wasmtime-advisories: $*" >&2; exit 2; }
[ $# -le 1 ] || { echo "usage: wasmtime-advisories.sh [ADVISORIES_JSON]" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || die "jq is needed"

if [ -n "${WASMTIME_VERSION:-}" ]; then
  V=$WASMTIME_VERSION
else
  V=$(sh "$HERE/fetch-wasmtime.sh" --expected | sed -n 's/^wasmtime-v\([0-9][0-9.]*\)-.*/\1/p') ||
    die "fetch-wasmtime.sh --expected failed"
fi
printf '%s\n' "$V" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || die "not a version of wasmtime: '$V'"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ $# -eq 1 ]; then
  [ -f "$1" ] || die "no such file: $1"
  JSON=$1
else
  JSON=$TMP/advisories.json
  gh api --paginate '/repos/bytecodealliance/wasmtime/security-advisories?per_page=100&state=published' |
    jq -s 'add' >"$JSON" || die "cannot fetch the advisories"
fi
# one line for each element of vulnerabilities:
# GHSA, severity, ecosystem, package, range, patched versions, summary
jq -r '.[] | . as $a | .vulnerabilities[] |
  [$a.ghsa_id, ($a.severity // ""), (.package.ecosystem // ""), (.package.name // ""),
   (.vulnerable_version_range // ""), (.patched_versions // ""), ($a.summary // "")] | @tsv' \
  "$JSON" >"$TMP/vulns" || die "not a list of advisories: $JSON"

LC_ALL=C awk -F '\t' -v pin="$V" -v errfile="$TMP/errors" '
function err(m) { print "wasmtime-advisories: " m >>errfile; errors++ }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
function key(s,   p) {
  if (s !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) return ""
  split(s, p, ".")
  return sprintf("%09d.%09d.%09d", p[1], p[2], p[3])
}
# ADR 0157: the items in the written order
function range(r,   n, it, i, op, ver, k, m, open) {
  delete lo; delete loin; delete hi; delete hiin
  n = split(r, it, ",")
  m = 0; open = 0
  for (i = 1; i <= n; i++) {
    it[i] = trim(it[i]); op = ""
    if (match(it[i], /^(>=|<=|>|<|=)/)) { op = substr(it[i], 1, RLENGTH); ver = trim(substr(it[i], RLENGTH + 1)) } else ver = it[i]
    if ((k = key(ver)) == "") { why = "an item that is not a comparison with a version: " it[i]; return -1 }
    if (op == ">=" || op == ">") {
      if (open) { why = "a lower bound in an open interval"; return -1 }
      m++; lo[m] = k; loin[m] = (op == ">="); hi[m] = ""; open = 1
    } else if (op == "<=" || op == "<") {
      if (!open) { m++; lo[m] = ""; loin[m] = 0 }
      hi[m] = k; hiin[m] = (op == "<="); open = 0
    } else { m++; lo[m] = k; loin[m] = 1; hi[m] = k; hiin[m] = 1 }
  }
  return m
}
function inside(k, i) {
  if (lo[i] != "" && (loin[i] ? k < lo[i] : k <= lo[i])) return 0
  if (hi[i] != "" && (hiin[i] ? k > hi[i] : k >= hi[i])) return 0
  return 1
}
{
  g = $1; pkg = $4; r = $5
  if (pkg != "wasmtime" && pkg !~ /^wasmtime-/) { err(g ": cannot check the package " pkg); next }
  n = range(r)
  if (n < 0) { err(g ": cannot read the range \"" r "\" of " pkg ": " why); next }
  k = key(pin)
  for (i = 1; i <= n && !inside(k, i); i++) ;
  if (i <= n) hit(g)
}
function hit(g) {
  if (g in hits) return
  hits[g] = 1; nh++
  printf "%s\t%s\t%s\t%s\t%s\n", $1, $2, $4, $5, $7
}
END {
  if (errors) exit 2
  exit nh ? 1 : 0
}' "$TMP/vulns" || code=$?
cat "$TMP/notes" "$TMP/errors" >&2 2>/dev/null || true
exit "${code:-0}"
