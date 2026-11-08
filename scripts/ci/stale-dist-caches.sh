#!/bin/sh
# The dist- caches of main to delete, for the job caches of ci.yml
# (docs/adr/0228-keep-the-ci-caches-under-the-10-gb-limit.md).
#
#   gh cache list --ref refs/heads/main --key dist- --json id,key,createdAt \
#     --jq '.[] | [.id, .createdAt, .key] | @tsv' |
#     stale-dist-caches.sh PREFIX...
#
# The input has one cache a line: its ID, the time it was made (as the API
# writes it, 2026-11-08T03:22:56.727245Z) and its key, separated by tabs.
# Each PREFIX is the key of a family of the current keys without the commit
# hash (the dist-newstyle of x86-64 and of aarch64, and dist-wasm). Writes
# the IDs to delete, one a line, in ascending order:
#
# - of the caches of a family, all but the one made last (of two made at
#   the same time, the larger ID is kept);
# - every dist- cache of no family (a family before a change of the GHC
#   version or the freeze).
#
# A key that does not start with dist- is never written. A key is of the
# family of the first PREFIX that it starts with. The exit code is 2 for a
# wrong argument and 1 for a line that is not of the form above.
set -eu
if [ $# -eq 0 ]; then
  echo "usage: stale-dist-caches.sh PREFIX... < caches.tsv" >&2
  exit 2
fi
for p in "$@"; do
  case "$p" in
    *[[:space:]]*)
      echo "stale-dist-caches: the prefix has a space: $p" >&2
      exit 2
      ;;
    dist-?*) ;;
    *)
      echo "stale-dist-caches: the prefix does not start with dist-: $p" >&2
      exit 2
      ;;
  esac
done
# separated by spaces: awk -v takes no newline in some awk (macOS)
PREFIXES=$(printf '%s ' "$@")
STALE=$(awk -F '\t' -v prefixes="$PREFIXES" '
  BEGIN { n = split(prefixes, prefix, " ") }
  # the time as a string that sorts as the time: the fraction of the
  # second padded with zeros to nine digits
  function stamp(t,   frac, i) {
    if (t !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z$/) return ""
    t = substr(t, 1, length(t) - 1)
    i = index(t, ".")
    if (i == 0) { frac = ""; } else { frac = substr(t, i + 1); t = substr(t, 1, i - 1) }
    while (length(frac) < 9) frac = frac "0"
    return t "." frac
  }
  function bad(why) {
    printf "stale-dist-caches: line %d: %s\n", NR, why > "/dev/stderr"
    exit 1
  }
  {
    if (NF != 3) bad("not an ID, a time and a key")
    id = $1; key = $3
    if (id !~ /^[0-9]+$/) bad("the ID is not a number: " id)
    s = stamp($2)
    if (s == "") bad("the time is not of the API: " $2)
    if (substr(key, 1, 5) != "dist-") next
    family = 0
    for (i = 1; i <= n; i++) if (index(key, prefix[i]) == 1) { family = i; break }
    if (family == 0) { print id; next }
    if (!(family in keep)) { keep[family] = id; at[family] = s; next }
    if (s > at[family] || (s == at[family] && id + 0 > keep[family] + 0)) {
      print keep[family]
      keep[family] = id; at[family] = s
    } else {
      print id
    }
  }
')
# the IDs of the caches, sorted; nothing for no cache
if [ -n "$STALE" ]; then printf '%s\n' "$STALE" | sort -n; fi
