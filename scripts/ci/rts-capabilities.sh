#!/bin/sh
# Checks that no program under modules/ changes its number of capabilities
# while it runs, so that the hang of the test suites in CI cannot come
# back.
#
# Two calls of setNumCapabilities that raise the count at the same time
# deadlock the threaded RTS of GHC 9.10.3. In rts/Schedule.c (tag
# ghc-9.10.3-release) setNumCapabilities reads old_n_capabilities (line
# 2272) and compares with enabled_capabilities (2274) before it stops the
# other capabilities (2297); acquireAllCapabilities takes all of them
# (1543), but releaseAllCapabilities releases only old_n_capabilities
# (2371). When one call has already raised the count, the other one keeps
# the new capabilities: their running_task is its Task forever, and the
# next GC waits for one of them (1786-1789) without end. GHC issue #22989
# (setnumcapabilities001 times out) is open. The tests did that: tasty
# runs tests at once, and several of them raised the count to eight.
#
#   rts-capabilities.sh [ROOT]
#
# Two rules:
#   - no Haskell file under ROOT/modules calls setNumCapabilities;
#   - every component (executable, test-suite, benchmark) built with
#     -threaded starts on every processor: its ghc-options (its own or
#     those of a common stanza it imports) have -with-rtsopts with -N.
#     tasty (1.5) calls setNumCapabilities at start when the program has
#     fewer capabilities than processors; with -N it never does.
# A call is written to stderr as FILE:LINE, a component as FILE: COMPONENT,
# and the exit code is 1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${1:-$HERE/../..}
STATUS=0
calls=$(grep -rn --include='*.hs' 'setNumCapabilities' "$ROOT/modules" || true)
if [ -n "$calls" ]; then
  printf '%s\n' "$calls" | cut -d: -f1,2 | sed "s|^${ROOT}/||" >&2
  STATUS=1
fi
for cabal in "$ROOT"/modules/*/*.cabal; do
  [ -f "$cabal" ] || continue
  missing=$(awk '
    # the RTS options of a ghc-options line have -N as one of their words
    function has_n(line,   rest, q, quoted, words, k, i) {
      k = index(line, "-with-rtsopts=")
      if (k == 0) return 0
      quoted = (k > 1 && substr(line, k - 1, 1) == "\"")
      rest = substr(line, k + length("-with-rtsopts="))
      # "-with-rtsopts=-N -A64m" or -with-rtsopts="-N -A64m": up to the closing quote
      if (substr(rest, 1, 1) == "\"") { quoted = 1; rest = substr(rest, 2) }
      if (quoted) { q = index(rest, "\""); if (q > 0) rest = substr(rest, 1, q - 1) }
      else { sub(/[ \t].*/, "", rest) }
      k = split(rest, words, " ")
      for (i = 1; i <= k; i++) if (words[i] == "-N") return 1
      return 0
    }
    function close_component() {
      if (component != "") { thr[component] = own_thr; n_ok[component] = own_n; imports[component] = imported }
    }
    /^[^ \t-]/ {
      close_component()
      component = ""; common = ""; own_thr = 0; own_n = 0; imported = ""
      if ($1 == "common") { common = $2 }
      else if ($1 ~ /^(executable|test-suite|benchmark)$/) { component = $0; order[++n] = component }
      next
    }
    /^[ \t]+ghc-options:/ {
      t = ($0 ~ /(^|[ \t:"])-threaded([ \t"]|$)/); r = has_n($0)
      if (common != "") { if (t) common_thr[common] = 1; if (r) common_n[common] = 1 }
      if (component != "") { if (t) own_thr = 1; if (r) own_n = 1 }
      next
    }
    /^[ \t]+import:/ {
      line = $0; sub(/^[ \t]+import:[ \t]*/, "", line); gsub(/[ \t,]+/, " ", line)
      imported = imported " " line
      next
    }
    END {
      close_component()
      for (i = 1; i <= n; i++) {
        c = order[i]; t = thr[c]; r = n_ok[c]
        m = split(imports[c], names, " ")
        for (j = 1; j <= m; j++) { if (names[j] in common_thr) t = 1; if (names[j] in common_n) r = 1 }
        if (t && !r) print c
      }
    }
  ' "$cabal")
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | sed "s|^|${cabal#"$ROOT"/}: |" >&2
    STATUS=1
  fi
done
exit "$STATUS"
