#!/bin/sh
# Writes stdin to stdout with each relative Markdown link made absolute
# (docs/adr/0259-record-what-the-audit-of-the-ci-release-and-tooling-adrs-found-on-2026-11-09.md),
# so that a status line of an ADR in the release notes links what it
# links in the repository.
#
#   absolute-links.sh REV PATH
#
# PATH is the file of the repository the text is from. The target of a
# link [TEXT](TARGET) is resolved against the directory of PATH ("." and
# ".." are taken away) and becomes https://github.com/tett23/golem/blob/REV/
# followed by it; a target that is only an anchor (#...) becomes PATH and
# the anchor. A target with a scheme (https:, mailto:, ...) stays as it is.
set -eu
[ $# -eq 2 ] || {
  echo "usage: absolute-links.sh REV PATH" >&2
  exit 2
}
# C locale: macOS awk stops at bytes that are not UTF-8; the bytes of a
# character are never "]", "(" nor ")"
LC_ALL=C awk -v base="https://github.com/tett23/golem/blob/$1/" -v path="$2" '
  # the path of TARGET, with its anchor, resolved against the directory of path
  function resolve(t,   anchor, i, n, parts, out, m, k, dir) {
    anchor = ""
    i = index(t, "#")
    if (i > 0) { anchor = substr(t, i); t = substr(t, 1, i - 1) }
    if (t == "") return path anchor
    dir = path; sub(/[^\/]*$/, "", dir)
    n = split(dir t, parts, "/")
    m = 0
    for (k = 1; k <= n; k++) {
      if (parts[k] == "" || parts[k] == ".") continue
      if (parts[k] == "..") { if (m > 0) m--; continue }
      out[++m] = parts[k]
    }
    t = ""
    for (k = 1; k <= m; k++) t = t (k > 1 ? "/" : "") out[k]
    return t anchor
  }
  {
    line = $0; res = ""
    while (match(line, /\]\([^()]*\)/)) {
      target = substr(line, RSTART + 2, RLENGTH - 3)
      res = res substr(line, 1, RSTART + 1)
      if (target ~ /^[A-Za-z][A-Za-z0-9+.-]*:/) res = res target
      else res = res base resolve(target)
      res = res ")"
      line = substr(line, RSTART + RLENGTH)
    }
    print res line
  }'
