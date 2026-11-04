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
MANIFEST=${WASMTIME_MANIFEST:-$ROOT/licenses/wasmtime-v$V/MANIFEST.tsv}
[ -f "$MANIFEST" ] || die "no list of the crates of wasmtime $V: $MANIFEST"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
if [ $# -eq 1 ]; then
  [ -f "$1" ] || die "no such file: $1"
  JSON=$1
else
  JSON=$TMP/advisories.json
  gh api --paginate '/repos/bytecodealliance/wasmtime/security-advisories?per_page=100&state=published' \
    >"$TMP/pages" || die "cannot fetch the advisories"
  # one array for each page
  jq -s 'add // []' "$TMP/pages" >"$JSON" || die "not the advisories: the answer of gh api"
fi
# one line for each element of vulnerabilities:
# GHSA, severity, ecosystem, package, range, patched versions, summary
jq -r '.[] | . as $a | .vulnerabilities[] |
  [$a.ghsa_id, ($a.severity // ""), (.package.ecosystem // ""), (.package.name // ""),
   (.vulnerable_version_range // ""), (.patched_versions // ""), ($a.summary // "")] | @tsv' \
  "$JSON" >"$TMP/vulns" || die "not a list of advisories: $JSON"

LC_ALL=C awk -F '\t' -v manifest="$MANIFEST" -v errfile="$TMP/errors" -v notefile="$TMP/notes" '
function err(m) { print "wasmtime-advisories: " m >>errfile; errors++ }
function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
# the key of a version that sorts as the version, or "" if it is not one
function key(s,   p) {
  if (s !~ /^[0-9]+\.[0-9]+\.[0-9]+$/) return ""
  split(s, p, ".")
  return sprintf("%09d.%09d.%09d", p[1], p[2], p[3])
}
function series(k) { return substr(k, 1, 9) + 0 >= 1 ? substr(k, 1, 9) : substr(k, 1, 19) }
# split s at ",", "&&" and the word "and" into it[1..n] (no empty item)
function items(s, it,   a, n, i, m) {
  gsub(/&&/, ",", s)
  s = " " s " "
  gsub(/[ \t]and[ \t]/, " , ", s)
  n = split(s, a, ",")
  m = 0
  for (i = 1; i <= n; i++) { a[i] = trim(a[i]); if (a[i] != "") it[++m] = a[i] }
  return m
}
# reads the range r into the intervals lo[], loin[], hi[], hiin[] (keys;
# "" for no bound) and the excluded keys ex[]; returns the number of
# intervals, or -1 with the reason in why
function range(r,   s, t, n, it, i, j, op, ver, k, ops, keys, tk, to, m, open, nx, xa) {
  delete lo; delete loin; delete hi; delete hiin; delete ex
  s = r
  if (match(s, /\(excluding [^()]*\)[ \t]*$/)) {
    t = substr(s, RSTART + 11, RLENGTH - 11)
    sub(/\)[ \t]*$/, "", t)
    s = substr(s, 1, RSTART - 1)
    nx = items(t, xa)
    for (i = 1; i <= nx; i++) {
      if ((k = key(xa[i])) == "") { why = "an excluded version that is not one: " xa[i]; return -1 }
      ex[k] = 1
    }
  }
  if (s ~ /[()]/) { why = "parentheses that are not a trailing (excluding ...)"; return -1 }
  n = items(s, it)
  if (n == 0) { why = "no version"; return -1 }
  for (i = 1; i <= n; i++) {
    op = ""
    if (match(it[i], /^(>=|<=|>|<|=)/)) { op = substr(it[i], 1, RLENGTH); ver = trim(substr(it[i], RLENGTH + 1)) } else ver = it[i]
    if (op == "") op = "="
    if ((k = key(ver)) == "") { why = "an item that is not a comparison with a version: " it[i]; return -1 }
    for (j = 1; j < i; j++) if (keys[j] == k) { why = "the version " ver " twice"; return -1 }
    # insertion sort by the version
    for (j = i - 1; j >= 1 && keys[j] > k; j--) { keys[j + 1] = keys[j]; ops[j + 1] = ops[j] }
    keys[j + 1] = k; ops[j + 1] = op
  }
  m = 0; open = 0
  for (i = 1; i <= n; i++) {
    if (ops[i] == ">=" || ops[i] == ">") {
      if (open) { why = "a lower bound in an open interval"; return -1 }
      m++; lo[m] = keys[i]; loin[m] = (ops[i] == ">="); hi[m] = ""; open = 1
    } else if (ops[i] == "<=" || ops[i] == "<") {
      if (!open) {
        if (m > 0) { why = "an upper bound with no lower bound after an interval"; return -1 }
        m++; lo[m] = ""; loin[m] = 0
      }
      hi[m] = keys[i]; hiin[m] = (ops[i] == "<="); open = 0
    } else {
      if (open) { why = "a version alone in an open interval"; return -1 }
      m++; lo[m] = keys[i]; loin[m] = 1; hi[m] = keys[i]; hiin[m] = 1
    }
  }
  return m
}
function inside(k, i) {
  if (lo[i] != "" && (loin[i] ? k < lo[i] : k <= lo[i])) return 0
  if (hi[i] != "" && (hiin[i] ? k > hi[i] : k >= hi[i])) return 0
  return 1
}
BEGIN {
  while ((getline line <manifest) > 0) {
    if (++ln == 1) continue
    split(line, f, "\t")
    vers[f[1]] = (f[1] in vers) ? vers[f[1]] " " f[2] : f[2]
  }
  close(manifest)
}
{
  g = $1; pkg = $4; r = $5; pv = $6
  if ($3 != "rust" && $3 != "crates.io") { err(g ": the ecosystem " $3 " of " pkg " is not rust or crates.io"); next }
  if (!(pkg in vers)) { err(g ": the package " pkg " is not in " manifest); next }
  n = range(r)
  if (n < 0) { err(g ": cannot read the range \"" r "\" of " pkg ": " why); next }
  nv = split(vers[pkg], vs, " ")
  for (v = 1; v <= nv; v++) {
    k = key(vs[v])
    if (k == "") { err(g ": the version " vs[v] " of " pkg " in " manifest " is not one"); continue }
    if (k in ex) continue
    for (i = 1; i <= n && !inside(k, i); i++) ;
    if (i > n) continue
    if (hi[i] != "") { hit(g); continue }
    # an interval with no upper bound: read the patched versions
    np = items(pv, ps)
    bad = 0; max = ""
    for (j = 1; j <= np; j++) {
      p = ps[j]; sub(/^>=[ \t]*/, "", p)
      if ((pk[j] = key(p)) == "") bad = 1
      else if (pk[j] > max) max = pk[j]
    }
    if (bad) { err(g ": cannot read the patched versions \"" pv "\" of " pkg); continue }
    fixed = 0
    for (j = 1; j <= np; j++)
      if (pk[j] >= lo[i] && pk[j] <= k && (series(pk[j]) == series(k) || pk[j] == max)) fixed = 1
    if (fixed) { printf "note: %s\t%s\t%s\t%s\t%s\n", g, pkg, vs[v], r, pv >>notefile; continue }
    hit(g)
  }
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
for f in "$TMP/notes" "$TMP/errors"; do
  if [ -s "$f" ]; then cat "$f" >&2; fi
done
exit "${code:-0}"
