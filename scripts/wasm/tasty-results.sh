#!/bin/sh
# The results of the tests in the output of a tasty suite run with
# --color never (docs/adr/0293): one line per test, the result (OK, FAIL
# or SKIP), a tab, and the full name of the test as tasty's patterns see
# it ($0: the names of its groups and its own, joined with .).
#
#   tasty-results.sh [LOG]   (stdin by default)
#
# tasty writes a group as its name, and a test as its name, a colon,
# spaces and the result, each indented by two spaces more than its group.
# The lines after a test that are indented more than it (the description
# of a failure, tasty's "Use -p" line) are the test's, not groups. Lines
# without indentation after the tree (the counts, the lines of the
# skipped tests of Golem.TestSupport.Skipped) end it.
set -eu
[ $# -le 1 ] || { echo "usage: tasty-results.sh [LOG]" >&2; exit 2; }
awk '
  function indent(s) { match(s, /^ */); return RLENGTH }
  {
    sub(/\r$/, "")
    if ($0 ~ /^[[:space:]]*$/) next
    d = indent($0)
    if (body >= 0 && d > body) next
    body = -1
    text = substr($0, d + 1)
    level = d / 2
    if (d % 2 != 0) next
    if (match(text, /: +(OK|FAIL|SKIP)( \([0-9.]+s\))?$/)) {
      name = substr(text, 1, RSTART - 1)
      result = substr(text, RSTART)
      sub(/^: +/, "", result)
      sub(/ .*$/, "", result)
      full = ""
      for (i = 0; i < level; i++) full = full group[i] "."
      print result "\t" full name
      body = d
      next
    }
    if (d == 0 && seen) { stop = 1 }
    if (stop) next
    group[level] = text
    seen = 1
  }
  BEGIN { body = -1 }
' "${1:--}"
