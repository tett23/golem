#!/bin/sh
# Checks the Japanese writing rules of the documents with textlint
# (docs/adr/0036-textlint-for-documents.md). CI (the textlint job of docs.yml)
# and developers run the same script.
#
#   textlint.sh [BASE]
#
# BASE is the commit that the branch started from; the ADRs added since then
# (committed, staged, changed or untracked) are checked. It defaults to the
# merge base of origin/main and HEAD. With a BASE that is not a commit (a
# push that created a branch, BASE of zeros), no ADR is checked. Committed
# ADRs cannot change and are never checked.
#
# The profiles in tools/textlint/config/:
#   docs         docs/**/*.md but the ADRs, docs/diagnostics.md and the
#                records (docs/audit/, docs/audits/, docs/benchmark/,
#                docs/benchmarks/, docs/ci-timings/); README.md;
#                CONTRIBUTING.md
#   diagnostics  docs/diagnostics.md
#   adr          the ADRs added since BASE
#   manual       manual/**/*.gm
#   manual-dev   manual-dev/**/*.gm
# CONTRIBUTING.en.md is English and is not checked.
#
# The first run installs the pinned packages (npm ci in tools/textlint).
# Extra arguments for textlint go in TEXTLINT_ARGS, for example
# TEXTLINT_ARGS=--fix to apply the fixes of prh and the spacing rules.
# The exit code is 1 when a document breaks a rule.
set -eu
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
TOOL=tools/textlint
TEXTLINT=$TOOL/node_modules/.bin/textlint
if [ ! -x "$TEXTLINT" ]; then
  npm ci --prefix "$TOOL" --no-fund --no-audit
fi

# the file names have no spaces; splitting on whitespace is safe
set -f
# The profiles run in parallel (most of the time goes to the morphological
# analysis of the Markdown profiles); each writes its report to OUT and the
# reports are printed in order at the end.
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
PROFILES=
run() {
  profile=$1
  shift
  [ $# -gt 0 ] || return 0
  PROFILES="$PROFILES $profile"
  # shellcheck disable=SC2086
  { "$TEXTLINT" --config "$TOOL/config/$profile.js" ${TEXTLINT_ARGS-} "$@" >"$OUT/$profile" 2>&1 ||
    : >"$OUT/$profile.failed"; } &
}

RECORDS='^docs/(audit|audits|benchmark|benchmarks|ci-timings)/'
ADR='(^|/)adr/'

# shellcheck disable=SC2046
run docs $(git ls-files -- 'docs/*.md' README.md CONTRIBUTING.md |
  grep -v -E "$RECORDS|$ADR|^docs/diagnostics\.md$")
run diagnostics docs/diagnostics.md

BASE=${1-}
if [ -z "$BASE" ]; then
  BASE=$(git merge-base origin/main HEAD 2>/dev/null || true)
fi
if [ -n "$BASE" ] && git rev-parse -q --verify "$BASE^{commit}" >/dev/null; then
  FORK=$(git merge-base "$BASE" HEAD)
  # shellcheck disable=SC2046
  run adr $({
    git -c core.quotePath=false diff --name-only --diff-filter=A "$FORK" -- 'docs/*.md'
    git -c core.quotePath=false ls-files --others --exclude-standard -- 'docs/*.md'
  } | grep -E "$ADR" | sort -u)
else
  echo "textlint.sh: no base commit; the new ADRs are not checked" >&2
fi

# shellcheck disable=SC2046
run manual $(git ls-files -- 'manual/*.gm')
# shellcheck disable=SC2046
run manual-dev $(git ls-files -- 'manual-dev/*.gm')

wait
STATUS=0
for profile in $PROFILES; do
  cat "$OUT/$profile"
  if [ -e "$OUT/$profile.failed" ]; then
    echo "textlint.sh: the $profile profile failed" >&2
    STATUS=1
  fi
done
exit "$STATUS"
