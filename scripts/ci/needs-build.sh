#!/bin/sh
# Reads the changed paths, one per line, and writes "true" if the change
# needs the build, the tests and the other checks, "false" if it does not
# (docs/adr/0009-ci-speed.md). Only the files under docs/ and the Markdown
# files at the root of the repository need no build; Markdown under modules/
# is test data. An empty input writes "true", so that a missing diff never
# skips the checks.
set -eu
awk '
  /^$/ { next }
  { n++ }
  /^docs\// { next }
  /^[^\/]+\.md$/ { next }
  { build = 1 }
  END { print ((n == 0 || build) ? "true" : "false") }
'
