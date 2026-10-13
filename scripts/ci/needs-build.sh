#!/bin/sh
# Reads the changed paths, one per line, and writes "true" if the change
# needs the build, the tests and the other checks, "false" if it does not
# (docs/adr/0009-ci-speed.md). Only the files under docs/ and the Markdown
# files at the root of the repository need no build; Markdown under modules/
# is test data. An empty input writes "true", so that a missing diff never
# skips the checks.
#
# The documents under docs/ that the build or the tests read are not docs
# only: a change of one of them needs the build (docs/adr/0021). docs-refs.sh
# checks that the list has every document that the code names.
# docs/manual.md is the source of the manual: the build job checks its
# headings against manual/ (docs/adr/0022).
#
#   needs-build.sh < paths
#   needs-build.sh --list     the documents that the build reads
set -eu
BUILD_DOCS="docs/diagnostics.md docs/manual.md"
if [ "${1-}" = --list ]; then
  printf '%s\n' $BUILD_DOCS
  exit 0
fi
awk -v docs="$BUILD_DOCS" '
  BEGIN { n = split(docs, d, " "); for (i = 1; i <= n; i++) read[d[i]] = 1; n = 0 }
  /^$/ { next }
  { n++ }
  $0 in read { build = 1; next }
  /^docs\// { next }
  /^[^\/]+\.md$/ { next }
  { build = 1 }
  END { print ((n == 0 || build) ? "true" : "false") }
'
