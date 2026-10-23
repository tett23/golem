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
#     -threaded starts on every processor: the last -with-rtsopts of its
#     ghc-options (those of the common stanzas it imports, then its own)
#     has -N. GHC keeps the last -with-rtsopts only (9.10.3).
#     tasty (1.5) calls setNumCapabilities at start when the program has
#     fewer capabilities than processors; with -N it never does.
# The .cabal files are read as cabal reads them: the names of sections and
# fields in any case, and a field on the lines indented under its name
# (docs/adr/0069-lint-scripts-bypassed-by-plain-rewrites.md).
# incomplete-patterns.sh reads them the same way, with its own code, so
# that the two checks stay apart.
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
    # "1" if the last -with-rtsopts of the options has -N, "0" if it has
    # not, "" if there is none
    function last_rts(line,   k, quoted, rest, q, val, words, n, i, res) {
      res = ""
      while ((k = index(line, "-with-rtsopts=")) > 0) {
        quoted = (k > 1 && substr(line, k - 1, 1) == "\"")
        rest = substr(line, k + length("-with-rtsopts="))
        # "-with-rtsopts=-N -A64m" or -with-rtsopts="-N -A64m": up to the closing quote
        if (substr(rest, 1, 1) == "\"") { quoted = 1; rest = substr(rest, 2) }
        if (quoted) {
          q = index(rest, "\"")
          if (q > 0) { val = substr(rest, 1, q - 1); line = substr(rest, q + 1) }
          else { val = rest; line = "" }
        } else {
          match(rest, /^[^ \t]*/); val = substr(rest, 1, RLENGTH); line = substr(rest, RLENGTH + 1)
        }
        n = split(val, words, " "); res = "0"
        for (i = 1; i <= n; i++) if (words[i] == "-N") res = "1"
      }
      return res
    }
    # the end of a field: its value is all of its lines
    function close_field(   t, r, line) {
      if (field == "ghc-options" && scope != "") {
        t = (value ~ /(^|[ \t:"])-threaded([ \t"]|$)/); r = last_rts(value)
        if (t) thr[scope] = 1
        if (r != "") rts[scope] = r
      } else if (field == "import" && scope != "") {
        line = value; gsub(/[ \t,]+/, " ", line)
        imports[scope] = imports[scope] " " line
      }
      field = ""; value = ""
    }
    /^[ \t]*--/ || /^[ \t]*$/ { next }
    /^[^ \t]/ {
      close_field()
      scope = ""
      kind = tolower($1)
      if (kind == "common") { scope = "common " $2 }
      else if (kind ~ /^(executable|test-suite|benchmark)$/) {
        header = $0; sub(/[ \t]+$/, "", header)
        scope = header; order[++n] = scope
      }
      next
    }
    {
      match($0, /^[ \t]*/); indent = RLENGTH
      if (field != "" && indent > field_indent) { value = value " " substr($0, indent + 1); next }
      close_field()
      if (match($0, /^[ \t]+[A-Za-z][A-Za-z0-9_-]*[ \t]*:/)) {
        name = substr($0, indent + 1, RLENGTH - indent); sub(/[ \t]*:$/, "", name)
        field = tolower(name); field_indent = indent
        value = substr($0, RLENGTH + 1)
      }
    }
    END {
      close_field()
      for (i = 1; i <= n; i++) {
        c = order[i]; t = thr[c]; r = ""
        m = split(imports[c], names, " ")
        for (j = 1; j <= m; j++) {
          if (thr["common " names[j]]) t = 1
          if (rts["common " names[j]] != "") r = rts["common " names[j]]
        }
        if (rts[c] != "") r = rts[c]
        if (t && r != "1") print c
      }
    }
  ' "$cabal")
  if [ -n "$missing" ]; then
    printf '%s\n' "$missing" | sed "s|^|${cabal#"$ROOT"/}: |" >&2
    STATUS=1
  fi
done
exit "$STATUS"
