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
paths "the policy of the manuals (docs/adr/0024)" false docs/manual-policy.md
paths "the developer manual (docs/adr/0024)" true manual-dev/style.toml
paths "the textlint tool (docs/adr/0036)" false tools/textlint/package-lock.json tools/textlint/rules/scan.js
paths "the textlint tool and docs (docs/adr/0036)" false tools/textlint/config/docs.js docs/specifications.md
paths "the textlint tool and a module (docs/adr/0036)" true tools/textlint/package.json modules/golem-font/src/Golem/Font.hs
paths "the textlint script (docs/adr/0036)" true scripts/ci/textlint.sh
paths "a directory that starts with tools/textlint" true tools/textlintx/a.js

needs_build_list() { sh "$HERE/needs-build.sh" --list; }
: >"$WORK/in"
run needs_build_list
expect "needs-build: the documents that the build reads (docs/adr/0024)" 0 "docs/diagnostics.md"

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

# ---------------------------------------------------------------- incomplete-patterns.sh

incomplete_patterns() { sh "$HERE/incomplete-patterns.sh" "$@"; }
: >"$WORK/in"
run incomplete_patterns "$HERE/../.."
expect "incomplete-patterns: the repository" 0
P=$WORK/patterns
mkdir -p "$P/modules/a" "$P/modules/b"
# cabal NAME TEXT: modules/NAME/NAME.cabal
cabal() { printf '%s' "$2" >"$P/modules/$1/$1.cabal"; }
COMMON_OK='common warnings
  ghc-options: -Wall -Werror=incomplete-patterns

library
  import:           warnings

test-suite a-test
  import:           warnings
  ghc-options: -threaded
'
cabal a "$COMMON_OK"
cabal b 'executable b
  ghc-options: -threaded -Wall -Werror=incomplete-patterns
'
run incomplete_patterns "$P"
expect "incomplete-patterns: through the common stanza or its own ghc-options" 0
cabal b 'common warnings
  ghc-options: -Wall

library
  import:           warnings
'
run incomplete_patterns "$P"
expect "incomplete-patterns: a common stanza without the flag" 1
if grep -qx 'modules/b/b.cabal: library' "$WORK/err"; then ok; else ng "incomplete-patterns: the component is named"; fi
cabal b 'common warnings
  ghc-options: -Wall -Werror=incomplete-patterns

library
  import:           warnings

executable b
  ghc-options: -Wall
'
run incomplete_patterns "$P"
expect "incomplete-patterns: a component that does not import the stanza" 1
if grep -qx 'modules/b/b.cabal: executable b' "$WORK/err" && ! grep -q 'library' "$WORK/err"; then ok; else ng "incomplete-patterns: only the component without the flag is named"; fi
rm "$P/modules/b/b.cabal"
run incomplete_patterns "$P"
expect "incomplete-patterns: a package without a .cabal file" 1

# ---------------------------------------------------------------- unsafe-io.sh

