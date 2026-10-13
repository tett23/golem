#!/bin/sh
# Tests of the CI scripts (docs/adr/0009-ci-speed.md). The changes job of
# .github/workflows/ci.yml runs this before it decides whether to build.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
FAILURES=0
COUNT=0

ok() { COUNT=$((COUNT + 1)); }
ng() {
  COUNT=$((COUNT + 1))
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
  if [ -s "$WORK/out" ]; then sed 's/^/  stdout: /' "$WORK/out"; fi
  if [ -s "$WORK/err" ]; then sed 's/^/  stderr: /' "$WORK/err"; fi
  return 0
}

# run CMD...: stdin from $WORK/in, stdout to $WORK/out, stderr to $WORK/err,
# the exit code to $CODE
run() {
  CODE=0
  "$@" <"$WORK/in" >"$WORK/out" 2>"$WORK/err" || CODE=$?
}

# expect NAME CODE [STDOUT]: checks the result of the last run
expect() {
  name=$1 code=$2
  if [ "$CODE" != "$code" ]; then
    ng "$name (exit code $CODE, expected $code)"
    return 0
  fi
  if [ $# -ge 3 ] && [ "$(cat "$WORK/out")" != "$3" ]; then
    ng "$name (stdout)"
    printf '  expected: %s\n' "$3"
    return 0
  fi
  ok
}

# ---------------------------------------------------------------- needs-build.sh

needs_build() { sh "$HERE/needs-build.sh"; }

# paths NAME EXPECTED PATH...: the paths, one per line, are the input
paths() {
  name=$1 expected=$2
  shift 2
  : >"$WORK/in"
  for p in "$@"; do printf '%s\n' "$p" >>"$WORK/in"; done
  run needs_build
  expect "needs-build: $name" 0 "$expected"
}

paths "empty input" true
paths "an ADR" false docs/adr/0009-ci-speed.md
paths "Markdown at the root" false README.md CONTRIBUTING.en.md
paths "docs only" false docs/specifications.md docs/golem-pdf/adr/0005-producer.md
paths "docs and a module" true docs/specifications.md modules/golem-font/src/Golem/Font.hs
paths "a workflow" true .github/workflows/ci.yml
paths "a script" true scripts/determinism.sh
paths "Markdown under modules/" true modules/golem-layout/test/data/knuth-plass/README.md
paths "VERSION" true VERSION
paths "a directory that starts with docs" true docsx/a.md
paths "a file named docs" true docs
paths "a path with a space" false "docs/a b.md"

printf 'docs/a.md' >"$WORK/in"
run needs_build
expect "needs-build: no newline at the end" 0 false

paths "a document that the tests read" true docs/diagnostics.md
paths "it with another document" true docs/diagnostics.md docs/specifications.md
paths "the source of the manual (docs/adr/0022)" true docs/manual.md

# ---------------------------------------------------------------- changed-paths.sh
# (docs/adr/0021-docs-workflow-and-ci-gate.md)

changed_paths() { sh "$HERE/changed-paths.sh" "$@"; }
G=$WORK/git
mkdir -p "$G"
(
  cd "$G" || exit 1
  git init -q -b main .
  git config user.email ci@example.com
  git config user.name ci
  echo a >a.hs && git add a.hs && git commit -q -m a
  git checkout -q -b topic
  mkdir -p docs && echo x >docs/x.md && echo s >"docs/a b.md" && echo j >docs/日本語.md
  git add docs && git commit -q -m x
  git checkout -q main
  echo b >b.hs && git add b.hs && git commit -q -m b
) >/dev/null 2>&1
MAIN=$(git -C "$G" rev-parse main)
MAIN1=$(git -C "$G" rev-parse main~1)
TOPIC=$(git -C "$G" rev-parse topic)
: >"$WORK/in"
in_g() { (cd "$G" && changed_paths "$@"); }
run in_g pull_request "$MAIN" "$TOPIC"
expect "changed-paths: a pull request from the merge base" 0 "docs/a b.md
docs/x.md
docs/日本語.md"
run in_g push "$MAIN1" "$MAIN"
expect "changed-paths: a push" 0 "b.hs"
run in_g push 0000000000000000000000000000000000000000 "$MAIN"
expect "changed-paths: a push that creates the branch" 3 ""
run in_g push "" "$MAIN"
expect "changed-paths: a push without before" 3 ""
run in_g workflow_dispatch
expect "changed-paths: workflow_dispatch" 3 ""
run in_g pull_request 1234567890123456789012345678901234567890 "$TOPIC"
if [ "$CODE" != 0 ] && [ "$CODE" != 3 ]; then ok; else ng "changed-paths: a commit that does not exist (exit code $CODE)"; fi

# ---------------------------------------------------------------- docs-refs.sh

docs_refs() { sh "$HERE/docs-refs.sh" "$@"; }
run docs_refs "$HERE/../.."
expect "docs-refs: the repository" 0
R=$WORK/refs
mkdir -p "$R/modules/x/test" "$R/scripts"
printf 'main = readFile "../../docs/new.md"\n' >"$R/modules/x/test/Main.hs"
run docs_refs "$R"
expect "docs-refs: a document that is not in the list" 1
if grep -q 'docs/new.md' "$WORK/err"; then ok; else ng "docs-refs: the document is named"; fi
printf -- '-- docs/adr/0001-x.md\nmain = readFile "../../docs/diagnostics.md"\n' >"$R/modules/x/test/Main.hs"
run docs_refs "$R"
expect "docs-refs: an ADR and a listed document" 0

# ---------------------------------------------------------------- gate.sh

gate() { sh "$HERE/gate.sh" "$@"; }
needs() { # needs NAME=RESULT...: the JSON of the needs context
  printf '{'
  sep=
  for nr in "$@"; do
    printf '%s"%s":{"result":"%s","outputs":{}}' "$sep" "${nr%%=*}" "${nr#*=}"
    sep=,
  done
  printf '}\n'
}
needs changes=success build=success determinism=success release-scripts=success format=success >"$WORK/in"
run gate
expect "gate: all succeeded" 0
needs changes=success build=skipped determinism=skipped release-scripts=skipped format=skipped >"$WORK/in"
run gate
expect "gate: docs only" 0
needs changes=success build=failure determinism=skipped release-scripts=success format=success >"$WORK/in"
run gate
expect "gate: a failed build" 1
if grep -q 'build' "$WORK/err" && grep -q 'failure' "$WORK/err"; then ok; else ng "gate: the failed job is named"; fi
needs changes=success build=success determinism=cancelled release-scripts=success format=success >"$WORK/in"
run gate
expect "gate: a cancelled job" 1
needs changes=success build=success determinism=success release-scripts=success >"$WORK/in"
run gate
expect "gate: a missing job" 1
if grep -q 'format' "$WORK/err"; then ok; else ng "gate: the missing job is named"; fi
echo 'not json' >"$WORK/in"
run gate
expect "gate: not JSON" 1

# the jobs of ci.yml, but ci itself, are the jobs that gate.sh knows
ci_jobs() { # ci_jobs WORKFLOW: the names of its jobs
  awk '/^jobs:/ { on = 1; next } on && /^[^ #]/ { on = 0 } on && /^  [a-z][a-z0-9-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$1"
}
: >"$WORK/in"
run gate --names
if [ "$CODE" = 0 ] && [ "$(sort "$WORK/out")" = "$(ci_jobs "$HERE/../../.github/workflows/ci.yml" | grep -vx ci | sort)" ]; then ok; else ng "gate: the names are the jobs of ci.yml"; fi
ci_jobs "$HERE/../../.github/workflows/ci.yml" | grep -vx ci | grep -vx format >"$WORK/fewer"
if [ "$(sort "$WORK/out")" != "$(sort "$WORK/fewer")" ]; then ok; else ng "gate: a job missing from the names is found"; fi

# ---------------------------------------------------------------- timings.sh

timings() { sh "$HERE/timings.sh" "$@"; }

cp "$HERE/testdata/run.json" "$WORK/in"
run timings
expect "timings: run 38319536503" 0 "| ジョブ | ステップ | 秒 |
|---|---|---|
| \`build (ubuntu-24.04)\` | ジョブ全体 | 564 |
| \`build (ubuntu-24.04)\` | \`Set up job\` | 1 |
| \`build (ubuntu-24.04)\` | \`Run actions/checkout@v7\` | 1 |
| \`build (ubuntu-24.04)\` | \`Run haskell-actions/setup@v2\` | 143 |
| \`build (ubuntu-24.04)\` | \`Run cabal build all\` | 230 |
| \`adr\` | ジョブ全体 | 5 |
| \`adr\` | \`Set up job\` | 0 |
| \`adr\` | \`Run actions/checkout@v7\` | 2 |
| \`adr\` | \`Run tett23/adr-guard@v0.2.1\` | 0 |
| \`determinism\` | ジョブ全体 | 4 |
| \`determinism\` | \`Set up job\` | 1 |
| \`determinism\` | \`Run actions/download-artifact@v8\` | 1 |
| \`determinism\` | \`Outputs are byte-identical on x86-64 and aarch64\` | 0 |"

# run J S1 S2 DURATION...: one run with the job J; step i lasts the i-th
# duration in seconds, or is cancelled if the duration is "-"
mkrun() {
  job=$1
  shift
  printf '{"jobs":[{"name":"%s","startedAt":"2026-10-12T00:00:00Z","completedAt":"2026-10-12T00:01:00Z","steps":[' "$job"
  i=0
  for d in "$@"; do
    i=$((i + 1))
    [ "$i" -gt 1 ] && printf ','
    if [ "$d" = - ]; then
      end=0001-01-01T00:00:00Z
    else
      end=$(printf '2026-10-12T00:00:%02dZ' "$d")
    fi
    printf '{"name":"s%s","number":%s,"startedAt":"2026-10-12T00:00:00Z","completedAt":"%s"}' "$i" "$i" "$end"
  done
  printf ']}]}\n'
}

mkrun j 3 - >"$WORK/in"
run timings
expect "timings: a cancelled step" 0 "| ジョブ | ステップ | 秒 |
|---|---|---|
| \`j\` | ジョブ全体 | 60 |
| \`j\` | \`s1\` | 3 |
| \`j\` | \`s2\` | - |"

printf '%s\n' '{"jobs":[{"name":"d","startedAt":"2026-10-12T22:23:26Z","completedAt":"2026-10-12T22:23:25Z","conclusion":"skipped","steps":[]}]}' >"$WORK/in"
run timings
expect "timings: a skipped job" 0 "| ジョブ | ステップ | 秒 |
|---|---|---|
| \`d\` | ジョブ全体 | - |"

mkrun 'a | b' 1 >"$WORK/in"
run timings
expect "timings: a bar in a name" 0 "| ジョブ | ステップ | 秒 |
|---|---|---|
| \`a \\| b\` | ジョブ全体 | 60 |
| \`a \\| b\` | \`s1\` | 1 |"

{
  mkrun j 10 10 -
  mkrun j 30 20 -
  mkrun j 20 -
} >"$WORK/in"
run timings --median
expect "timings: --median" 0 "| ジョブ | ステップ | 最小 | 中央値 | 最大 |
|---|---|---|---|---|
| \`j\` | ジョブ全体 | 60 | 60 | 60 |
| \`j\` | \`s1\` | 10 | 20 | 30 |
| \`j\` | \`s2\` | 10 | 15 | 20 |
| \`j\` | \`s3\` | - | - | - |"

{
  cat "$HERE/testdata/run.json"
  cat "$HERE/testdata/run.json"
} >"$WORK/in"
run timings --median
if grep -qx '| `build (ubuntu-24.04)` | `Run haskell-actions/setup@v2` | 143 | 143 | 143 |' "$WORK/out"; then ok; else ng "timings: --median of run 38319536503 twice"; fi

: >"$WORK/in"
run timings --bogus
expect "timings: an unknown option" 2

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
