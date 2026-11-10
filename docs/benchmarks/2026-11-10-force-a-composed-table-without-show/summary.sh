#!/bin/sh
# summary.sh RESULTS: for each input, the medians of golem-before and
# golem-after (allocation, maximum residency, CPU, wall clock), the
# allocation of after as a share of before, the medians of the ratios
# after / before of CPU and of the wall clock within a round, and the
# number of distinct output hashes.
awk '
function v(s, k,  a) { split(s, a, "="); return a[2] }
function med(arr, n,   i, j, t, b) { for (i = 1; i <= n; i++) b[i] = arr[i]; for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (b[j] < b[i]) { t = b[i]; b[i] = b[j]; b[j] = t } return (n % 2) ? b[(n + 1) / 2] : (b[n / 2] + b[n / 2 + 1]) / 2 }
{
  r = $1; f = $2; w = $3
  if (!(f in seen)) { seen[f] = 1; order[++nf] = f }
  for (i = 4; i <= NF; i++) { split($i, a, "="); x[r, f, w, a[1]] = a[2] }
  if (x[r, f, w, "exit"] != 0) bad++
  hashes[f, x[r, f, w, "hash"]] = 1
  if (r > rounds) rounds = r
}
END {
  printf "%-18s %9s %9s %6s %8s %8s %7s %7s %6s %6s %s\n", "input", "allocB", "allocA", "A/B", "maxresB", "maxresA", "cpuB", "cpuA", "cpuA/B", "wallA/B", "hashes"
  for (k = 1; k <= nf; k++) {
    f = order[k]
    for (r = 1; r <= rounds; r++) {
      ab[r] = x[r, f, "before", "alloc"]; aa[r] = x[r, f, "after", "alloc"]
      mb[r] = x[r, f, "before", "maxres"]; ma[r] = x[r, f, "after", "maxres"]
      cb[r] = x[r, f, "before", "cpu"]; ca[r] = x[r, f, "after", "cpu"]
      cr[r] = x[r, f, "after", "cpu"] / x[r, f, "before", "cpu"]
      wr[r] = x[r, f, "after", "wall"] / x[r, f, "before", "wall"]
    }
    nh = 0; for (h in hashes) { split(h, p, SUBSEP); if (p[1] == f) nh++ }
    printf "%-18s %9.3f %9.3f %6.3f %8.1f %8.1f %7.2f %7.2f %6.3f %6.3f %d\n", f, med(ab, rounds) / 1e9, med(aa, rounds) / 1e9, med(aa, rounds) / med(ab, rounds), med(mb, rounds) / 1e6, med(ma, rounds) / 1e6, med(cb, rounds), med(ca, rounds), med(cr, rounds), med(wr, rounds), nh
  }
  if (bad) printf "builds with a non-zero exit: %d\n", bad
}' "$1"