unsafe_io() { sh "$HERE/unsafe-io.sh" "$@"; }
: >"$WORK/in"
run unsafe_io "$HERE/../.."
expect "unsafe-io: the repository" 0
U=$WORK/unsafe
mkdir -p "$U/modules/x/src/X" "$U/scripts/ci"
printf 'modules/x/src/X/A.hs:kept # a reason\n' >"$U/scripts/ci/unsafe-io-allowed.txt"
cat >"$U/modules/x/src/X/A.hs" <<'EOF'
module X.A (kept, pure') where

import System.IO.Unsafe (unsafePerformIO)

-- | unsafePerformIO in a comment is not counted
kept :: Int -> Int
kept n = unsafePerformIO $ do
  pure n

pure' :: Int
pure' = 1 -- unsafePerformIO here neither
EOF
run unsafe_io "$U"
expect "unsafe-io: the allowed use, an import and comments" 0
cat >>"$U/modules/x/src/X/A.hs" <<'EOF'

added :: Int -> Int
added n =
  let k = unsafeDupablePerformIO (pure n)
   in k
EOF
run unsafe_io "$U"
expect "unsafe-io: a use not in the list" 1
if grep -q 'modules/x/src/X/A.hs:added' "$WORK/err"; then ok; else ng "unsafe-io: the new use is named"; fi
printf 'modules/x/src/X/A.hs:kept # a reason\nmodules/x/src/X/A.hs:added # another\nmodules/x/src/X/A.hs:gone # removed\n' >"$U/scripts/ci/unsafe-io-allowed.txt"
run unsafe_io "$U"
expect "unsafe-io: a listed use that is gone" 1
if grep -q 'modules/x/src/X/A.hs:gone' "$WORK/err"; then ok; else ng "unsafe-io: the gone use is named"; fi

# ---------------------------------------------------------------- rts-capabilities.sh

rts_capabilities() { sh "$HERE/rts-capabilities.sh" "$@"; }
: >"$WORK/in"
run rts_capabilities "$HERE/../.."
expect "rts-capabilities: the repository" 0
Q=$WORK/capabilities
mkdir -p "$Q/modules/a/test" "$Q/modules/b"
# qcabal NAME TEXT: modules/NAME/NAME.cabal
qcabal() { printf '%s' "$2" >"$Q/modules/$1/$1.cabal"; }
qcabal a 'common rts
  ghc-options: -threaded "-with-rtsopts=-N -A64m"

library

executable a
  ghc-options: -threaded "-with-rtsopts=-N"

test-suite a-test
  import:           rts

test-suite a-plain
  ghc-options: -Wall
'
qcabal b 'test-suite b-test
  ghc-options: -threaded -rtsopts -with-rtsopts=-N -Wall
'
printf 'main = getNumCapabilities >>= print\n' >"$Q/modules/a/test/Main.hs"
run rts_capabilities "$Q"
expect "rts-capabilities: -N in quotes, unquoted, through a common stanza; no -threaded" 0
qcabal b 'test-suite b-test
  ghc-options: -threaded "-with-rtsopts=-N8"

executable b
  ghc-options: -threaded
'
run rts_capabilities "$Q"
expect "rts-capabilities: -threaded without -N" 1
if grep -qx 'modules/b/b.cabal: test-suite b-test' "$WORK/err" && grep -qx 'modules/b/b.cabal: executable b' "$WORK/err" && ! grep -q 'modules/a' "$WORK/err"; then ok; else ng "rts-capabilities: the components without -N are named"; fi
qcabal b 'library
'
printf 'main = setNumCapabilities 8\n' >"$Q/modules/a/test/Main.hs"
run rts_capabilities "$Q"
expect "rts-capabilities: a call of setNumCapabilities" 1
if grep -qx 'modules/a/test/Main.hs:1' "$WORK/err"; then ok; else ng "rts-capabilities: the call is named by file and line"; fi

# ---------------------------------------------------------------- suite-timeout.sh

# GNU timeout is on the runners; macOS has none unless coreutils is installed
if command -v timeout >/dev/null 2>&1; then
  suite_timeout() { SUITE_TIMEOUT=1 sh "$HERE/suite-timeout.sh" "$@"; }
  : >"$WORK/in"
  run suite_timeout true
  expect "suite-timeout: a suite that passes" 0
  run suite_timeout sh -c 'exit 3'
  expect "suite-timeout: a suite that fails keeps its exit code" 3
  if [ ! -s "$WORK/err" ]; then ok; else ng "suite-timeout: nothing is said of a suite that finished"; fi
  run suite_timeout sleep 30
  expect "suite-timeout: a suite that does not finish is stopped" 124
  if grep -qx 'sleep: did not finish in 1 seconds' "$WORK/err"; then ok; else ng "suite-timeout: the suite that did not finish is named"; fi
fi

# ---------------------------------------------------------------- bg.sh
# (docs/adr/0037-ci-build-job-speedup.md)

export BG_DIR="$WORK/bg"
bg() { sh "$HERE/bg.sh" "$@"; }
: >"$WORK/in"
run bg start ok sh -c 'echo out; echo err >&2'
expect "bg: start" 0 ""
run bg wait ok
expect "bg: wait prints the output of the command" 0 "out
err"
run bg start three sh -c 'exit 3'
run bg wait three
expect "bg: wait exits with the code of the command" 3
run bg start slow sh -c 'sleep 1; echo done'
if [ "$CODE" = 0 ] && [ ! -f "$BG_DIR/slow.code" ]; then ok; else ng "bg: start returns while the command runs"; fi
run bg wait slow
expect "bg: wait waits for the command" 0 "done"
run bg start stdin cat
run bg wait stdin
expect "bg: the command reads no standard input" 0 ""
run bg wait never
expect "bg: wait for a name that was not started" 2
run bg start nothing
expect "bg: start without a command" 2
run bg start a/b true
expect "bg: a name with a slash" 2
run bg stop ok
expect "bg: an unknown subcommand" 2
unset BG_DIR

# ---------------------------------------------------------------- apt-install.sh

apt_install() { sh "$HERE/apt-install.sh" "$@"; }
: >"$WORK/in"
run apt_install
expect "apt-install: no package" 2

# ---------------------------------------------------------------- ci.yml and cabal
# (docs/adr/0037-ci-build-job-speedup.md)

# Every cabal command of the build job reads the same configuration: the
# test wrapper is in cabal.project.local, not on the command line of one
# command. A flag that changes the configuration of the local packages on
# one command (cabal test --test-wrapper, say) makes the next command
# configure them again, and golem-font compile HarfBuzz again.
CI_YML=$HERE/../../.github/workflows/ci.yml
if grep -nE '\bcabal +(build|test|run|install|list-bin)\b.*--(test-|benchmark-|enable-|disable-|ghc-options|constraint|flags|haddock-)' "$CI_YML" >"$WORK/out"; then
  ng "ci.yml: a cabal command sets the configuration on its command line"
else
  ok
fi
if grep -qE "test-wrapper: .*scripts/ci/suite-timeout\.sh.*cabal\.project\.local" "$CI_YML"; then ok; else ng "ci.yml: the test wrapper is written to cabal.project.local"; fi

# ---------------------------------------------------------------- ci.yml and the environment check
# (docs/adr/0038-env-determinism-quick-on-pull-requests.md)

# pull requests check the small inputs (--quick); pushes to main and the
# calls from release.yml check every input
if grep -qE 'scripts/env-determinism/check\.sh +\$QUICK *$' "$CI_YML"; then ok; else ng "ci.yml: check.sh takes the argument of the event"; fi
if grep -qF "QUICK: \${{ github.event_name == 'pull_request' && '--quick' || '' }}" "$CI_YML"; then ok; else ng "ci.yml: --quick on pull requests only"; fi

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

# ---------------------------------------------------------------- test-only-deps.sh

PLANS=$HERE/testdata/test-only-deps
test_only_deps() { sh "$HERE/test-only-deps.sh" "$@"; }

# deps NAME CODE PLAN [COMPONENT...]: the exit code, and the components
# named on stderr (exactly these, when the code is 1)
deps() {
  name=$1 code=$2 plan=$3
  shift 3
  : >"$WORK/in"
  run test_only_deps "$plan"
  if [ "$CODE" != "$code" ]; then
    ng "test-only-deps: $name (exit code $CODE, expected $code)"
    return 0
  fi
  if [ "$code" = 1 ]; then
    for c in "$@"; do
      if ! grep -qF " $c " "$WORK/err"; then
        ng "test-only-deps: $name ($c is not on stderr)"
        return 0
      fi
    done
    if [ "$(wc -l <"$WORK/err" | tr -d ' ')" != $# ]; then
      ng "test-only-deps: $name (stderr has not $# lines)"
      return 0
    fi
  fi
  ok
}

deps "only test suites depend" 0 "$PLANS/test-only.json"
deps "an executable depends directly" 1 "$PLANS/exe-direct.json" golem-cli:exe:golem
deps "an executable depends through a library" 1 "$PLANS/exe-transitive.json" golem-cli:exe:golem golem-driver:lib
deps "a library no executable uses depends" 1 "$PLANS/lib-only.json" golem-lsp:lib:golem-lsp-internal
deps "the lib of a per-package element depends" 1 "$PLANS/package-components.json" golem-custom:lib
deps "only through exe-depends and setup" 0 "$PLANS/exe-depends.json"
deps "a package that is not local depends" 0 "$PLANS/not-local.json"
deps "golem-test-support is not in the plan" 0 "$PLANS/absent.json"
deps "no such file" 2 "$WORK/no-such-plan.json"
printf 'not json\n' >"$WORK/bad.json"
deps "not JSON" 2 "$WORK/bad.json"
printf '{"cabal-version":"3.16.1.0"}\n' >"$WORK/no-plan.json"
deps "no install-plan" 2 "$WORK/no-plan.json"
: >"$WORK/in"
run test_only_deps
expect "test-only-deps: no argument" 2

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
