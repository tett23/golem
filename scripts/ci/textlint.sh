#!/bin/sh
# Checks the Japanese writing rules of the documents with textlint
# (docs/adr/0036-textlint-for-documents.md, docs/adr/0258-textlint-per-file-jobs-and-a-cache-of-clean-results.md).
# CI (the textlint job of docs.yml) and developers run the same script.
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
#                CONTRIBUTING.md; functions/README.md
#   diagnostics  docs/diagnostics.md
#   adr          the ADRs added since BASE
#   manual       manual/**/*.gm
#   manual-dev   manual-dev/**/*.gm
# CONTRIBUTING.en.md is English and is not checked.
#
# Each Markdown file is a job of its own, and each manual is one job (its
# rules look at characters and lines and take well under a second). The jobs
# run in parallel, the largest first, TEXTLINT_JOBS at a time (the number of
# processors by default); the reports are printed in the order above.
#
# A job that reports nothing is remembered in the cache file TEXTLINT_CACHE
# (tools/textlint/.cache/clean by default) under a key: the hash of the
# profile, the paths and the bytes of its files, the bytes and the names of
# every file under tools/textlint/ (node_modules included, the cache
# excluded), this script and the version of node. A job whose key is in the
# file is not run again. Only a job that reported nothing is remembered, so a
# run with the cache reports what a run without it reports. TEXTLINT_CACHE=
# (empty) turns the cache off. After a run the file holds the keys of that
# run's jobs that reported nothing, and no others.
#
# The first run installs the pinned packages (npm ci in tools/textlint).
# Extra arguments for textlint go in TEXTLINT_ARGS, for example
# TEXTLINT_ARGS=--fix to apply the fixes of prh and the spacing rules; with
# TEXTLINT_ARGS the cache is neither read nor written.
# The exit code is 1 when a document breaks a rule.
set -eu
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT"
TOOL=tools/textlint
TEXTLINT=$TOOL/node_modules/.bin/textlint
if [ ! -x "$TEXTLINT" ]; then
  npm ci --prefix "$TOOL" --no-fund --no-audit
fi
CACHE=${TEXTLINT_CACHE-$TOOL/.cache/clean}
if [ -n "${TEXTLINT_ARGS-}" ]; then
  CACHE=
fi
PARALLEL=${TEXTLINT_JOBS:-$(getconf _NPROCESSORS_ONLN)}

# the file names have no spaces; splitting on whitespace is safe
set -f
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

TOOLHASH=
if [ -n "$CACHE" ]; then
  find "$TOOL" -path "$TOOL/.cache" -prune -o -type f -print | LC_ALL=C sort >"$OUT/tool-files"
  TOOLHASH=$({
    node --version
    cat "$OUT/tool-files"
    git hash-object --no-filters --stdin-paths <"$OUT/tool-files"
    git hash-object --no-filters -- scripts/ci/textlint.sh
  } | git hash-object --stdin)
fi

# A job is a line "<bytes> <number> <key> <profile> <file>...".
N=0
job() {
  profile=$1
  shift
  [ $# -gt 0 ] || return 0
  N=$((N + 1))
  key=-
  if [ -n "$CACHE" ]; then
    key=$({
      printf '%s\n' "$TOOLHASH" "$profile" "$@"
      git hash-object --no-filters -- "$@"
    } | git hash-object --stdin)
  fi
  echo "$(cat -- "$@" | wc -c | tr -d ' ') $N $key $profile $*" >>"$OUT/jobs"
}
each() {
  profile=$1
  shift
  for file in "$@"; do
    job "$profile" "$file"
  done
}

RECORDS='^docs/(audit|audits|benchmark|benchmarks|ci-timings)/'
ADR='(^|/)adr/'

# shellcheck disable=SC2046
each docs $(git ls-files -- 'docs/*.md' README.md CONTRIBUTING.md functions/README.md |
  grep -v -E "$RECORDS|$ADR|^docs/diagnostics\.md$")
# shellcheck disable=SC2046
each diagnostics $(git ls-files -- docs/diagnostics.md)

BASE=${1-}
if [ -z "$BASE" ]; then
  BASE=$(git merge-base origin/main HEAD 2>/dev/null || true)
fi
if [ -n "$BASE" ] && git rev-parse -q --verify "$BASE^{commit}" >/dev/null; then
  FORK=$(git merge-base "$BASE" HEAD)
  # shellcheck disable=SC2046
  each adr $({
    git -c core.quotePath=false diff --name-only --diff-filter=A "$FORK" -- 'docs/*.md'
    git -c core.quotePath=false ls-files --others --exclude-standard -- 'docs/*.md'
  } | grep -E "$ADR" | sort -u)
else
  echo "textlint.sh: no base commit; the new ADRs are not checked" >&2
fi

# shellcheck disable=SC2046
job manual $(git ls-files -- 'manual/*.gm')
# shellcheck disable=SC2046
job manual-dev $(git ls-files -- 'manual-dev/*.gm')

[ "$N" -gt 0 ] || exit 0

if [ -n "$CACHE" ] && [ -f "$CACHE" ]; then
  cp "$CACHE" "$OUT/cache"
else
  : >"$OUT/cache"
fi

# The worker of a job. It writes its report to OUT/<number>, and the key to
# OUT/<number>.clean when the job reported nothing (or its key was in the
# cache), or OUT/<number>.failed when textlint failed.
# shellcheck disable=SC2016
WORKER='
set -f
n=$1 key=$2 profile=$3
shift 3
if [ "$key" != - ] && grep -q -x -F -e "$key" "$OUT/cache"; then
  : >"$OUT/$n"
  echo "$key" >"$OUT/$n.clean"
  exit 0
fi
# shellcheck disable=SC2086
if "$TEXTLINT" --config "$TOOL/config/$profile.js" ${TEXTLINT_ARGS-} "$@" >"$OUT/$n" 2>&1; then
  if [ "$key" != - ] && [ ! -s "$OUT/$n" ]; then
    echo "$key" >"$OUT/$n.clean"
  fi
else
  : >"$OUT/$n.failed"
fi
'
export OUT TEXTLINT TOOL
export TEXTLINT_ARGS="${TEXTLINT_ARGS-}"
sort -k1,1nr -k2,2n "$OUT/jobs" | cut -d ' ' -f 2- |
  xargs -L 1 -P "$PARALLEL" sh -c "$WORKER" sh

STATUS=0
: >"$OUT/clean"
i=1
while [ "$i" -le "$N" ]; do
  cat "$OUT/$i"
  if [ -e "$OUT/$i.failed" ]; then
    echo "textlint.sh: textlint failed on $(grep "^[0-9]* $i " "$OUT/jobs" | cut -d ' ' -f 4-)" >&2
    STATUS=1
  fi
  if [ -e "$OUT/$i.clean" ]; then
    cat "$OUT/$i.clean" >>"$OUT/clean"
  fi
  i=$((i + 1))
done

if [ -n "$CACHE" ]; then
  mkdir -p "$(dirname "$CACHE")"
  # written beside the cache and renamed, so that the file is never half written
  LC_ALL=C sort -u "$OUT/clean" >"$CACHE.$$"
  mv "$CACHE.$$" "$CACHE"
fi
exit "$STATUS"
