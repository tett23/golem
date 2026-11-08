#!/bin/sh
# Tests of the CI scripts (docs/adr/0009-ci-speed.md). The scripts-linux job of
# .github/workflows/ci.yml runs this, beside the changes job (docs/adr/0097).
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

# skip COUNT NAME: COUNT checks did not run; said on stderr and counted in
# the summary (docs/adr/0077)
SKIPPED=0
skip() {
  SKIPPED=$((SKIPPED + $1))
  printf 'SKIP %s %s\n' "$1" "$2" >&2
}

# fixture NAME CMD...: runs a command that builds the input of the tests.
# A failure stops the tests with its output: a broken fixture would make
# the later checks pass or fail for another reason (docs/adr/0077)
fixture() {
  name=$1
  shift
  # not in an if nor before || or &&, which would turn off set -e in CMD
  "$@" >"$WORK/fixture.log" 2>&1
  fixture_code=$?
  if [ "$fixture_code" != 0 ]; then
    printf 'FIXTURE FAILED: %s\n' "$name"
    sed 's/^/  /' "$WORK/fixture.log"
    exit 1
  fi
}

# git_repo DIR: a new repository at DIR on the branch main, which commits
# and tags as ci, without signing whatever the configuration of the user
git_repo() {
  mkdir -p "$1" &&
    git -C "$1" init -q -b main &&
    git -C "$1" config user.email ci@example.com &&
    git -C "$1" config user.name ci &&
    git -C "$1" config commit.gpgsign false &&
    git -C "$1" config tag.gpgsign false
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
# git_repo commits and tags even when the configuration of the user signs
# every commit and tag with a gpg that fails; a plain repository does not
# (docs/adr/0077)
printf '[commit]\n\tgpgsign = true\n[tag]\n\tgpgsign = true\n[gpg]\n\tprogram = false\n' >"$WORK/signing.gitconfig"
# signed_commit DIR INIT...: INIT makes a repository at DIR, then a commit
# and an annotated tag, with the configuration that signs
signed_commit() (
  dir=$1
  shift
  GIT_CONFIG_GLOBAL=$WORK/signing.gitconfig
  export GIT_CONFIG_GLOBAL
  "$@" "$dir" && echo a >"$dir/a" && git -C "$dir" add a &&
    git -C "$dir" -c user.email=ci@example.com -c user.name=ci commit -q -m a &&
    git -C "$dir" -c user.email=ci@example.com -c user.name=ci tag -a -m t v1
) >/dev/null 2>&1
plain_repo() { mkdir -p "$1" && git -C "$1" init -q -b main; }
if signed_commit "$WORK/signing-plain" plain_repo; then ng "git_repo: the configuration that signs breaks a plain repository"; else ok; fi
if signed_commit "$WORK/signing-fixture" git_repo; then ok; else ng "git_repo: a fixture commits and tags without signing"; fi

G=$WORK/git
changed_paths_repo() (
  set -e
  git_repo "$G"
  cd "$G"
  echo a >a.hs && git add a.hs && git commit -q -m a
  git checkout -q -b topic
  mkdir -p docs && echo x >docs/x.md && echo s >"docs/a b.md" && echo j >docs/日本語.md
  git add docs && git commit -q -m x
  git checkout -q main
  echo b >b.hs && git add b.hs && git commit -q -m b
  # a move of a module file into docs/, with rename detection on as git
  # has it by default (docs/adr/0070)
  git checkout -q -b moved
  git config diff.renames true
  mkdir -p docs && git mv a.hs docs/moved.md && git commit -q -m moved
  git checkout -q main
)
fixture "the repository of changed-paths.sh" changed_paths_repo
MAIN=$(git -C "$G" rev-parse main)
MAIN1=$(git -C "$G" rev-parse main~1)
TOPIC=$(git -C "$G" rev-parse topic)
MOVED=$(git -C "$G" rev-parse moved)
: >"$WORK/in"
in_g() { (cd "$G" && changed_paths "$@"); }
run in_g pull_request "$MAIN" "$TOPIC"
expect "changed-paths: a pull request from the merge base" 0 "docs/a b.md
docs/x.md
docs/日本語.md"
run in_g push "$MAIN1" "$MAIN"
expect "changed-paths: a push" 0 "b.hs"
run in_g push "$MAIN" "$MOVED"
expect "changed-paths: a move is the path it left and the path it took (docs/adr/0070)" 0 "a.hs
docs/moved.md"
cp "$WORK/out" "$WORK/in"
run needs_build
expect "changed-paths: a module file moved into docs/ needs the build (docs/adr/0070)" 0 true
: >"$WORK/in"
run in_g push 0000000000000000000000000000000000000000 "$MAIN"
expect "changed-paths: a push that creates the branch" 3 ""
run in_g push "" "$MAIN"
expect "changed-paths: a push without before" 3 ""
run in_g workflow_dispatch
expect "changed-paths: workflow_dispatch" 3 ""
run in_g pull_request 1234567890123456789012345678901234567890 "$TOPIC"
if [ "$CODE" != 0 ] && [ "$CODE" != 3 ]; then ok; else ng "changed-paths: a commit that does not exist (exit code $CODE)"; fi

# ---------------------------------------------------------------- abi-version.sh
# (docs/adr/0052-plugin-abi-version-bump-rule.md)

AV=$WORK/abi
# abi_repo: a repository with the three files at ABI 1, tagged v0.0.1
# abi_git ARG...: git in $AV, as a fixture
abi_git() { fixture "abi-version: git $*" git -C "$AV" "$@"; }
abi_repo() {
  rm -rf "$AV"
  fixture "abi-version: the repository" git_repo "$AV"
  mkdir -p "$AV/modules/golem-doc/schema" "$AV/modules/golem-doc/src/Golem/Doc"
  printf '; the IR\ndocument = { version: uint }\n' >"$AV/modules/golem-doc/schema/golem-doc.cddl"
  printf -- '-- | The checks\nmodule Golem.Doc.Validate where\n\n{- | a block\ncomment -}\ncheck :: Int -> Bool\ncheck n = n > 0 -- positive\n' >"$AV/modules/golem-doc/src/Golem/Doc/Validate.hs"
  printf 'module Golem.Doc.IR where\n\nabiVersion :: Int\nabiVersion = 1\n' >"$AV/modules/golem-doc/src/Golem/Doc/IR.hs"
  abi_git add .
  abi_git commit -q -m release
  abi_git tag v0.0.1
}
# abi_change NAME CODE [STDERR-WORD...]: commits the changes made in $AV, then runs the script
abi_change() {
  # not name: fixture sets it
  abi_name=$1 abi_code=$2
  shift 2
  abi_git add -A
  abi_git commit -q --allow-empty -m change
  : >"$WORK/in"
  run env GOLEM_ROOT="$AV" sh "$HERE/abi-version.sh"
  expect "abi-version: $abi_name" "$abi_code"
  for w in "$@"; do
    if grep -qF -- "$w" "$WORK/err"; then ok; else ng "abi-version: $abi_name: \"$w\" on stderr"; fi
  done
}
abi_cddl() { printf "$1" >"$AV/modules/golem-doc/schema/golem-doc.cddl"; }
abi_validate() { printf -- "$1" >"$AV/modules/golem-doc/src/Golem/Doc/Validate.hs"; }
abi_set() { sed "s/^abiVersion = .*/abiVersion = $1/" "$AV/modules/golem-doc/src/Golem/Doc/IR.hs" >"$AV/ir" && mv "$AV/ir" "$AV/modules/golem-doc/src/Golem/Doc/IR.hs"; }
abi_repo
abi_change "nothing changed" 0
abi_repo
abi_cddl '; the IR, commented again\ndocument = {  version: uint }\n'
abi_change "a comment of the CDDL" 0
abi_repo
abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
abi_set 2
abi_change "a rule of the CDDL and one more version" 0
abi_repo
abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
abi_change "a rule of the CDDL without a new version" 1 "1" "golem-doc.cddl"
abi_repo
abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
abi_set 3
abi_change "a rule of the CDDL and two more versions" 1 "3"
abi_repo
abi_set 2
abi_change "a new version without a change" 1 "2"
abi_repo
abi_validate '-- | The checks\nmodule Golem.Doc.Validate where\n\n{- | a block\ncomment -}\ncheck :: Int -> Bool\ncheck n = n >= 0 -- positive\n'
abi_change "a check of Validate.hs without a new version" 1 "Validate.hs"
abi_repo
abi_validate '-- | The checks, again\nmodule Golem.Doc.Validate where\n\n{- | another\nblock {- nested -} comment -}\ncheck :: Int -> Bool\ncheck n = n > 0 -- strictly positive\n'
abi_change "a comment of Validate.hs" 0
abi_repo
abi_validate "-- | The checks\nmodule Golem.Doc.Validate where\n\n{- | a block\ncomment -}\ncheck :: Int -> Bool\ncheck n = n > 0 -- positive\nq = ('\"', \"a -- b\") -- one\n"
abi_git add -A
abi_git commit -q -m q
abi_git tag -f v0.0.1
abi_validate "-- | The checks\nmodule Golem.Doc.Validate where\n\n{- | a block\ncomment -}\ncheck :: Int -> Bool\ncheck n = n > 0 -- positive\nq = ('\"', \"a -- b\") -- two\n"
abi_change "a comment after a character and a string with dashes" 0
abi_validate "-- | The checks\nmodule Golem.Doc.Validate where\n\n{- | a block\ncomment -}\ncheck :: Int -> Bool\ncheck n = n > 0 -- positive\nq = ('\"', \"a -- c\") -- two\n"
abi_change "dashes in a string are not a comment" 1 "Validate.hs"
abi_repo
abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
abi_validate '-- | The checks\nmodule Golem.Doc.Validate where\n\ncheck :: Int -> Bool\ncheck n = n >= 0\n'
abi_set 2
abi_change "the CDDL and Validate.hs and one more version" 0
abi_repo
abi_git rm -q modules/golem-doc/src/Golem/Doc/Validate.hs
abi_git commit -q -m gone
abi_git tag -d v0.0.1
abi_git tag v0.0.1
abi_validate '-- | The checks\nmodule Golem.Doc.Validate where\n'
abi_change "Validate.hs missing from the release" 1 "Validate.hs"
abi_repo
abi_git tag -d v0.0.1
abi_change "no release tag" 0
if grep -q 'no release' "$WORK/out" "$WORK/err"; then ok; else ng "abi-version: no release tag: says the check is skipped"; fi

# From v1.0.0 on (docs/adr/0174-compatibility-promises-for-1-0.md): a
# minor version changes the ABI only after the last release announced it in
# docs/compatibility.md, a patch version never changes it, and a major
# version follows the rule of one more per release
# abi_v1 [HEADING...]: the repository tagged v1.0.0 with VERSION 1.0.0 and
# docs/compatibility.md that has the headings
abi_v1() {
  rm -rf "$AV"
  fixture "abi-version: the repository" git_repo "$AV"
  mkdir -p "$AV/modules/golem-doc/schema" "$AV/modules/golem-doc/src/Golem/Doc" "$AV/docs"
  printf '; the IR\ndocument = { version: uint }\n' >"$AV/modules/golem-doc/schema/golem-doc.cddl"
  printf -- 'module Golem.Doc.Validate where\n' >"$AV/modules/golem-doc/src/Golem/Doc/Validate.hs"
  printf 'module Golem.Doc.IR where\n\nabiVersion :: Int\nabiVersion = 8\n' >"$AV/modules/golem-doc/src/Golem/Doc/IR.hs"
  printf '1.0.0\n' >"$AV/VERSION"
  printf '# 互換性\n\n## 予告している ABI の変更\n\n' >"$AV/docs/compatibility.md"
  for h in "$@"; do printf '%s\n\n本文\n\n' "$h" >>"$AV/docs/compatibility.md"; done
  abi_git add .
  abi_git commit -q -m release
  abi_git tag v1.0.0
}
abi_version() { printf '%s\n' "$1" >"$AV/VERSION"; }
abi_new_abi() {
  abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
  abi_set 9
}
abi_v1
abi_version 1.1.0
abi_new_abi
abi_change "1.1.0: a new ABI that v1.0.0 did not announce" 1 "9" "docs/compatibility.md"
abi_v1 '### ABI のバージョン 10'
abi_version 1.1.0
abi_new_abi
abi_change "1.1.0: a new ABI that v1.0.0 announced under another number" 1 "9"
abi_v1 '### ABI のバージョン 9'
abi_version 1.1.0
abi_new_abi
abi_change "1.1.0: a new ABI that v1.0.0 announced" 0
abi_v1
abi_version 1.1.0
abi_change "1.1.0: the same ABI" 0
abi_v1 '### ABI のバージョン 9'
abi_version 1.0.1
abi_new_abi
abi_change "1.0.1: a new ABI, announced" 1 "patch"
abi_v1
abi_version 1.0.1
abi_change "1.0.1: the same ABI" 0
abi_v1
abi_version 2.0.0
abi_new_abi
abi_change "2.0.0: a new ABI, not announced" 0
abi_v1
abi_version 2.0.0
abi_cddl '; the IR\ndocument = { version: uint, title: tstr }\n'
abi_change "2.0.0: a new ABI without a new version" 1 "9"
# a prerelease of 1.0.0 comes before 1.0.0: the rule of one more per release
abi_v1
abi_git tag -d v1.0.0
abi_git tag v1.0.0-rc1
abi_version 1.0.0
abi_new_abi
abi_change "after v1.0.0-rc1: a new ABI, not announced" 0
# the patch rule of docs/adr/0212: X.Y.Z is a patch when X and Z are 1 or
# more, and its base is the latest release of X.Y that is not a prerelease
abi_v1 '### ABI のバージョン 9'
abi_git tag -d v1.0.0
abi_git tag v1.1.0-rc1
abi_version 1.1.0
abi_new_abi
abi_change "after v1.1.0-rc1: 1.1.0 with a new ABI that v1.1.0-rc1 announced" 0
abi_v1
abi_git tag -d v1.0.0
abi_git tag v1.1.0-rc1
abi_version 1.1.0
abi_new_abi
abi_change "after v1.1.0-rc1: 1.1.0 with a new ABI that v1.1.0-rc1 did not announce" 1 "docs/compatibility.md"
abi_v1
abi_git tag v1.0.1-rc1
abi_version 1.0.1
abi_change "after v1.0.0 and v1.0.1-rc1: 1.0.1 with the same ABI" 0
abi_v1
abi_git tag -d v1.0.0
abi_git tag v1.0.1-rc1
abi_version 1.0.1
abi_change "after v1.0.1-rc1 only: the patch 1.0.1 has no base" 1 "1.0.1"
abi_v1
abi_version 1.0.1-rc1
abi_new_abi
abi_change "1.0.1-rc1: a prerelease of a patch keeps the ABI" 1 "patch"

# ---------------------------------------------------------------- diagnostic-codes.sh
# (docs/adr/0174-compatibility-promises-for-1-0.md)

DC=$WORK/codes
dc_git() { fixture "diagnostic-codes: git $*" git -C "$DC" "$@"; }
# dc_section CODE SEVERITY STATE: one section of docs/diagnostics.md
dc_section() {
  printf '## %s\n\n題。\n\n- 重大度: %s\n- 状態: %s\n\n### 意味\n\n意味。\n\n' "$1" "$2" "$3"
}
# dc_doc: docs/diagnostics.md of the release
dc_doc() {
  {
    printf '# diagnostic のコード\n\n## 節の形\n\n- **重大度**：`- 重大度:` の行。\n\n'
    dc_section E01100 エラー 使用中
    dc_section E02109 お知らせ 使用中
    dc_section G01001 エラー 使用中
    dc_section G02065 お知らせ 使用中
    dc_section G02070 警告 使用中
    dc_section G02071 警告 使用中
    dc_section G02072 情報 使用中
    dc_section G03010 'dev では警告、prod ではエラー' 使用中
    dc_section G04001 エラー 廃止
    dc_section G09002 'プリフライトの設定による（print の既定は警告、3mm）' 使用中
    dc_section G09003 'プリフライトの設定による（print の既定は off）' 使用中
  } >"$DC/docs/diagnostics.md"
}
# dc_repo TAG VERSION: the repository tagged TAG, with VERSION
dc_repo() {
  rm -rf "$DC"
  fixture "diagnostic-codes: the repository" git_repo "$DC"
  mkdir -p "$DC/docs"
  dc_doc
  printf '%s\n' "$2" >"$DC/VERSION"
  dc_git add .
  dc_git commit -q -m release
  dc_git tag "$1"
}
# dc_set CODE SEVERITY STATE: rewrites the lines of the section of CODE
dc_set() {
  awk -v code="$1" -v sev="$2" -v state="$3" '
    /^## / { cur = substr($0, 4) }
    cur == code && /^- 重大度: / { print "- 重大度: " sev; next }
    cur == code && /^- 状態: / { print "- 状態: " state; next }
    { print }
  ' "$DC/docs/diagnostics.md" >"$DC/d" && mv "$DC/d" "$DC/docs/diagnostics.md"
}
dc_version() { printf '%s\n' "$1" >"$DC/VERSION"; }
# dc_check NAME CODE [STDERR-WORD...]: commits the changes made in $DC, then runs the script
dc_check() {
  dc_name=$1 dc_code=$2
  shift 2
  dc_git add -A
  dc_git commit -q --allow-empty -m change
  : >"$WORK/in"
  run env GOLEM_ROOT="$DC" sh "$HERE/diagnostic-codes.sh"
  expect "diagnostic-codes: $dc_name" "$dc_code"
  for w in "$@"; do
    if grep -qF -- "$w" "$WORK/err"; then ok; else ng "diagnostic-codes: $dc_name: \"$w\" on stderr"; fi
  done
}
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_check "nothing changed" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02065 お知らせ 廃止
dc_check "a G code in use made obsolete" 1 G02065
dc_repo v1.0.0 1.0.0
dc_version 1.0.1
awk '/^## G02070$/ { skip = 1 } /^## G02071$/ { skip = 0 } !skip' "$DC/docs/diagnostics.md" >"$DC/d" && mv "$DC/d" "$DC/docs/diagnostics.md"
dc_check "a G code in use removed" 1 G02070
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02065 警告 使用中
dc_check "a notice made a warning" 1 G02065
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02070 エラー 使用中
dc_check "a warning made an error" 1 G02070
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02070 'dev では警告、prod ではエラー' 使用中
dc_check "a warning made an error in prod" 1 G02070
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02072 お知らせ 使用中
dc_check "an info made a notice" 1 G02072
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G03010 エラー 使用中
dc_check "an error in prod made an error" 1 G03010
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G09002 'プリフライトの設定による（print の既定はエラー、3mm）' 使用中
dc_check "a preflight code whose print default is made an error" 1 G09002
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G09003 'プリフライトの設定による（print の既定は警告）' 使用中
dc_check "a preflight code whose print default off is made a warning" 1 G09003
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G09002 'プリフライトの設定による（print の既定は警告、5mm）' 使用中
dc_check "a preflight code with another value of print" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G01001 警告 使用中
dc_set G02070 お知らせ 使用中
dc_set G03010 警告 使用中
dc_check "severities lowered" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set E01100 エラー 廃止
dc_set E02109 エラー 使用中
dc_check "E codes made obsolete and raised" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_section G02200 エラー 使用中 >>"$DC/docs/diagnostics.md"
dc_check "a code added" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G04001 エラー 使用中
dc_check "an obsolete code of the release" 0
dc_repo v1.0.0 1.0.0
dc_version 2.0.0
dc_set G02065 お知らせ 廃止
dc_set G02070 エラー 使用中
dc_check "a major version" 0
dc_repo v1.1.0 1.1.0
dc_version 1.2.0-rc1
dc_set G02070 エラー 使用中
dc_check "after the release v1.1.0" 1 G02070
dc_repo v0.1.0-rc3 0.1.0-rc3
dc_version 0.1.0-rc4
dc_set G02065 お知らせ 廃止
dc_set G02070 エラー 使用中
dc_check "before v1.0.0" 0
dc_repo v1.0.0-rc1 1.0.0-rc1
dc_version 1.0.0
dc_set G02070 エラー 使用中
dc_check "after a prerelease of 1.0.0" 0
dc_repo v1.0.0 1.0.0
dc_git tag -d v1.0.0
dc_version 1.1.0
dc_set G02070 エラー 使用中
dc_check "no release" 0
dc_repo v1.0.0 1.0.0
dc_version 1.1.0
dc_set G02070 致命的 使用中
dc_check "a severity it does not know" 1 G02070
run env GOLEM_ROOT="$HERE/../.." sh "$HERE/diagnostic-codes.sh"
expect "diagnostic-codes: the repository" 0

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
# a path built from "docs" needs the annotation (docs/adr/0069)
printf 'main = readFile ("../.." </> "docs" </> "new.md")\n' >"$R/modules/x/test/Main.hs"
run docs_refs "$R"
expect "docs-refs: a path built from \"docs\" without the annotation" 1
if grep -qF 'modules/x/test/Main.hs:1' "$WORK/err"; then ok; else ng "docs-refs: the line without the annotation is named"; fi
printf 'main = readFile ("../.." </> "docs" </> "new.md") -- docs-refs: docs/new.md\n' >"$R/modules/x/test/Main.hs"
run docs_refs "$R"
expect "docs-refs: the annotation names a document that is not in the list" 1
if grep -q 'docs/new.md' "$WORK/err"; then ok; else ng "docs-refs: the annotated document is named"; fi
printf 'main = readFile ("../.." </> "docs" </> "diagnostics.md") -- docs-refs: docs/diagnostics.md\n' >"$R/modules/x/test/Main.hs"
run docs_refs "$R"
expect "docs-refs: the annotation names a listed document" 0
printf 'd="docs"\n' >"$R/scripts/a.sh"
run docs_refs "$R"
expect "docs-refs: \"docs\" in a script without the annotation" 1
rm "$R/scripts/a.sh"

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
# the forms that slipped past the check (docs/adr/0069)
# ip_case NAME CODE TEXT [LINE]: modules/b/b.cabal is TEXT; with LINE,
# stderr has it
ip_case() {
  cabal b "$3"
  run incomplete_patterns "$P"
  expect "incomplete-patterns: $1" "$2"
  if [ $# -ge 4 ]; then
    if grep -qxF "$4" "$WORK/err"; then ok; else ng "incomplete-patterns: $1: \"$4\" on stderr"; fi
  fi
}
for neg in -Wno-error=incomplete-patterns -Wno-incomplete-patterns -Wwarn=incomplete-patterns; do
  ip_case "the flag, then $neg" 1 "library
  ghc-options: -Werror=incomplete-patterns $neg
" "modules/b/b.cabal: library"
done
ip_case "the flag in the common stanza, a negation in the component" 1 'common warnings
  ghc-options: -Werror=incomplete-patterns

library
  import: warnings
  ghc-options: -Wno-error=incomplete-patterns
' "modules/b/b.cabal: library"
ip_case "the flag after a negation" 0 'library
  ghc-options: -Wno-incomplete-patterns -Werror=incomplete-patterns
'
ip_case "the flag on the line after ghc-options" 0 'Common warnings
  GHC-Options:
    -Wall
    -Werror=incomplete-patterns

Library
  Import: warnings

executable b
  ghc-options:
    -Werror=incomplete-patterns
    -threaded
'
ip_case "a negation on the line after ghc-options" 1 'library
  ghc-options: -Werror=incomplete-patterns
    -Wno-error=incomplete-patterns
' "modules/b/b.cabal: library"
ip_case "a section name in capitals" 1 'Executable b
  ghc-options: -Wall
' "modules/b/b.cabal: Executable b"
cabal b "$COMMON_OK"
mkdir -p "$P/modules/b/src"
printf '{-# OPTIONS_GHC -Wall -Wno-incomplete-patterns #-}\nmodule B where\n' >"$P/modules/b/src/B.hs"
run incomplete_patterns "$P"
expect "incomplete-patterns: OPTIONS_GHC with a negation in a source" 1
if grep -qxF 'modules/b/src/B.hs:1' "$WORK/err"; then ok; else ng "incomplete-patterns: the source is named by file and line"; fi
printf 'module B where\n\n{-# options_ghc\n      -Wwarn=incomplete-patterns #-}\n' >"$P/modules/b/src/B.hs"
run incomplete_patterns "$P"
expect "incomplete-patterns: a pragma over two lines in lower case" 1
printf -- '-- {-# OPTIONS_GHC -Wno-incomplete-patterns #-} is not written\n{-# OPTIONS_GHC -Wall #-}\nmodule B where\n' >"$P/modules/b/src/B.hs"
run incomplete_patterns "$P"
expect "incomplete-patterns: OPTIONS_GHC without a negation, and one in a comment" 0
rm -r "$P/modules/b/src"
printf 'packages: modules/*/*.cabal\n\npackage *\n  ghc-options: -Wno-error=incomplete-patterns\n' >"$P/cabal.project"
run incomplete_patterns "$P"
expect "incomplete-patterns: package * of cabal.project takes the flag back" 1
if grep -qxF 'cabal.project: package *' "$WORK/err"; then ok; else ng "incomplete-patterns: the section of cabal.project is named"; fi
printf 'packages: modules/*/*.cabal\n\npackage *\n  ghc-options: -Wall\n' >"$P/cabal.project"
printf 'Package golem-b\n  GHC-Options:\n    -Wno-incomplete-patterns\n' >"$P/cabal.project.local"
run incomplete_patterns "$P"
expect "incomplete-patterns: cabal.project.local takes the flag back" 1
if grep -qxF 'cabal.project.local: Package golem-b' "$WORK/err"; then ok; else ng "incomplete-patterns: the section of cabal.project.local is named"; fi
rm "$P/cabal.project" "$P/cabal.project.local"
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
# unsafe_case NAME USE TEXT: A.hs is the allowed kept, then TEXT; the
# script fails and names USE (docs/adr/0069)
unsafe_case() {
  printf 'modules/x/src/X/A.hs:kept # a reason\n' >"$U/scripts/ci/unsafe-io-allowed.txt"
  printf 'module X.A (kept) where\n\nkept :: Int -> Int\nkept n = unsafePerformIO (pure n)\n%s\n' "$3" >"$U/modules/x/src/X/A.hs"
  run unsafe_io "$U"
  expect "unsafe-io: $1" 1
  if grep -qxF "unsafe-io: not in scripts/ci/unsafe-io-allowed.txt: modules/x/src/X/A.hs:$2" "$WORK/err"; then ok; else ng "unsafe-io: $1: $2 is named"; fi
}
for name in unsafeInterleaveIO unsafeInterleaveST unsafeIOToST inlinePerformIO accursedUnutterablePerformIO; do
  unsafe_case "$name" other "other :: Int
other = $name x"
done
unsafe_case "a use after dashes in a string" other 'other :: Int
other = let _ = "--" in unsafePerformIO x'
unsafe_case "a use after an opening of a block comment in a string" other 'other :: Int
other = let _ = "{-" in unsafePerformIO x'
unsafe_case "a use after an escaped quote in a string" other 'other = let _ = "\"--" in unsafePerformIO x'
unsafe_case "a use after a quote in a character" other "other = let _ = ('\"', '-') in unsafePerformIO x"
unsafe_case "a quoted name" other "other = \$(varE 'unsafePerformIO)"
unsafe_case "a use after an operator of dashes" other 'other = a --> unsafePerformIO x'
unsafe_case "a use in an instance right after the allowed function" "instance Show T" 'instance Show T where show _ = unsafePerformIO x'
unsafe_case "a use in the body of an instance" "instance Show T" 'instance Show T where
  show _ = unsafePerformIO x'
# the cases that are not uses: a string with the name, a character, a
# primed name, a block comment opened in a string and closed later
printf 'modules/x/src/X/A.hs:kept # a reason\n' >"$U/scripts/ci/unsafe-io-allowed.txt"
cat >"$U/modules/x/src/X/A.hs" <<'EOF'
module X.A (kept) where

kept :: Int -> Int
kept n = unsafePerformIO (pure n)

other :: String
other = "unsafePerformIO" ++ ['\'', '"'] ++ "a \"{- b" ++ unsafePerformIO' ++ x'unsafePerformIO -- "
{- "unsafePerformIO -}
EOF
run unsafe_io "$U"
expect "unsafe-io: the name in a string, characters, primed names" 0

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
# the forms that slipped past the check (docs/adr/0069); cabal 3.18.1 reads
# a field on the lines after its name and the names of sections and fields
# in any case, and GHC 9.10.3 keeps the last -with-rtsopts only
printf 'main = pure ()\n' >"$Q/modules/a/test/Main.hs"
qcabal a 'library
'
# rts_case NAME CODE TEXT [COMPONENT]: modules/b/b.cabal is TEXT; with
# COMPONENT, stderr names it
rts_case() {
  qcabal b "$3"
  run rts_capabilities "$Q"
  expect "rts-capabilities: $1" "$2"
  if [ $# -ge 4 ]; then
    if grep -qxF "modules/b/b.cabal: $4" "$WORK/err"; then ok; else ng "rts-capabilities: $1: $4 is named"; fi
  fi
}
rts_case "-threaded on the line after ghc-options" 1 'executable b
  ghc-options:
    -Wall
    -threaded
' "executable b"
rts_case "a section name in capitals" 1 'Executable b
  ghc-options: -threaded
' "Executable b"
rts_case "a field name in capitals" 1 'executable b
  GHC-Options: -threaded
' "executable b"
rts_case "-N in the first -with-rtsopts, not in the last" 1 'executable b
  ghc-options: -threaded "-with-rtsopts=-N" "-with-rtsopts=-A64m"
' "executable b"
rts_case "-N in the first ghc-options, not in the last" 1 'executable b
  ghc-options: -threaded "-with-rtsopts=-N"
  ghc-options: "-with-rtsopts=-A64m"
' "executable b"
rts_case "-N in the common stanza, replaced by the component" 1 'common rts
  ghc-options: -threaded "-with-rtsopts=-N"

executable b
  import: rts
  ghc-options: "-with-rtsopts=-A64m"
' "executable b"
rts_case "-threaded only in a common stanza" 1 'common rts
  ghc-options: -threaded

test-suite b-test
  import: rts
' "test-suite b-test"
rts_case "-threaded and -N on the lines after ghc-options" 0 'common rts
  ghc-options:
    -threaded
    "-with-rtsopts=-N"

executable b
  ghc-options:
    -threaded
    "-with-rtsopts=-A64m" "-with-rtsopts=-N -A64m"

Test-Suite b-test
  Import: rts
'

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
else
  skip 4 "suite-timeout (no timeout command)"
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
run bg start .hidden true
expect "bg: a name that starts with a dot" 2
run bg start "" true
expect "bg: an empty name" 2
run bg wait ok extra
expect "bg: wait with more than a name" 2
# a name started again: wait waits for the new command, not the code of the old one
run bg start again sh -c 'exit 3'
run bg wait again
run bg start again sh -c 'sleep 1; echo second'
run bg wait again
expect "bg: a name started again is waited for anew" 0 "second"
unset BG_DIR

# ---------------------------------------------------------------- apt-install.sh

apt_install() { sh "$HERE/apt-install.sh" "$@"; }
: >"$WORK/in"
run apt_install
expect "apt-install: no package" 2
# a fake sudo on PATH records each command and what it read; FAIL_ON makes that command fail
mkdir -p "$WORK/fakebin"
cat >"$WORK/fakebin/sudo" <<'FAKE'
#!/bin/sh
case "$1" in debconf-set-selections) printf '%s: %s\n' "$*" "$(cat)" ;; *) printf '%s\n' "$*" ;; esac >>"$SUDO_LOG"
[ "$*" != "${FAIL_ON-}" ]
FAKE
chmod +x "$WORK/fakebin/sudo"
export SUDO_LOG="$WORK/sudo.log"
: >"$SUDO_LOG"
run env PATH="$WORK/fakebin:$PATH" sh "$HERE/apt-install.sh" qpdf epubcheck
expect "apt-install: installs the packages" 0
if [ "$(cat "$SUDO_LOG")" = "debconf-set-selections: man-db man-db/auto-update boolean false
apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=3 update
apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=3 install -y --no-install-recommends qpdf epubcheck" ]; then ok; else
  ng "apt-install: man-db is not updated, then update, then install without recommends, each with a timeout of 30 seconds and 3 retries"
  sed 's/^/  sudo: /' "$SUDO_LOG"
fi
: >"$SUDO_LOG"
run env PATH="$WORK/fakebin:$PATH" FAIL_ON="apt-get -o Acquire::http::Timeout=30 -o Acquire::Retries=3 update" sh "$HERE/apt-install.sh" qpdf
expect "apt-install: a failed update fails" 1
if ! grep -q 'apt-get install' "$SUDO_LOG"; then ok; else ng "apt-install: nothing is installed after a failed update"; fi
unset SUDO_LOG

# ---------------------------------------------------------------- epubcheck-install.sh
# (docs/adr/0062-epubcheck-from-release-with-cache.md)

# a fake release zip with the layout of epubcheck-VERSION.zip; a fake curl
# on PATH records its arguments and writes the zip to the file of -o; a fake
# Java prints its arguments
EC=$WORK/epubcheck
mkdir -p "$EC/src/epubcheck-9.9.9/lib" "$EC/fakebin" "$EC/java/bin"
printf 'jar\n' >"$EC/src/epubcheck-9.9.9/epubcheck.jar"
(cd "$EC/src" && zip -qr "$EC/release.zip" epubcheck-9.9.9)
if command -v sha256sum >/dev/null 2>&1; then
  EC_SHA=$(sha256sum "$EC/release.zip" | cut -d' ' -f1)
else
  EC_SHA=$(shasum -a 256 "$EC/release.zip" | cut -d' ' -f1)
fi
EC_BAD=0000000000000000000000000000000000000000000000000000000000000000
cat >"$EC/fakebin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$CURL_LOG"
while [ $# -gt 0 ]; do
  case "$1" in -o) cp "$CURL_ZIP" "$2" || exit 22; shift ;; esac
  shift
done
FAKE
cat >"$EC/java/bin/java" <<'FAKE'
#!/bin/sh
printf 'java %s\n' "$*"
FAKE
chmod +x "$EC/fakebin/curl" "$EC/java/bin/java"
export CURL_LOG="$EC/curl.log" CURL_ZIP="$EC/release.zip"
# epubcheck_install HOME VERSION SHA: runs the script with the fakes
epubcheck_install() {
  env PATH="$EC/fakebin:$PATH" EPUBCHECK_HOME="$1" JAVA_HOME_17_X64="$EC/java" sh "$HERE/epubcheck-install.sh" "$2" "$3"
}
: >"$WORK/in"
run sh "$HERE/epubcheck-install.sh"
expect "epubcheck-install: no argument" 2
run sh "$HERE/epubcheck-install.sh" 9.9.9
expect "epubcheck-install: no SHA-256" 2
# no cache: the zip is fetched from the release of w3c/epubcheck
: >"$CURL_LOG"
run epubcheck_install "$EC/h1" 9.9.9 "$EC_SHA"
expect "epubcheck-install: a zip of the right SHA-256 is installed" 0
if grep -qF "https://github.com/w3c/epubcheck/releases/download/v9.9.9/epubcheck-9.9.9.zip" "$CURL_LOG"; then ok; else ng "epubcheck-install: the zip is fetched from the release of w3c/epubcheck"; fi
if [ -f "$EC/h1/zip/epubcheck-9.9.9.zip" ]; then ok; else ng "epubcheck-install: the zip is kept for the cache"; fi
CODE=0
"$EC/h1/bin/epubcheck" book.epub >"$WORK/out" 2>"$WORK/err" || CODE=$?
expect "epubcheck-install: epubcheck runs the jar with the Java of JAVA_HOME_17_X64" 0 "java -jar $EC/h1/epubcheck-9.9.9/epubcheck.jar book.epub"
# a wrong SHA-256 fails, and nothing is installed nor cached
: >"$CURL_LOG"
run epubcheck_install "$EC/h2" 9.9.9 "$EC_BAD"
expect "epubcheck-install: a zip of a wrong SHA-256 fails" 1
if [ ! -e "$EC/h2/bin/epubcheck" ] && [ ! -e "$EC/h2/zip/epubcheck-9.9.9.zip" ]; then ok; else ng "epubcheck-install: nothing is installed nor cached from a zip of a wrong SHA-256"; fi
# a cached zip: curl is not called
mkdir -p "$EC/h3/zip"
cp "$EC/release.zip" "$EC/h3/zip/epubcheck-9.9.9.zip"
: >"$CURL_LOG"
run epubcheck_install "$EC/h3" 9.9.9 "$EC_SHA"
expect "epubcheck-install: a cached zip is installed" 0
if [ ! -s "$CURL_LOG" ]; then ok; else ng "epubcheck-install: a cached zip is not fetched again"; fi
if [ -x "$EC/h3/bin/epubcheck" ]; then ok; else ng "epubcheck-install: epubcheck is installed from the cached zip"; fi
# a cached zip of a wrong SHA-256 fails
mkdir -p "$EC/h4/zip"
printf 'not a zip\n' >"$EC/h4/zip/epubcheck-9.9.9.zip"
run epubcheck_install "$EC/h4" 9.9.9 "$EC_SHA"
expect "epubcheck-install: a cached zip of a wrong SHA-256 fails" 1
if [ ! -e "$EC/h4/bin/epubcheck" ]; then ok; else ng "epubcheck-install: nothing is installed from a cached zip of a wrong SHA-256"; fi
# a failed download fails
run env PATH="$EC/fakebin:$PATH" CURL_ZIP="$EC/no-such.zip" EPUBCHECK_HOME="$EC/h5" JAVA_HOME_17_X64="$EC/java" sh "$HERE/epubcheck-install.sh" 9.9.9 "$EC_SHA"
if [ "$CODE" != 0 ] && [ ! -e "$EC/h5/bin/epubcheck" ]; then ok; else ng "epubcheck-install: a failed download fails"; fi
# no Java at JAVA_HOME_17_X64
run env PATH="$EC/fakebin:$PATH" EPUBCHECK_HOME="$EC/h6" JAVA_HOME_17_X64="$EC/no-java" sh "$HERE/epubcheck-install.sh" 9.9.9 "$EC_SHA"
if [ "$CODE" != 0 ] && [ ! -e "$EC/h6/bin/epubcheck" ]; then ok; else ng "epubcheck-install: no Java fails"; fi
unset CURL_LOG CURL_ZIP

# ---------------------------------------------------------------- pdf-fonts.sh
# (docs/adr/0232): the typefaces of a PDF, and none but the fonts given
# fonts_pdf FILE FACE...: a PDF of one page with a font dictionary of each FACE
fonts_pdf() {
  out=$1
  shift
  {
    printf '%%PDF-1.6\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 10 10] /Resources << /Font <<'
    n=4
    for face in "$@"; do printf ' /F%s %s 0 R' "$n" "$n"; n=$((n + 1)); done
    printf ' >> >> >>\nendobj\n'
    n=4
    for face in "$@"; do printf '%s 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /%s >>\nendobj\n' "$n" "$face"; n=$((n + 1)); done
    printf 'trailer\n<< /Root 1 0 R >>\n%%%%EOF\n'
  } >"$out"
}
: >"$WORK/in"
if command -v qpdf >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  fonts_pdf "$WORK/listed.pdf" ABCDEF+NotoSerifJP-Regular GHIJKL+SourceCodePro-Regular ABCDEF+NotoSerifJP-Regular
  run sh "$HERE/pdf-fonts.sh" "$WORK/listed.pdf"
  expect "pdf-fonts.sh: the BaseFonts without the tags of the subsets, sorted, each once" 0 "NotoSerifJP-Regular
SourceCodePro-Regular"
  run sh "$HERE/pdf-fonts.sh" "$WORK/listed.pdf" NotoSerifJP-Regular SourceCodePro-Regular SourceSerif4-Regular
  expect "pdf-fonts.sh: a PDF of the fonts listed alone passes" 0
  fonts_pdf "$WORK/other.pdf" ABCDEF+NotoSerifJP-Regular Helvetica
  run sh "$HERE/pdf-fonts.sh" "$WORK/other.pdf" NotoSerifJP-Regular SourceCodePro-Regular
  expect "pdf-fonts.sh: a typeface not listed fails" 1
  if grep -qF 'has Helvetica, which is not a font of the list' "$WORK/err"; then ok; else ng "pdf-fonts.sh: the typeface not listed is named"; fi
else
  skip 4 "pdf-fonts.sh: qpdf or jq is not installed"
fi
run sh "$HERE/pdf-fonts.sh"
expect "pdf-fonts.sh: no PDF is a usage error" 2
run sh "$HERE/pdf-fonts.sh" "$WORK/no-such.pdf"
if command -v qpdf >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then expect "pdf-fonts.sh: a missing PDF exits with 2" 2; else expect "pdf-fonts.sh: without qpdf or jq it exits with 2" 2; fi

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

# ---------------------------------------------------------------- ci.yml and the parts of build
# (docs/adr/0045-split-x86-build-and-pull-request-cache.md)

# x86-64 builds four times: two runners for the tests (the suites of
# golem-driver, and the rest), one for the outputs, one for the environment
# check; aarch64 builds twice, for the tests and for the outputs. One runner
# of each architecture saves dist-newstyle (docs/adr/0045, docs/adr/0097,
# docs/adr/0140)
matrix_rows() { # the runner, part, tests, outputs, env, suites and save of each row of the matrix
  awk '/^        include:/ { on = 1; next }
    on && /^    [a-z]/ { on = 0 }
    on && /- runner:/ { r = $3 } on && /part:/ { p = $2 } on && /tests:/ { t = $2 }
    on && /outputs:/ { o = $2 } on && /env:/ { e = $2 } on && /suites:/ { u = $2 }
    on && /save:/ { print r, p, t, o, e, u, $2 }' "$1"
}
if [ "$(matrix_rows "$CI_YML")" = "ubuntu-24.04 tests-driver true false false driver true
ubuntu-24.04 tests-rest true false false rest false
ubuntu-24.04 outputs false true false none false
ubuntu-24.04 env false false true none false
ubuntu-24.04-arm tests-driver true false false driver true
ubuntu-24.04-arm tests-rest true false false rest false
ubuntu-24.04-arm outputs false true false none false" ]; then ok; else ng "ci.yml: the matrix of build has two runners of the tests on each architecture, the outputs of both, and the environment check of x86-64 (docs/adr/0155)"; fi
# one runner of each architecture saves dist-newstyle (docs/adr/0045,
# docs/adr/0140, docs/adr/0155)
if [ "$(matrix_rows "$CI_YML" | awk '$7 == "true" { print $1 }' | sort | uniq -c | awk '{ print $1 }' | sort -u)" = 1 ] &&
  [ "$(matrix_rows "$CI_YML" | awk '$7 == "true"' | wc -l | tr -d ' ')" = 2 ]; then ok; else
  ng "ci.yml: one runner of each architecture has save: true"
fi
# the step that starts at a line that matches $1 has a line that matches $2
step_has() {
  awk -v s="$1" -v c="$2" 'index($0, s) { on = 1; print; next } on && /^      - / { on = 0 } on' "$CI_YML" | grep -qF -- "$2"
}
# the step after a line that matches $1 has the condition $2
step_if() { awk -v s="$1" -v c="$2" 'index($0, s) { getline; if (index($0, c)) found = 1 } END { exit !found }' "$CI_YML"; }
TEST_STEP="name: The test suites of the runner"
if step_if "$TEST_STEP" "if: matrix.tests"; then ok; else ng "ci.yml: the tests run on the runners of the tests"; fi
if step_has "$TEST_STEP" 'cabal test $(sh scripts/ci/test-suites.sh "$SUITES")' && step_has "$TEST_STEP" 'SUITES: ${{ matrix.suites }}'; then ok; else
  ng "ci.yml: each runner of the tests runs the suites that test-suites.sh gives for its part (docs/adr/0140)"
fi
if [ "$(grep -cE '^ +(- run: )?cabal test ' "$CI_YML")" = 1 ]; then ok; else ng "ci.yml: one step runs cabal test"; fi
# the generated parser is checked where the suites of golem-parser run
if step_if "name: Generated parser matches the grammar" "if: matrix.tests && matrix.suites != 'driver'"; then ok; else ng "ci.yml: the generated parser is checked on the runners of the tests but tests-driver"; fi
if step_if "name: Outputs for the determinism check" "if: matrix.outputs"; then ok; else ng "ci.yml: the outputs are made on the runners of the outputs"; fi
# the lines of the job $1 of ci.yml
job_lines() { awk -v j="  $1:" '$0 == j { on = 1; next } on && /^  [a-z]/ { on = 0 } on' "$CI_YML"; }
# the generated modules of golem-driver are checked in the same way, right
# after the parser (docs/adr/0203)
EMBEDDED_STEP="name: Generated modules match VERSION and docs/diagnostics.md"
if step_if "$EMBEDDED_STEP" "if: matrix.tests && matrix.suites != 'driver'" &&
  step_has "$EMBEDDED_STEP" "sh scripts/gen-embedded.sh" &&
  step_has "$EMBEDDED_STEP" "git diff --exit-code modules/golem-driver/src/Golem/Driver/Version/Embedded.hs modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs" &&
  [ "$(awk '/^      - name: / { print }' "$CI_YML" | grep -A1 -F "name: Generated parser matches the grammar" | sed -n 2p)" = "      - $EMBEDDED_STEP" ]; then ok; else
  ng "ci.yml: the step after the generated parser runs gen-embedded.sh and checks that the generated modules of golem-driver have no diff (docs/adr/0203)"
fi
# the format job leaves the generated modules to the script, like the parser
for f in modules/golem-driver/src/Golem/Driver/Version/Embedded.hs modules/golem-driver/src/Golem/Driver/Explain/Embedded.hs; do
  if job_lines format | grep -qF -- "!$f" && job_lines format | grep -qF -- "--ignore-glob=\"$f\""; then ok; else
    ng "ci.yml: fourmolu and hlint skip $f (docs/adr/0203)"
  fi
done
# the determinism job compares the list of x86-64 with the committed
# hashes.txt, beside the two architectures (docs/adr/0173)
if job_lines determinism | grep -qF 'run: sh scripts/ci/determinism-hashes.sh determinism-ubuntu-24.04.txt scripts/determinism/hashes.txt' &&
  job_lines determinism | grep -qF 'uses: actions/checkout@'; then ok; else
  ng "ci.yml: the determinism job compares the outputs with scripts/determinism/hashes.txt (docs/adr/0173)"
fi
# every checkout of every workflow leaves no token in .git/config (the
# security audit of 2026-11-08, CI-01): the lines of the step, those indented
# more than its "- uses:", have persist-credentials: false
checkouts_without() {
  awk '
    function flush() { if (on && !seen) print FILENAME ":" at; on = 0 }
    FNR == 1 { flush() }
    on && NF > 0 && match($0, /^ */) && RLENGTH <= indent { flush() }
    on && /^ *persist-credentials: false *$/ { seen = 1 }
    /^ *- uses: actions\/checkout@/ { flush(); on = 1; seen = 0; at = FNR; match($0, /^ */); indent = RLENGTH }
    END { flush() }
  ' "$@"
}
missing=$(checkouts_without "$HERE"/../../.github/workflows/*.yml)
if [ -z "$missing" ]; then ok; else
  ng "workflows: a checkout without persist-credentials: false: $(echo "$missing" | sed 's#.*/\.github/#.github/#' | tr '\n' ' ')"
fi
printf '      - uses: actions/checkout@v7\n        with:\n          fetch-depth: 0\n      - run: true\n      - uses: actions/checkout@v7\n        with:\n          persist-credentials: false\n' >"$WORK/checkouts.yml"
if [ "$(checkouts_without "$WORK/checkouts.yml")" = "$WORK/checkouts.yml:1" ]; then ok; else
  ng "test.sh: checkouts_without finds the checkout without persist-credentials: false, and only it"
fi
# the build job checks the direction of the packages split from golem-doc
# in the plan it built (docs/adr/0173)
if job_lines build | grep -qF 'run: sh scripts/ci/doc-deps.sh dist-newstyle/cache/plan.json'; then ok; else
  ng "ci.yml: the build job runs doc-deps.sh on the plan (docs/adr/0173)"
fi
# the lines of the build job of ci.yml
build_lines() { job_lines build; }
# the environment check has an x86-64 runner of its own (docs/adr/0097)
if step_if "name: Japanese locales for the environment check" "if: matrix.env"; then ok; else ng "ci.yml: the locales are generated on the runner of the environment check"; fi
if step_if "name: The outputs do not change with the environment" "if: matrix.env"; then ok; else ng "ci.yml: the environment check runs on its own runner"; fi
if step_if "name: The fonts of the manuals for the environment check" "if: matrix.env" &&
  step_has "name: The fonts of the manuals for the environment check" "scripts/manual/fetch-fonts.sh manual/fonts" &&
  step_has "name: The fonts of the manuals for the environment check" "scripts/manual/fetch-fonts.sh manual-dev/fonts"; then ok; else
  ng "ci.yml: the runner of the environment check fetches the fonts of the manuals"
fi
# every runner of build configures the packages alike: a step before cabal
# build that adds a directory to PATH changes the configuration of every
# package on that runner alone, and cabal configures and builds them all
# again, golem-font and its HarfBuzz too (docs/adr/0097). The GHC
# directory is the same on every runner of an architecture
build_before_cabal() { awk '$0 == "  build:" { on = 1; next } on && /^  [a-z]/ { on = 0 } on && /- id: build$/ { on = 0 } on' "$CI_YML"; }
if [ "$(build_before_cabal | grep -c 'GITHUB_PATH')" = 1 ] && build_before_cabal | grep -qF 'echo "$GHC_DIR/bin" >> "$GITHUB_PATH"'; then ok; else
  ng "ci.yml: no step of build but GHC on the PATH adds to PATH before cabal build"
fi
if step_has "name: epubcheck is installed" 'echo "$RUNNER_TEMP/epubcheck/bin" >> "$GITHUB_PATH"'; then ok; else ng "ci.yml: epubcheck is put on PATH after cabal build"; fi
# the ten public-domain books are typeset to every target in CI (docs/adr/0058)
if step_has "$TEST_STEP" 'GOLEM_PD_BOOKS: "1"'; then ok; else ng "ci.yml: cabal test all has GOLEM_PD_BOOKS"; fi
# a missing golden file fails the tests in CI instead of being created
# (tasty-golden's --no-create, given by the environment: a suite without
# tasty-golden would reject the flag on its command line)
if step_has "$TEST_STEP" 'TASTY_NO_CREATE: "true"'; then ok; else ng "ci.yml: cabal test all has TASTY_NO_CREATE"; fi
# apt installs qpdf on the runners of the tests and the x86-64 runner of
# the outputs (docs/adr/0232); epubcheck comes from its release, cached by
# its version and SHA-256, on the x86-64 runner of the outputs (docs/adr/0062)
QPDF_IF="if: matrix.tests || (matrix.runner == 'ubuntu-24.04' && matrix.outputs)"
if step_if "name: qpdf in the background" "$QPDF_IF" && step_has "name: qpdf in the background" "apt-install.sh qpdf poppler-utils"; then ok; else ng "ci.yml: apt installs qpdf and Poppler on the runners of the tests and the x86-64 runner of the outputs in one apt-get"; fi
if grep -n 'apt-install\.sh' "$CI_YML" | grep -q epubcheck || grep -q "'epubcheck'" "$CI_YML"; then ng "ci.yml: apt does not install epubcheck"; else ok; fi
if grep -Eq '^  EPUBCHECK_VERSION: "[0-9]+\.[0-9]+\.[0-9]+"$' "$CI_YML" && grep -Eq '^  EPUBCHECK_SHA256: "[0-9a-f]{64}"$' "$CI_YML"; then ok; else ng "ci.yml: the version and the SHA-256 of epubcheck are pinned"; fi
EPUBCHECK_IF="if: matrix.runner == 'ubuntu-24.04' && matrix.outputs"
if step_if "name: Cache the release of epubcheck" "$EPUBCHECK_IF" &&
  step_has "name: Cache the release of epubcheck" "uses: actions/cache@" &&
  step_has "name: Cache the release of epubcheck" 'key: epubcheck-${{ env.EPUBCHECK_VERSION }}-${{ env.EPUBCHECK_SHA256 }}'; then ok; else
  ng "ci.yml: the release of epubcheck is cached by its version and SHA-256 on the x86-64 runner of the outputs"
fi
if step_if "name: epubcheck in the background" "$EPUBCHECK_IF" &&
  step_has "name: epubcheck in the background" 'sh scripts/ci/bg.sh start epubcheck timeout -k 10 300 sh scripts/ci/epubcheck-install.sh "$EPUBCHECK_VERSION" "$EPUBCHECK_SHA256"'; then ok; else
  ng "ci.yml: epubcheck-install.sh runs in the background with the pinned version on the x86-64 runner of the outputs"
fi
if step_if "name: epubcheck is installed" "$EPUBCHECK_IF" && step_has "name: epubcheck is installed" "bg.sh wait epubcheck"; then ok; else ng "ci.yml: the x86-64 runner of the outputs waits for epubcheck"; fi
# the four EPUBs of the fixtures pass epubcheck; epub-forms takes glossary
# from plugins/wasm through a cache (docs/adr/0232)
if step_if "name: The EPUB of epub-forms passes epubcheck" "$EPUBCHECK_IF" && step_has "name: The EPUB of epub-forms passes epubcheck" 'XDG_CACHE_HOME="$cache"' && step_has "name: The EPUB of epub-forms passes epubcheck" "epubcheck build/epub/book.epub"; then ok; else ng "ci.yml: the EPUB of epub-forms passes epubcheck on the x86-64 runner of the outputs"; fi
if step_if "name: qpdf is installed" "$QPDF_IF" && step_has "name: qpdf is installed" "bg.sh wait apt"; then ok; else ng "ci.yml: the runners of the tests and the x86-64 runner of the outputs wait for qpdf"; fi
# the manuals pass golem preflight with the rules of CI, and their PDFs
# name no typeface but the fonts of their fonts/ (docs/adr/0232)
MANUAL_IF="if: matrix.runner == 'ubuntu-24.04' && matrix.outputs"
if step_if "name: The preflight of the manuals" "$MANUAL_IF" && step_has "name: The preflight of the manuals" 'preflight --rules ../scripts/ci/manual-preflight.toml'; then ok; else ng "ci.yml: the x86-64 runner of the outputs runs golem preflight on the manuals"; fi
if step_if "name: The typefaces of the manuals are their fonts" "$MANUAL_IF" && step_has "name: The typefaces of the manuals are their fonts" 'sh scripts/ci/pdf-fonts.sh'; then ok; else ng "ci.yml: the x86-64 runner of the outputs checks the typefaces of the manuals"; fi
# release-scripts installs the pinned Claude Code with mise before test.sh
# and requires it (docs/adr/0058)
RS=$WORK/release-scripts.yml
job_lines release-scripts >"$RS"
MISE_AT=$(grep -n 'uses: jdx/mise-action@' "$RS" | head -1 | cut -d: -f1)
TEST_AT=$(grep -n 'run: sh scripts/release/test.sh' "$RS" | head -1 | cut -d: -f1)
if [ -n "$MISE_AT" ] && [ -n "$TEST_AT" ] && [ "$MISE_AT" -lt "$TEST_AT" ]; then ok; else ng "ci.yml: release-scripts installs Claude Code with mise before test.sh"; fi
if grep -qF 'MISE_TRUSTED_CONFIG_PATHS: ${{ github.workspace }}' "$RS" && grep -qF 'cache: false' "$RS"; then ok; else ng "ci.yml: release-scripts runs mise as the notes job does"; fi
if grep -qF 'GOLEM_REQUIRE_CLAUDE: "1"' "$RS"; then ok; else ng "ci.yml: release-scripts runs test.sh with GOLEM_REQUIRE_CLAUDE"; fi
if grep -q 'ANTHROPIC_API_KEY' "$RS"; then ng "ci.yml: release-scripts has no API key"; else ok; fi
# scripts-macos runs the six tests of the scripts on macOS with the BSD
# tools of the system only, when the change needs the build; ci needs it
# (docs/adr/0079). The tests of the visual regression test run in changes
# too (docs/adr/0093, docs/adr/0095)
SM=$WORK/scripts-macos.yml
job_lines scripts-macos >"$SM"
if grep -qx '    runs-on: macos-15' "$SM"; then ok; else ng "ci.yml: scripts-macos runs on macos-15"; fi
if grep -qx '    needs: changes' "$SM" && grep -qxF "    if: needs.changes.outputs.build == 'true'" "$SM"; then ok; else ng "ci.yml: scripts-macos is skipped as build is"; fi
if grep -qx '      PATH: /usr/bin:/bin:/usr/sbin:/sbin' "$SM" && ! grep -Eq 'brew|gnubin|coreutils|gawk|gnu-sed|findutils' "$SM"; then ok; else ng "ci.yml: scripts-macos has the tools of the system only on PATH"; fi
# the six run at the same time on the cores of the runner, by run-all.sh,
# in one step
SM_RUN='        run: sh scripts/ci/run-all.sh -t 600 scripts/ci/test.sh scripts/manual/test.sh scripts/env-determinism/test.sh scripts/release/test.sh scripts/test.sh scripts/visual/test.sh'
if grep -qxF "$SM_RUN" "$SM" && [ "$(grep -c 'run: ' "$SM")" = 1 ]; then ok; else ng "ci.yml: scripts-macos runs the six tests with run-all.sh -t 600"; fi
# the deadline comes before the timeout of the job, so that the outputs are
# written (docs/adr/0154)
SM_MIN=$(sed -n 's/^    timeout-minutes: \([0-9]*\)$/\1/p' "$SM")
if [ -n "$SM_MIN" ] && [ 600 -lt $((SM_MIN * 60)) ]; then ok; else ng "ci.yml: the deadline of scripts-macos is shorter than the timeout of its job"; fi
# the tests of the scripts run in scripts-linux, beside changes, so that the
# build does not wait for them; it is never skipped (docs/adr/0097)
SL=$WORK/scripts-linux.yml
job_lines scripts-linux >"$SL"
if grep -qx '    runs-on: ubuntu-24.04' "$SL" && ! grep -Eq '^    (needs|if):' "$SL"; then ok; else ng "ci.yml: scripts-linux runs on ubuntu-24.04, with no needs and no condition"; fi
for t in scripts/ci/test.sh scripts/manual/test.sh scripts/env-determinism/test.sh scripts/test.sh scripts/visual/test.sh; do
  if grep -qx "        run: sh $t" "$SL"; then ok; else ng "ci.yml: scripts-linux runs $t"; fi
  if job_lines changes | grep -qx "        run: sh $t"; then ng "ci.yml: changes does not run $t"; else ok; fi
done
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?scripts-linux([],].*)?$'; then ok; else ng "ci.yml: ci needs scripts-linux"; fi

# ---------------------------------------------------------------- ci.yml and the visual regression test
# (docs/adr/0093, docs/adr/0094, docs/adr/0095)

VJ=$WORK/visual.yml
job_lines visual >"$VJ"
if [ -s "$VJ" ]; then ok; else ng "ci.yml: there is a visual job"; fi
if grep -qx '    needs: \[changes\]' "$VJ" && grep -qxF "    if: needs.changes.outputs.build == 'true'" "$VJ"; then ok; else ng "ci.yml: visual needs only changes and is skipped as build is (docs/adr/0099)"; fi
if grep -qx '    runs-on: ubuntu-24.04' "$VJ" && grep -qx '    timeout-minutes: 75' "$VJ"; then ok; else ng "ci.yml: visual runs on ubuntu-24.04 with a timeout of 75 minutes"; fi
# visual waits for visual-pdfs of the outputs runner before it downloads it
# (docs/adr/0099)
WAIT_AT=$(grep -n 'sh scripts/visual/wait-pdfs.sh' "$VJ" | head -1 | cut -d: -f1)
DOWNLOAD_AT=$(grep -n 'uses: actions/download-artifact@' "$VJ" | head -1 | cut -d: -f1)
if grep -qxF "        run: timeout -k 10 3600 sh scripts/visual/wait-pdfs.sh \"\$GITHUB_RUN_ID\" \"\$GITHUB_RUN_ATTEMPT\" 'build (ubuntu-24.04, outputs)'" "$VJ" &&
  [ -n "$WAIT_AT" ] && [ -n "$DOWNLOAD_AT" ] && [ "$WAIT_AT" -lt "$DOWNLOAD_AT" ]; then ok; else ng "ci.yml: visual waits for visual-pdfs of the outputs runner, then downloads it"; fi
if grep -qF "name: build (\${{ matrix.runner }}, \${{ matrix.part }})" "$CI_YML" && awk '/^          - runner: ubuntu-24.04$/ { r = 1; next } r && /part: outputs$/ { f = 1 } { r = 0 } END { exit !f }' "$CI_YML"; then ok; else ng "ci.yml: the job that wait-pdfs.sh waits for is named build (ubuntu-24.04, outputs)"; fi
# visual_step NAME: the lines of the step of visual that starts at a line with NAME
visual_step() { awk -v s="$1" 'index($0, s) { on = 1; print; next } on && /^      - / { on = 0 } on' "$VJ"; }
if visual_step "name: Cache shem" | grep -qF 'uses: actions/cache@' &&
  visual_step "name: Cache shem" | grep -qxF '          path: third_party/shem' &&
  visual_step "name: Cache shem" | grep -qxF "          key: shem-\${{ hashFiles('scripts/visual/fetch-shem.sh') }}"; then ok; else
  ng "ci.yml: visual caches third_party/shem by the hash of fetch-shem.sh"
fi
if grep -qxF '        run: timeout -k 10 300 sh scripts/visual/fetch-shem.sh' "$VJ"; then ok; else ng "ci.yml: visual runs fetch-shem.sh under timeout"; fi
CACHE_AT=$(grep -n 'name: Cache shem' "$VJ" | head -1 | cut -d: -f1)
FETCH_AT=$(grep -n 'sh scripts/visual/fetch-shem.sh' "$VJ" | head -1 | cut -d: -f1)
CHECK_AT=$(grep -n 'sh scripts/visual/check.sh' "$VJ" | head -1 | cut -d: -f1)
if [ -n "$CACHE_AT" ] && [ -n "$FETCH_AT" ] && [ -n "$CHECK_AT" ] && [ "$CACHE_AT" -lt "$FETCH_AT" ] && [ "$FETCH_AT" -lt "$CHECK_AT" ]; then ok; else ng "ci.yml: visual restores the cache, fetches shem, then checks"; fi
if visual_step "uses: actions/download-artifact@" | grep -qxF '          name: visual-pdfs'; then ok; else ng "ci.yml: visual downloads visual-pdfs"; fi
if grep -qF 'run: timeout -k 10 600 sh scripts/visual/check.sh --lists "$RUNNER_TEMP/visual-diff/pages" visual-pdfs' "$VJ" &&
  visual_step "name: The pages match the references" | grep -qxF '        shell: bash'; then ok; else
  ng "ci.yml: visual runs check.sh under timeout -k 10 600, with pipefail"
fi
if grep -q 'SHEM' "$VJ"; then ng "ci.yml: CI does not use SHEM"; else ok; fi
VISUAL_IF="if: matrix.runner == 'ubuntu-24.04' && matrix.outputs"
if step_if "name: The PDFs of the visual regression test" "$VISUAL_IF" &&
  step_has "name: The PDFs of the visual regression test" 'GOLEM="$(cabal list-bin -v0 golem)" sh scripts/visual/build.sh visual-pdfs'; then ok; else
  ng "ci.yml: the x86-64 runner of the outputs builds the PDFs of the visual regression test"
fi
if [ "$(grep -c 'sh scripts/visual/build.sh' "$CI_YML")" = 1 ]; then ok; else ng "ci.yml: only one step builds the PDFs of the visual regression test"; fi
if step_if "name: Upload the PDFs of the visual regression test" "$VISUAL_IF" &&
  step_has "name: Upload the PDFs of the visual regression test" 'name: visual-pdfs'; then ok; else
  ng "ci.yml: the x86-64 runner of the outputs uploads visual-pdfs"
fi
# visual-pdfs is built and uploaded before the EPUBs and the outputs of
# determinism.sh, so that visual does not wait for them (docs/adr/0140)
DET_AT=$(grep -n 'name: Outputs for the determinism check' "$CI_YML" | cut -d: -f1)
EPUB_AT=$(grep -n 'name: The EPUB passes epubcheck' "$CI_YML" | cut -d: -f1)
VB_AT=$(grep -n 'name: The PDFs of the visual regression test' "$CI_YML" | cut -d: -f1)
VU_AT=$(grep -n 'name: Upload the PDFs of the visual regression test' "$CI_YML" | cut -d: -f1)
if [ -n "$DET_AT" ] && [ -n "$EPUB_AT" ] && [ -n "$VB_AT" ] && [ -n "$VU_AT" ] &&
  [ "$VB_AT" -lt "$VU_AT" ] && [ "$VU_AT" -lt "$EPUB_AT" ] && [ "$VU_AT" -lt "$DET_AT" ]; then ok; else
  ng "ci.yml: the PDFs of the visual regression test are built and uploaded before epubcheck and determinism.sh"
fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?visual([],].*)?$'; then ok; else ng "ci.yml: ci needs visual"; fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?scripts-macos([],].*)?$'; then ok; else ng "ci.yml: ci needs scripts-macos"; fi
# no step of actions/cache/save has a condition on pull_request: a pull
# request saves no dist- cache, and restores those of main (docs/adr/0228, I1)
cache_saves_on_pull_requests() {
  awk '
    function flush() { if (save && pr) print at; save = 0; pr = 0 }
    /^      - / { flush(); at = FNR }
    /^  [a-z]/ { flush() }
    /uses: actions\/cache\/save@/ { save = 1 }
    /github\.event_name == .pull_request./ { pr = 1 }
    END { flush() }
  ' "$1"
}
if [ -z "$(cache_saves_on_pull_requests "$CI_YML")" ]; then ok; else ng "ci.yml: no step of actions/cache/save runs on pull requests (docs/adr/0228, I1)"; fi
printf '      - name: Save\n        if: github.event_name == '"'"'pull_request'"'"'\n        uses: actions/cache/save@v6\n      - name: Restore\n        if: github.event_name == '"'"'pull_request'"'"'\n        uses: actions/cache/restore@v6\n' >"$WORK/saves.yml"
if [ "$(cache_saves_on_pull_requests "$WORK/saves.yml")" = 1 ]; then ok; else
  ng "test.sh: cache_saves_on_pull_requests finds the save on pull requests, and not the restore"
fi
# a push to main saves dist-newstyle only when GHC compiled a module
# (docs/adr/0228, I2)
if step_if "name: Save dist-newstyle (docs/adr/0009)" "if: success() && matrix.save && steps.build.outputs.compiled == 'true' && github.event_name == 'push' && github.ref == 'refs/heads/main'"; then ok; else ng "ci.yml: a push to main saves dist-newstyle from the runner that saves, when GHC compiled (docs/adr/0140, docs/adr/0228, I2)"; fi
if grep -n 'Save dist-newstyle' -A 1 "$CI_YML" | grep -q 'matrix.tests'; then ng "ci.yml: the saves of dist-newstyle do not depend on matrix.tests"; else ok; fi

# ---------------------------------------------------------------- ci.yml and the caches of GHC and the index
# (docs/adr/0141-smaller-ghc-and-hackage-index-caches.md)

# the Hackage index is cached as one directory, and the step of cabal
# update removes 01-index.tar.gz before the cache is saved at the end of
# the job: a line with ! in the path of actions/cache took nothing out
# (docs/adr/0152)
INDEX_STEP="name: Cache the Hackage index"
if step_has "$INDEX_STEP" '          path: ~/.cabal/packages/hackage.haskell.org' &&
  ! step_has "$INDEX_STEP" '!~/.cabal' &&
  step_has "$INDEX_STEP" "key: hackage-index-no-gz-\${{ hashFiles('cabal.project.freeze') }}"; then ok; else
  ng "ci.yml: the Hackage index is cached as one directory under hackage-index-no-gz-"
fi
UPDATE_STEP="- if: steps.index.outputs.cache-hit != 'true'"
UPD_AT=$(build_lines | grep -nF -- "$UPDATE_STEP" | head -1 | cut -d: -f1)
if [ -n "$UPD_AT" ] && build_lines | sed -n "$UPD_AT,\$p" | awk 'NR > 1 && /^      - / { exit } { print }' >"$WORK/update-step" &&
  grep -n 'cabal update' "$WORK/update-step" >/dev/null &&
  [ "$(grep -n '^ *cabal update$' "$WORK/update-step" | cut -d: -f1)" -lt "$(grep -n '^ *rm ~/.cabal/packages/hackage.haskell.org/01-index.tar.gz$' "$WORK/update-step" | cut -d: -f1)" ]; then ok; else
  ng "ci.yml: the step of cabal update removes 01-index.tar.gz after cabal update"
fi
# a ! line works in actions/cache only with patterns of single files, which
# no check of the path catches: no step of actions/cache has one
if grep -n -A6 'uses: actions/cache' "$CI_YML" | grep -Eq '^[0-9]+-\s+!'; then ng "ci.yml: no path of actions/cache has a line with !"; else ok; fi
# GHC is cached without its documentation and its libraries for profiling
if step_has "name: Cache GHC" 'key: ghc-${{ env.GHC_VERSION }}-${{ runner.os }}-${{ runner.arch }}-${{ env.ImageOS }}-slim'; then ok; else
  ng "ci.yml: the key of the cache of GHC ends in -slim"
fi
SLIM_STEP="name: The files of GHC that CI does not read"
if step_if "$SLIM_STEP" "if: steps.ghc.outputs.cache-hit != 'true'" &&
  build_lines | grep -B1 -F 'name: Cache GHC' | grep -qx '      - id: ghc'; then ok; else
  ng "ci.yml: the files of GHC are removed only when the cache of GHC missed"
fi
if step_has "$SLIM_STEP" 'rm -rf "$GHC_DIR/share/doc"' &&
  step_has "$SLIM_STEP" "find \"\$GHC_DIR\" -type f \\( -name '*_p.a' -o -name '*.p_hi' \\) -delete"; then ok; else
  ng "ci.yml: the documentation and the libraries for profiling are removed from GHC"
fi
SETUP_AT=$(build_lines | grep -n 'uses: haskell-actions/setup@' | head -1 | cut -d: -f1)
SLIM_AT=$(build_lines | grep -nF "$SLIM_STEP" | head -1 | cut -d: -f1)
CBUILD_AT=$(build_lines | grep -n -- '- id: build$' | head -1 | cut -d: -f1)
if [ -n "$SETUP_AT" ] && [ -n "$SLIM_AT" ] && [ -n "$CBUILD_AT" ] && [ "$SETUP_AT" -lt "$SLIM_AT" ] && [ "$SLIM_AT" -lt "$CBUILD_AT" ]; then ok; else
  ng "ci.yml: the files of GHC are removed after haskell-actions/setup and before cabal build"
fi

# ---------------------------------------------------------------- ci.yml and the times of setup-config
# (docs/adr/0147-touch-setup-config-after-restoring-dist.md)

# the setup-config of the restored dist-newstyle are made newer than the
# .cabal files of the checkout, after the restore and before cabal build,
# so that Setup does not configure every test suite again
TOUCH_STEP="name: The setup-config of dist-newstyle newer than the .cabal files"
if step_has "$TOUCH_STEP" 'find dist-newstyle -name setup-config -exec touch {} +'; then ok; else
  ng "ci.yml: a step touches the setup-config of dist-newstyle"
fi
RESTORE_AT=$(build_lines | grep -n 'name: Restore dist-newstyle' | head -1 | cut -d: -f1)
TOUCH_AT=$(build_lines | grep -nF "$TOUCH_STEP" | head -1 | cut -d: -f1)
CB_AT=$(build_lines | grep -n -- '- id: build$' | head -1 | cut -d: -f1)
if [ -n "$RESTORE_AT" ] && [ -n "$TOUCH_AT" ] && [ -n "$CB_AT" ] && [ "$RESTORE_AT" -lt "$TOUCH_AT" ] && [ "$TOUCH_AT" -lt "$CB_AT" ]; then ok; else
  ng "ci.yml: the setup-config are touched after Restore dist-newstyle and before cabal build"
fi

# ---------------------------------------------------------------- release.yml and mise.toml
# (docs/adr/0044-release-workflow-hardening.md)

# Claude Code is pinned to an exact version in mise.toml
MISE_TOML=$HERE/../../mise.toml
if grep -Eq '^"npm:@anthropic-ai/claude-code" = \{ *version = "[0-9]+\.[0-9]+\.[0-9]+"' "$MISE_TOML"; then ok; else ng "mise.toml: Claude Code at an exact version"; fi
RELEASE_YML=$HERE/../../.github/workflows/release.yml
job_of() { # job_of WORKFLOW JOB: the lines of the job
  awk -v job="  $2:" '/^jobs:/ { on = 1; next } on && /^[^ #]/ { on = 0 } on && /^  [a-z][a-z0-9-]*:$/ { inj = ($0 == job) } on && inj' "$1"
}
perms_of() { # perms_of WORKFLOW JOB: the permissions of the job, one per line
  job_of "$1" "$2" | awk '/^    permissions:/ { on = 1; next } on && /^    [^ ]/ { on = 0 } on { sub(/^ +/, ""); print }'
}
if [ "$(perms_of "$RELEASE_YML" notes)" = "contents: read" ]; then ok; else ng "release.yml: the notes job has contents: read only"; fi
if job_of "$RELEASE_YML" notes | grep -q 'jdx/mise-action@v'; then ok; else ng "release.yml: the notes job installs Claude Code with mise"; fi
if job_of "$RELEASE_YML" release | grep -Eiq 'npm|mise|claude'; then ng "release.yml: the release job has no npm, mise nor Claude Code"; else ok; fi
if job_of "$RELEASE_YML" release | grep -q '^      - release$\|needs:.*notes'; then ok; else ng "release.yml: the release job needs the notes job"; fi
if grep -q 'npm install' "$RELEASE_YML"; then ng "release.yml: no npm install"; else ok; fi
# a patch is checked on the inputs of its base, and the release waits for it (docs/adr/0212)
if job_of "$RELEASE_YML" release | grep -q 'needs:.*patch'; then ok; else ng "release.yml: the release job needs the patch job"; fi
if job_of "$RELEASE_YML" patch | grep -q 'scripts/release/check-patch-output.sh'; then ok; else ng "release.yml: the patch job runs check-patch-output.sh"; fi
if job_of "$RELEASE_YML" version | grep -q 'patch-base='; then ok; else ng "release.yml: the version job writes patch-base"; fi

# every job that runs haskell-actions/setup gives cabal CABAL_DIR=$HOME/.cabal
# before it and checks the directories cabal uses after it, before the cache
# of the Hackage index, under the same if: (docs/adr/0201)
CABAL_DIR_RUN='run: echo "CABAL_DIR=$HOME/.cabal" >> "$GITHUB_ENV"'
step_line() { # step_line WORKFLOW JOB TEXT: the line in the job of the first step that has TEXT
  job_of "$1" "$2" | awk -v t="$3" '/^      - / { s = NR } index($0, t) { print s; exit }'
}
step_cond() { # step_cond WORKFLOW JOB TEXT: the if: of the first step that has TEXT
  job_of "$1" "$2" | awk -v t="$3" '
    /^      - / { if (found) exit; c = "" }
    { u = $0; sub(/^      - /, "        ", u) }
    u ~ /^        if: / { c = u; sub(/^        if: /, "", c) }
    index($0, t) { found = 1 }
    END { if (found) print c }'
}
cabal_dir_case() { # cabal_dir_case WORKFLOW JOB NAME
  if [ "$(grep -cF 'uses: haskell-actions/setup@v2' "$1")" = "$(grep -cF "$CABAL_DIR_RUN" "$1")" ]; then ok; else
    ng "$3: as many steps give CABAL_DIR as run haskell-actions/setup (docs/adr/0201)"
  fi
  setup=$(step_line "$1" "$2" 'uses: haskell-actions/setup@v2')
  give=$(step_line "$1" "$2" "$CABAL_DIR_RUN")
  check=""
  for key in config-file:config remote-repo-cache:packages store-dir:store; do
    l=$(step_line "$1" "$2" "test \"\$(cabal path -z --${key%%:*})\" = \"\$HOME/.cabal/${key#*:}\"")
    if [ -n "$l" ] && { [ -z "$check" ] || [ "$l" = "$check" ]; }; then check=$l; else check=none; fi
  done
  if [ -n "$setup" ] && [ -n "$give" ] && [ "$give" -lt "$setup" ]; then ok; else
    ng "$3: CABAL_DIR is given before haskell-actions/setup (docs/adr/0201)"
  fi
  if [ -n "$setup" ] && [ "$check" != none ] && [ "$check" -gt "$setup" ]; then ok; else
    ng "$3: a step after haskell-actions/setup checks that cabal uses ~/.cabal (docs/adr/0201)"
  fi
  if [ -n "$setup" ] && [ "$(step_cond "$1" "$2" "$CABAL_DIR_RUN")" = "$(step_cond "$1" "$2" 'uses: haskell-actions/setup@v2')" ] &&
    [ "$(step_cond "$1" "$2" 'cabal path -z --config-file')" = "$(step_cond "$1" "$2" 'uses: haskell-actions/setup@v2')" ]; then ok; else
    ng "$3: the steps of CABAL_DIR have the if: of haskell-actions/setup (docs/adr/0201)"
  fi
}
cabal_dir_case "$CI_YML" build "ci.yml: build"
cabal_dir_case "$HERE/../../.github/workflows/race.yml" race "race.yml: race"
cabal_dir_case "$RELEASE_YML" build "release.yml: build"
for w in "$CI_YML:build" "$HERE/../../.github/workflows/race.yml:race"; do
  index=$(step_line "${w%:*}" "${w##*:}" 'path: ~/.cabal/packages/hackage.haskell.org')
  check=$(step_line "${w%:*}" "${w##*:}" 'cabal path -z --config-file')
  if [ -n "$index" ] && [ -n "$check" ] && [ "$check" -lt "$index" ]; then ok; else
    ng "$(basename "${w%:*}"): ${w##*:}: cabal's directory is checked before the cache of the Hackage index (docs/adr/0201)"
  fi
done

# mise itself is pinned to an exact version and the SHA-256 of its linux-x64
# binary, with the same values in ci.yml and release.yml, and every step of
# jdx/mise-action passes both (docs/adr/0085)
top_env() { # top_env WORKFLOW: the lines of the top-level env
  awk '/^env:$/ { on = 1; next } on && /^[^ #]/ { on = 0 } on' "$1"
}
env_value() { # env_value WORKFLOW NAME: the quoted value of NAME in the top-level env
  top_env "$1" | awk -v name="  $2: " 'index($0, name) == 1 { v = substr($0, length(name) + 1); gsub(/"/, "", v); print v }'
}
mise_steps() { # mise_steps WORKFLOW: the number of steps of jdx/mise-action
  grep -c 'uses: jdx/mise-action@' "$1"
}
mise_pinned_steps() { # mise_pinned_steps WORKFLOW: the steps of jdx/mise-action whose with: has the pinned version and SHA-256
  awk '
    function indent(s) { match(s, /^ */); return RLENGTH }
    function close_step() { if (instep && v && h) n++; instep = 0; inwith = 0 }
    {
      t = $0
      sub(/^ +/, "", t)
      if (instep && t != "" && indent($0) <= dash) close_step()
      if (instep) {
        if (inwith && t != "" && indent($0) <= wi) inwith = 0
        if (t == "with:") { inwith = 1; wi = indent($0) }
        else if (inwith && t == "version: ${{ env.MISE_VERSION }}") v = 1
        else if (inwith && t == "sha256: ${{ env.MISE_SHA256 }}") h = 1
      }
      if (index($0, "uses: jdx/mise-action@") > 0) {
        close_step()
        instep = 1; v = 0; h = 0
        dash = indent($0)
        if (substr(t, 1, 2) != "- ") dash -= 2
      }
    }
    END { close_step(); print n + 0 }' "$1"
}
# the patterns are in variables: written inside "$(...)", they matched
# nothing under bash 3.2, the sh of macOS
MISE_VERSION_RE='^  MISE_VERSION: "[0-9]{4}\.[0-9]{1,2}\.[0-9]+"$'
MISE_SHA256_RE='^  MISE_SHA256: "[0-9a-f]{64}"$'
for wf in "$CI_YML" "$RELEASE_YML"; do
  name=${wf##*/}
  if [ "$(top_env "$wf" | grep -Ec "$MISE_VERSION_RE")" -eq 1 ] &&
    [ "$(top_env "$wf" | grep -c 'MISE_VERSION')" -eq 1 ]; then ok; else
    ng "$name: one MISE_VERSION at an exact version in the top-level env"
  fi
  if [ "$(top_env "$wf" | grep -Ec "$MISE_SHA256_RE")" -eq 1 ] &&
    [ "$(top_env "$wf" | grep -c 'MISE_SHA256')" -eq 1 ]; then ok; else
    ng "$name: one MISE_SHA256 of 64 lowercase hex digits in the top-level env"
  fi
  MS=$(mise_steps "$wf")
  if [ "$MS" -gt 0 ] && [ "$(mise_pinned_steps "$wf")" -eq "$MS" ]; then ok; else
    ng "$name: every step of jdx/mise-action passes version and sha256 from the env"
  fi
done
if [ -n "$(env_value "$CI_YML" MISE_VERSION)" ] &&
  [ "$(env_value "$CI_YML" MISE_VERSION)" = "$(env_value "$RELEASE_YML" MISE_VERSION)" ]; then ok; else
  ng "ci.yml and release.yml: the same MISE_VERSION"
fi
if [ -n "$(env_value "$CI_YML" MISE_SHA256)" ] &&
  [ "$(env_value "$CI_YML" MISE_SHA256)" = "$(env_value "$RELEASE_YML" MISE_SHA256)" ]; then ok; else
  ng "ci.yml and release.yml: the same MISE_SHA256"
fi
# the SHA-256 is of the linux-x64 binary
if [ "$(job_of "$RELEASE_YML" notes | grep -cx '    runs-on: ubuntu-24.04')" -eq 1 ]; then ok; else ng "release.yml: the notes job runs on ubuntu-24.04"; fi
if [ "$(job_of "$CI_YML" release-scripts | grep -cx '    runs-on: ubuntu-24.04')" -eq 1 ]; then ok; else ng "ci.yml: release-scripts runs on ubuntu-24.04"; fi

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
needs changes=success scripts-linux=success build=success determinism=success visual=success release-scripts=success scripts-macos=success format=success plugins=success editors=success editors-lsp=success verapdf=success wasm=success >"$WORK/in"
run gate
expect "gate: all succeeded" 0
needs changes=success scripts-linux=success build=skipped determinism=skipped visual=skipped release-scripts=skipped scripts-macos=skipped format=skipped plugins=skipped editors=success editors-lsp=skipped verapdf=skipped wasm=skipped >"$WORK/in"
run gate
expect "gate: docs only" 0
needs changes=success scripts-linux=success build=failure determinism=skipped visual=skipped release-scripts=success scripts-macos=success format=success plugins=success editors=success >"$WORK/in"
run gate
expect "gate: a failed build" 1
if grep -q 'build' "$WORK/err" && grep -q 'failure' "$WORK/err"; then ok; else ng "gate: the failed job is named"; fi
needs changes=success scripts-linux=success build=success determinism=cancelled visual=cancelled release-scripts=success scripts-macos=success format=success plugins=success editors=success >"$WORK/in"
run gate
expect "gate: a cancelled job" 1
needs changes=success scripts-linux=success build=success determinism=success visual=success release-scripts=success scripts-macos=success plugins=success editors=success >"$WORK/in"
run gate
expect "gate: a missing job" 1
if grep -q 'format' "$WORK/err"; then ok; else ng "gate: the missing job is named"; fi
needs changes=success scripts-linux=success build=success determinism=success visual=failure release-scripts=success scripts-macos=success format=success plugins=success editors=success >"$WORK/in"
run gate
expect "gate: a failed visual (docs/adr/0095)" 1
if grep -q 'visual' "$WORK/err"; then ok; else ng "gate: the failed visual is named"; fi
echo 'not json' >"$WORK/in"
run gate
expect "gate: not JSON" 1

# the jobs of ci.yml, but ci itself and caches, which ci does not need
# (docs/adr/0228), are the jobs that gate.sh knows
ci_jobs() { # ci_jobs WORKFLOW: the names of its jobs
  awk '/^jobs:/ { on = 1; next } on && /^[^ #]/ { on = 0 } on && /^  [a-z][a-z0-9-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$1"
}
# names_match GATE: the names of the gate.sh at GATE are the jobs of ci.yml
names_match() {
  : >"$WORK/in"
  run sh "$1" --names
  [ "$CODE" = 0 ] && [ "$(sort "$WORK/out")" = "$(ci_jobs "$HERE/../../.github/workflows/ci.yml" | grep -vx -e ci -e caches | sort)" ]
}
if names_match "$HERE/gate.sh"; then ok; else ng "gate: the names are the jobs of ci.yml"; fi
# the same comparison finds a job missing from the names, in a copy of
# gate.sh without format (docs/adr/0077)
sed 's/^NAMES="\(.*\) format\(.*\)"$/NAMES="\1\2"/' "$HERE/gate.sh" >"$WORK/gate-fewer.sh"
if grep -q '^NAMES=.*format' "$WORK/gate-fewer.sh" || cmp -s "$HERE/gate.sh" "$WORK/gate-fewer.sh"; then
  ng "gate: the copy of gate.sh has no format"
elif names_match "$WORK/gate-fewer.sh"; then
  ng "gate: a job missing from the names is found"
else
  ok
fi

# the report of a failure needs actions: read for the artifacts of other
# runs: visual alone has it, and the workflow keeps contents: read
# (docs/adr/0096)
if [ "$(awk '/^permissions:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z]/' "$CI_YML")" = "  contents: read" ]; then ok; else ng "ci.yml: the permissions of the workflow are contents: read only"; fi
if [ "$(perms_of "$CI_YML" visual)" = "contents: read
actions: read" ]; then ok; else ng "ci.yml: visual has contents: read and actions: read"; fi
ACTIONS_READ_JOBS=$(ci_jobs "$CI_YML" | while IFS= read -r j; do if perms_of "$CI_YML" "$j" | grep -qx 'actions: read'; then printf '%s\n' "$j"; fi; done)
if [ "$ACTIONS_READ_JOBS" = visual ]; then ok; else ng "ci.yml: no job but visual has actions: read"; fi
# caches alone has a write permission, actions: write, to delete the stale
# dist- caches of main; it runs on pushes to main only, after the saves of
# build and wasm, and uses no action but checkout (docs/adr/0228)
WRITE_JOBS=$(ci_jobs "$CI_YML" | while IFS= read -r j; do if perms_of "$CI_YML" "$j" | grep -q ': *write'; then printf '%s\n' "$j"; fi; done)
if [ "$WRITE_JOBS" = caches ] && [ "$(perms_of "$CI_YML" caches)" = "contents: read
actions: write" ]; then ok; else ng "ci.yml: no job but caches has a write permission, and caches has contents: read and actions: write (docs/adr/0228)"; fi
if [ "$(grep -cE ': *write' "$CI_YML")" = 1 ]; then ok; else ng "ci.yml: one write permission, that of caches (docs/adr/0228)"; fi
CACHES_IF=$(job_lines caches | sed -n 's/^    if: //p')
case "$CACHES_IF" in
  *"github.event_name == 'push' && github.ref == 'refs/heads/main'"*) ok ;;
  *) ng "ci.yml: caches runs on pushes to main only (docs/adr/0228)" ;;
esac
if job_lines caches | grep -Eq '^    needs: \[(.*[ ,])?build([],].*)?$' &&
  job_lines caches | grep -Eq '^    needs: \[(.*[ ,])?wasm([],].*)?$'; then ok; else ng "ci.yml: caches needs build and wasm (docs/adr/0228)"; fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?caches([],].*)?$'; then ng "ci.yml: ci does not need caches (docs/adr/0228)"; else ok; fi
if [ "$(job_lines caches | grep -E '^ +(- )?uses: ' | grep -vE '^ +(- )?uses: actions/checkout@')" = "" ] &&
  job_lines caches | grep -qE '^ +(- )?uses: actions/checkout@'; then ok; else ng "ci.yml: caches uses no action but actions/checkout (docs/adr/0228)"; fi
if job_lines caches | grep -qF 'gh cache list --ref refs/heads/main --key dist- --limit 100 --json id,key,createdAt' &&
  job_lines caches | grep -qF 'sh scripts/ci/stale-dist-caches.sh' &&
  job_lines caches | grep -qF 'gh cache delete'; then ok; else ng "ci.yml: caches lists the dist- caches of main, and deletes those that stale-dist-caches.sh writes (docs/adr/0228)"; fi
if visual_step "uses: actions/checkout@" | grep -qxF '          fetch-depth: 0'; then ok; else ng "ci.yml: visual checks out the whole history"; fi
REPORT_IF="if: failure() && steps.check.outcome == 'failure'"
if visual_step "name: The pages match the references" | grep -qxF '      - id: check' || grep -B1 'name: The pages match the references' "$VJ" | grep -qxF '      - id: check'; then ok; else ng "ci.yml: the step of check.sh has the id check"; fi
if visual_step "name: Report of the changed pages" | grep -qxF "        $REPORT_IF" &&
  visual_step "name: Report of the changed pages" | grep -qF 'sh scripts/visual/report.sh "$RUNNER_TEMP/visual.txt" visual-pdfs "$RUNNER_TEMP/visual-diff"' &&
  visual_step "name: Report of the changed pages" | grep -qF 'GH_TOKEN: ${{ github.token }}'; then ok; else
  ng "ci.yml: report.sh runs only when the check failed, with the token of the run"
fi
if visual_step "name: Report of the changed pages" | grep -qF "github.event.pull_request.base.sha" &&
  visual_step "name: Report of the changed pages" | grep -qF "github.event.before"; then ok; else ng "ci.yml: the base of the report is the base of the pull request or the commit before the push"; fi
if visual_step "name: Upload the report of the changed pages" | grep -qxF "        $REPORT_IF" &&
  visual_step "name: Upload the report of the changed pages" | grep -qxF '          name: visual-diff'; then ok; else ng "ci.yml: visual-diff is uploaded only when the check failed"; fi

# ---------------------------------------------------------------- determinism.sh

# docs/adr/0071: the list has the SHA-256 of stdout and of stderr and the
# exit code of each build, and diagnostics is an input. The fake golem
# writes build/out; in the folder named diagnostics it writes $FAKE_STDERR
# to stderr and exits with 1. The manuals are empty projects under
# GOLEM_MANUAL_ROOT with a LICENSE each, built without their fonts. An
# input built with fonts/ja.otf and fonts/latin.otf gets build/fonts too.
DET=$WORK/determinism
mkdir -p "$DET/bin" "$DET/root/manual" "$DET/root/manual-dev"
: >"$DET/root/manual/manifest.toml"
: >"$DET/root/manual-dev/manifest.toml"
: >"$DET/root/manual/LICENSE"
: >"$DET/root/manual-dev/LICENSE"
cat >"$DET/bin/golem" <<'GOLEM'
#!/bin/sh
mkdir -p build
printf 'out\n' >build/out
if [ -f fonts/ja.otf ] && [ -f fonts/latin.otf ]; then printf 'fonts\n' >build/fonts; fi
if [ "$(basename "$(pwd)")" = diagnostics ]; then
  printf '%s\n' "$FAKE_STDERR" >&2
  exit 1
fi
GOLEM
chmod +x "$DET/bin/golem"
determinism() {
  GOLEM=$DET/bin/golem GOLEM_MANUAL_ROOT=$DET/root GOLEM_MANUAL_SKIP_FONTS=1 \
    GOLEM_MANUAL_COMMIT=0 GOLEM_MANUAL_TAG=v0 FAKE_STDERR=$1 \
    sh "$HERE/../determinism.sh"
}
: >"$WORK/in"
run determinism '{"diagnostics":[{"code":"G00000"}]}'
cp "$WORK/out" "$DET/first"
expect "determinism: a build that exits with 1" 0
if grep -qx 'exit 1  diagnostics' "$WORK/out"; then ok; else ng "determinism: the exit code of diagnostics"; fi
if grep -qx 'exit 0  sample' "$WORK/out"; then ok; else ng "determinism: the exit code of sample"; fi
if grep -qx 'exit 0  functions' "$WORK/out"; then ok; else ng "determinism: the fixture of the functions of .emet (docs/adr/0162)"; fi
for book in complex-vertical complex-horizontal; do
  if grep -qx "exit 0  $book" "$WORK/out" && grep -qE "^[0-9a-f]{64}  $book/stdout\$" "$WORK/out" && grep -qE "^[0-9a-f]{64}  $book/stderr\$" "$WORK/out"; then ok; else ng "determinism: the book $book (docs/adr/0175)"; fi
  if grep -qE "^[0-9a-f]{64}  $book/build/fonts\$" "$WORK/out"; then ok; else ng "determinism: $book is built with the fonts copied in (docs/adr/0175)"; fi
done
if grep -qE '^[0-9a-f]{64}  diagnostics/stderr$' "$WORK/out"; then ok; else ng "determinism: the stderr of diagnostics"; fi
if grep -qx 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  sample/stdout' "$WORK/out"; then ok; else ng "determinism: the empty stdout of sample"; fi
if grep -qE '^[0-9a-f]{64}  manual/build/out$' "$WORK/out"; then ok; else ng "determinism: the files of a manual"; fi
run determinism '{"diagnostics":[{"code":"G00001"}]}'
expect "determinism: another stderr" 0
if [ "$(grep '  diagnostics/stderr$' "$DET/first")" != "$(grep '  diagnostics/stderr$' "$WORK/out")" ]; then ok; else ng "determinism: a change of one character in stderr changes the list"; fi
if [ "$(grep -v '  diagnostics/stderr$' "$DET/first")" = "$(grep -v '  diagnostics/stderr$' "$WORK/out")" ]; then ok; else ng "determinism: the rest of the list stays"; fi

# --no-manuals leaves out the manuals, whose colophon has the commit; the
# rest of the list is the same (docs/adr/0173)
determinism_no_manuals() {
  GOLEM=$DET/bin/golem GOLEM_MANUAL_ROOT=$DET/root GOLEM_MANUAL_SKIP_FONTS=1 \
    GOLEM_MANUAL_COMMIT=0 GOLEM_MANUAL_TAG=v0 FAKE_STDERR=$1 \
    sh "$HERE/../determinism.sh" --no-manuals
}
run determinism_no_manuals '{"diagnostics":[{"code":"G00000"}]}'
expect "determinism: --no-manuals" 0
if grep -qE '  manual(-dev)?/' "$WORK/out"; then ng "determinism: --no-manuals lists no file of the manuals"; else ok; fi
if [ "$(grep -vE '  manual(-dev)?/' "$DET/first")" = "$(cat "$WORK/out")" ]; then ok; else ng "determinism: --no-manuals is the list without the manuals"; fi
determinism_unknown() {
  GOLEM=$DET/bin/golem GOLEM_MANUAL_ROOT=$DET/root sh "$HERE/../determinism.sh" --no-such-option
}
run determinism_unknown
expect "determinism: an unknown option" 2

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

# ---------------------------------------------------------------- race-needed.sh
# (docs/adr/0075-race-search-repetitions.md)

# The fake gh writes its arguments to $WORK/gh.args and prints
# $FAKE_HEAD, the head of the last successful run of race.yml.
RN=$WORK/race-needed
mkdir -p "$RN"
cat >"$RN/gh" <<GH
#!/bin/sh
printf '%s\n' "\$*" >"$WORK/gh.args"
[ -z "\${FAKE_GH_FAIL-}" ] || exit 1
printf '%s\n' "\$FAKE_HEAD"
GH
chmod +x "$RN/gh"
A=0123456789abcdef0123456789abcdef01234567
B=89abcdef0123456789abcdef0123456789abcdef
race_needed() { GH=$RN/gh FAKE_HEAD=$1 sh "$HERE/race-needed.sh" "$2"; }
: >"$WORK/in"
run race_needed "$A" "$A"
expect "race-needed: main has not changed" 0 false
if [ "$(cat "$WORK/gh.args" 2>/dev/null)" = "run list --workflow race.yml --branch main --status success --limit 1 --json headSha --jq .[0].headSha" ]; then ok; else ng "race-needed: the last successful run of race.yml on main"; fi
run race_needed "$B" "$A"
expect "race-needed: main has changed" 0 true
run race_needed "" "$A"
expect "race-needed: no successful run yet" 0 true
run race_needed null "$A"
expect "race-needed: no successful run yet (null)" 0 true
run race_needed "not a commit" "$A"
expect "race-needed: gh answers with what is not a commit" 1
run race_needed "$A" "${A%?}"
expect "race-needed: a SHA that is not a commit" 2
FAKE_GH_FAIL=1 run race_needed "$A" "$A"
expect "race-needed: gh fails" 1
# another workflow (docs/adr/0204); the assignment before the function
# call above stays set in some shells (bash in POSIX mode)
unset FAKE_GH_FAIL
race_needed_in() { GH=$RN/gh FAKE_HEAD=$1 sh "$HERE/race-needed.sh" "$2" "$3"; }
run race_needed_in "$A" "$A" enum.yml
expect "race-needed: enum.yml has not changed" 0 false
if [ "$(cat "$WORK/gh.args" 2>/dev/null)" = "run list --workflow enum.yml --branch main --status success --limit 1 --json headSha --jq .[0].headSha" ]; then ok; else ng "race-needed: the last successful run of enum.yml on main"; fi
run race_needed_in "$A" "$A" enum
expect "race-needed: a workflow that is not a file" 2

# ---------------------------------------------------------------- github-anchors.sh
# (docs/adr/0235)

# A docs/diagnostics.md of three codes, and headings that are not of a code
# (another level, more than the code); the fake gh prints $FAKE_HTML, a
# small HTML of GitHub, and writes its arguments to $WORK/gh.args.
GA=$WORK/github-anchors
mkdir -p "$GA/root/docs"
cat >"$GA/root/docs/diagnostics.md" <<'MD'
# diagnostics

## G01001

a

### G01004

## G01002

b

## G01005（説明）

## G01003
MD
cat >"$GA/gh" <<GH
#!/bin/sh
printf '%s\n' "\$*" >"$WORK/gh.args"
[ -z "\${FAKE_GH_FAIL-}" ] || exit 1
cat "\$FAKE_HTML"
GH
chmod +x "$GA/gh"
ga_html() { # ga_html CODE...: the HTML with the ids of the codes
  for c in "$@"; do
    printf '<div class="markdown-heading"><h2 class="heading-element">%s</h2><a id="user-content-%s" class="anchor" href="#%s"></a></div>\n' "$c" "$(printf '%s' "$c" | tr G g)" "$(printf '%s' "$c" | tr G g)"
  done >"$GA/html"
}
github_anchors() { GH=$GA/gh FAKE_HTML=$GA/html GOLEM_ROOT=$GA/root GITHUB_REPOSITORY=tett23/golem sh "$HERE/github-anchors.sh" "$@"; }
SHA_GA=0123456789abcdef0123456789abcdef01234567
: >"$WORK/in"
ga_html G01001 G01002 G01003
run github_anchors "$SHA_GA"
expect "github-anchors: I2 every code has its id" 0
if [ "$(cat "$WORK/gh.args" 2>/dev/null)" = "api repos/tett23/golem/contents/docs/diagnostics.md?ref=$SHA_GA -H Accept: application/vnd.github.html" ]; then ok; else ng "github-anchors: the HTML of docs/diagnostics.md of the commit, rendered by GitHub"; fi
ga_html G01001 G01003
run github_anchors "$SHA_GA"
expect "github-anchors: I2 a code without its id" 1
if grep -q 'G01002' "$WORK/err" && ! grep -q 'G01001\|G01003' "$WORK/err"; then ok; else ng "github-anchors: names the code without its id, and only it"; fi
# ### G01004 and ## G01005（説明） are not headings of a code: their ids
# are not asked for above
if ! grep -q 'G01004\|G01005' "$WORK/err"; then ok; else ng "github-anchors: ### G01004 and ## G01005（説明） are not codes"; fi
: >"$GA/html"
run github_anchors "$SHA_GA"
expect "github-anchors: an HTML without any id (a file over the size GitHub renders)" 1
ga_html G01001 G01002 G01003
FAKE_GH_FAIL=1 run github_anchors "$SHA_GA"
expect "github-anchors: a commit the API does not give" 1
FAKE_GH_FAIL=1 GITHUB_ANCHORS_SKIP_UNREACHABLE=1 run github_anchors "$SHA_GA"
expect "github-anchors: a commit the API does not give, of a fork" 0
if grep -q 'skipped' "$WORK/out"; then ok; else ng "github-anchors: says that it skipped"; fi
unset FAKE_GH_FAIL GITHUB_ANCHORS_SKIP_UNREACHABLE
run github_anchors
expect "github-anchors: no commit" 2
run github_anchors main
expect "github-anchors: a commit that is not a SHA" 2

# ---------------------------------------------------------------- scripts/models/check.sh
# (docs/adr/0235)

# The fake java writes ---Trace--- for the commands of $FAKE_FOUND and
# nothing for the others, as Alloy does; FAKE_JAVA_FAIL makes it fail. A
# model of three commands and its expected.txt.
MC=$WORK/models
mkdir -p "$MC/root/docs/m/models" "$MC/bin"
: >"$MC/alloy.jar"
cat >"$MC/root/docs/m/models/a.als" <<'ALS'
sig A {}
run one { some A } for 3
run two { no A } for 3
check three { some A } for 3
ALS
cat >"$MC/bin/java" <<'JAVA'
#!/bin/sh
[ -z "${FAKE_JAVA_FAIL-}" ] || { echo "java: failed" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case $1 in -c) cmd=$2; shift 2 ;; *) shift ;; esac
done
case " $FAKE_FOUND " in *" $cmd "*) printf '%s\n' '---Trace---' 'univ={A$0}' ;; esac
exit 0
JAVA
chmod +x "$MC/bin/java"
models_check() { GOLEM_ROOT=$MC/root ALLOY_JAR=$MC/alloy.jar JAVA=$MC/bin/java JOBS=2 FAKE_FOUND="one three" sh "$HERE/../models/check.sh" "$@"; }
printf 'one found\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: I3 every command as expected.txt says" 0 "docs/m/models/a.als one found
docs/m/models/a.als two none
docs/m/models/a.als three found"
printf 'one none\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: I3 a command with a solution that expected.txt says none" 1
if grep -q 'a.als one: found, but expected.txt says none' "$WORK/err"; then ok; else ng "models: names the command"; fi
printf 'one found\ntwo found\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: I3 a command without a solution that expected.txt says found" 1
if grep -q 'a.als two: none, but expected.txt says found' "$WORK/err"; then ok; else ng "models: names the command without a solution"; fi
printf '# the results\none found\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: a command not in expected.txt is not run" 0 "check: not in expected.txt, not run: docs/m/models/a.als two
docs/m/models/a.als one found
docs/m/models/a.als three found"
printf 'one found\nfour none\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: a command of expected.txt that the model does not have" 1
if grep -q 'no command four' "$WORK/err"; then ok; else ng "models: names the command the model does not have"; fi
printf 'one maybe\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: a result that is not found nor none" 1
printf 'one found\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
FAKE_JAVA_FAIL=1 run models_check
expect "models: a run of Alloy that fails is not none" 1
unset FAKE_JAVA_FAIL
rm "$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: a model without expected.txt" 1
run models_check x
expect "models: an argument" 2

# ---------------------------------------------------------------- race.yml
# (docs/adr/0075-race-search-repetitions.md)

RACE_YML=$HERE/../../.github/workflows/race.yml
if [ -f "$RACE_YML" ]; then ok; else ng "race.yml: exists"; fi
# once a day, and by hand
if grep -qE '^    - cron: "[0-9]+ [0-9]+ \* \* \*"$' "$RACE_YML" && grep -qx '  workflow_dispatch:' "$RACE_YML"; then ok; else ng "race.yml: a schedule of once a day and workflow_dispatch"; fi
# it reads the repository and the runs, and writes nothing
if [ "$(awk '/^permissions:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z]/' "$RACE_YML")" = "  contents: read
  actions: read" ]; then ok; else ng "race.yml: the permissions are contents: read and actions: read"; fi
if grep -qE ': *write' "$RACE_YML" || grep -q 'actions/cache@' "$RACE_YML"; then ng "race.yml: nothing is written, the caches are only restored"; else ok; fi
if grep -qF 'GH_TOKEN: ${{ github.token }}' "$RACE_YML" && grep -qF 'sh scripts/ci/race-needed.sh "$GITHUB_SHA"' "$RACE_YML"; then ok; else ng "race.yml: race-needed.sh decides with the token of the run"; fi
# the tests run with GOLEM_RACE_TESTS, and only the three race tests
RT=$WORK/race-tests
awk '/name: The race tests/ { on = 1; next } on && /^      - / { on = 0 } on' "$RACE_YML" >"$RT"
if grep -qx '          GOLEM_RACE_TESTS: "40"' "$RT"; then ok; else ng "race.yml: the race tests have GOLEM_RACE_TESTS=40"; fi
if [ "$(grep -c 'cabal test' "$RACE_YML")" = 2 ] &&
  grep -qx '          cabal test golem-driver-parallel-test golem-font-race-test' "$RT" &&
  grep -qx "          cabal test golem-font-test --test-option=-p --test-option='/one font from many threads/'" "$RT"; then ok; else
  ng "race.yml: only golem-driver-parallel-test, golem-font-race-test and the concurrency tests of golem-font-test run"
fi
if grep -qF 'one font from many threads' "$HERE/../../modules/golem-font/test/ConcurrencySpec.hs"; then ok; else ng "race.yml: the pattern names the group of ConcurrencySpec"; fi
if awk -v c="if: steps.needed.outputs.run == 'true'" 'index($0, "name: The race tests") { getline; if (index($0, c)) f = 1 } END { exit !f }' "$RACE_YML"; then ok; else ng "race.yml: the tests run only when race-needed.sh says so"; fi

# ---------------------------------------------------------------- advisories.yml
# (docs/adr/0157-check-wasmtime-pin-against-advisories.md)

ADV_YML=$HERE/../../.github/workflows/advisories.yml
if [ -f "$ADV_YML" ]; then ok; else ng "advisories.yml: exists"; fi
# once a day, and by hand; never on a pull request or a push
if grep -qE '^    - cron: "[0-9]+ [0-9]+ \* \* \*"$' "$ADV_YML" && grep -qx '  workflow_dispatch:' "$ADV_YML" &&
  ! grep -qE '^  (pull_request|push):' "$ADV_YML"; then ok; else ng "advisories.yml: a schedule of once a day and workflow_dispatch only"; fi
if [ "$(awk '/^permissions:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z]/' "$ADV_YML")" = "  contents: read" ] &&
  ! grep -qE ': *write' "$ADV_YML"; then ok; else ng "advisories.yml: the permissions are contents: read only"; fi
if grep -qF 'GH_TOKEN: ${{ github.token }}' "$ADV_YML" && grep -qx '        run: sh scripts/wasmtime-advisories.sh' "$ADV_YML"; then ok; else ng "advisories.yml: runs wasmtime-advisories.sh with the token of the run"; fi

# ---------------------------------------------------------------- test-suites.sh
# (docs/adr/0140-ci-split-test-runners-and-visual-pdfs-first.md)

test_suites() { sh "$HERE/test-suites.sh" "$@"; }
TS=$WORK/test-suites
mkdir -p "$TS/golem-driver" "$TS/golem-pdf" "$TS/golem-plain" "$TS/other-dir"
printf 'cabal-version: 3.0\nname:          golem-driver\n\nlibrary\n  exposed-modules: A\n\ntest-suite golem-driver-test\n  type: exitcode-stdio-1.0\n\ntest-suite golem-driver-parallel-test\n  type: exitcode-stdio-1.0\n' >"$TS/golem-driver/golem-driver.cabal"
printf 'cabal-version: 3.0\nname: golem-pdf\n\nlibrary\n\nTest-Suite   golem-pdf-test\n  type: exitcode-stdio-1.0\n' >"$TS/golem-pdf/golem-pdf.cabal"
printf 'cabal-version: 3.0\nname: golem-plain\n\nlibrary\n' >"$TS/golem-plain/golem-plain.cabal"
# the name of the package, not of its directory
printf 'cabal-version: 3.0\nname: golem-renamed\n\ntest-suite renamed-test\n  type: exitcode-stdio-1.0\n' >"$TS/other-dir/golem-renamed.cabal"
: >"$WORK/in"
run test_suites driver "$TS"
expect "test-suites: driver has the suites of golem-driver" 0 "golem-driver:test:golem-driver-test
golem-driver:test:golem-driver-parallel-test"
run test_suites rest "$TS"
expect "test-suites: rest has every other suite, by the name of its package" 0 "golem-pdf:test:golem-pdf-test
golem-renamed:test:renamed-test"
run test_suites all "$TS"
expect "test-suites: all is all of cabal test all" 0 "all"
run test_suites
expect "test-suites: no argument" 2
run test_suites tests "$TS"
expect "test-suites: an unknown part" 2
run test_suites driver "$WORK/no-such-modules"
expect "test-suites: no such directory" 1
# the real modules/: driver and rest share no suite, and together they are
# every test-suite of modules/*/*.cabal
test_suites driver >"$WORK/ts-driver" 2>"$WORK/err" || true
test_suites rest >"$WORK/ts-rest" 2>>"$WORK/err" || true
for f in "$HERE"/../../modules/*/*.cabal; do
  pkg=$(awk 'tolower($1) == "name:" { print $2; exit }' "$f")
  awk -v p="$pkg" 'tolower($1) == "test-suite" { print p ":test:" $2 }' "$f"
done | LC_ALL=C sort >"$WORK/ts-every"
if [ -s "$WORK/ts-driver" ] && [ -s "$WORK/ts-rest" ] &&
  [ -z "$(LC_ALL=C sort "$WORK/ts-driver" "$WORK/ts-rest" | uniq -d)" ] &&
  [ "$(cat "$WORK/ts-driver" "$WORK/ts-rest" | LC_ALL=C sort)" = "$(cat "$WORK/ts-every")" ] &&
  ! grep -qv '^golem-driver:' "$WORK/ts-driver"; then ok; else
  ng "test-suites: driver and rest of modules/ split every test suite in two"
fi

# ---------------------------------------------------------------- run-all.sh

run_all() { sh "$HERE/run-all.sh" "$@"; }
RA=$WORK/run-all
mkdir -p "$RA"
# the first ends last; the output is in the order of the arguments
printf 'sleep 1\necho one\necho one-err >&2\n' >"$RA/one.sh"
printf 'echo two\n' >"$RA/two.sh"
: >"$WORK/in"
run run_all "$RA/one.sh" "$RA/two.sh"
if [ "$CODE" = 0 ] && [ "$(grep -v '^==> ' "$WORK/out")" = "one
one-err
two" ] && [ "$(grep -c '^==> ' "$WORK/out")" = 2 ]; then ok; else ng "run-all: the outputs of the scripts, in the order of the arguments"; fi
if grep -q "^==> $RA/one.sh: exit 0" "$WORK/out"; then ok; else ng "run-all: a header names the script and its exit code"; fi
# the scripts run at the same time: each waits for the other's file
printf 'touch "%s/a"; i=0; while [ ! -f "%s/b" ]; do i=$((i + 1)); [ $i -lt 100 ] || exit 9; sleep 0.1; done\n' "$RA" "$RA" >"$RA/a.sh"
printf 'touch "%s/b"; i=0; while [ ! -f "%s/a" ]; do i=$((i + 1)); [ $i -lt 100 ] || exit 9; sleep 0.1; done\n' "$RA" "$RA" >"$RA/b.sh"
run run_all "$RA/a.sh" "$RA/b.sh"
expect "run-all: the scripts run at the same time" 0
# a failure fails the run, and the failed script is named on stderr; the
# others still run to their end
printf 'exit 3\n' >"$RA/three.sh"
run run_all "$RA/three.sh" "$RA/two.sh"
if [ "$CODE" = 1 ] && grep -qx "run-all: $RA/three.sh failed (exit 3)" "$WORK/err" && grep -qx two "$WORK/out"; then ok; else ng "run-all: a failed script fails the run and is named"; fi
# no standard input reaches the scripts
printf 'cat\n' >"$RA/cat.sh"
printf 'from stdin\n' >"$WORK/in"
run run_all "$RA/cat.sh"
if [ "$CODE" = 0 ] && ! grep -q 'from stdin' "$WORK/out"; then ok; else ng "run-all: the scripts read no standard input"; fi
: >"$WORK/in"
run run_all
expect "run-all: no argument" 2
# -t SECONDS stops a script still running after SECONDS seconds, writes
# what it wrote so far after a header that says so, and fails the run;
# the output of run-all.sh is closed when it ends, so a pipe after it
# does not wait for the stopped script (docs/adr/0154)
printf 'echo before\nsleep 30\necho after\n' >"$RA/hang.sh"
T0=$(date +%s)
CODE=0
sh "$HERE/run-all.sh" -t 2 "$RA/hang.sh" "$RA/two.sh" <"$WORK/in" 2>"$WORK/err" | cat >"$WORK/out" || true
sh "$HERE/run-all.sh" -t 2 "$RA/hang.sh" "$RA/two.sh" </dev/null >/dev/null 2>&1 || CODE=$?
T1=$(date +%s)
if [ $((T1 - T0)) -lt 20 ] && [ "$CODE" = 1 ] &&
  grep -A1 -xF "==> $RA/hang.sh: timed out after 2 s" "$WORK/out" | tail -1 | grep -qx before &&
  ! grep -qx after "$WORK/out" &&
  grep -q "^==> $RA/two.sh: exit 0" "$WORK/out"; then ok; else ng "run-all: -t stops a script over its seconds and writes what it wrote"; fi
if [ "$(cat "$WORK/err")" = "run-all: $RA/hang.sh timed out (2 s)" ]; then ok; else ng "run-all: a stopped script is named on stderr"; fi
run run_all -t 0 "$RA/two.sh"
expect "run-all: -t 0" 2
run run_all -t x "$RA/two.sh"
expect "run-all: -t of a word" 2

# ---------------------------------------------------------------- golem-driver's suites and threads
# (docs/adr/0146-threaded-golem-driver-test.md)

# stanza NAME: the lines of the test-suite NAME of golem-driver.cabal
DRIVER_CABAL=$HERE/../../modules/golem-driver/golem-driver.cabal
stanza() { awk -v n="test-suite $1" '$0 == n { on = 1; next } on && /^[^ \t-]/ { on = 0 } on' "$DRIVER_CABAL"; }
# modules NAME: the other-modules of the test-suite NAME, one per line
modules_of() { stanza "$1" | awk '/^  other-modules:/ { on = 1; next } on && /^  [a-z-]+:/ { on = 0 } on { print $1 }'; }
if stanza golem-driver-test | grep -Eq '^  ghc-options: .*-threaded' && stanza golem-driver-test | grep -qF '"-with-rtsopts=-N"'; then ok; else
  ng "golem-driver.cabal: golem-driver-test is built -threaded with -N"
fi
if [ -n "$(stanza golem-driver-global-test)" ] && ! stanza golem-driver-global-test | grep -q -- '-threaded'; then ok; else
  ng "golem-driver.cabal: golem-driver-global-test is a suite without -threaded"
fi
if ! modules_of golem-driver-test | grep -Eqx 'PluginsSpec|LocaleSpec' &&
  modules_of golem-driver-global-test | grep -qx PluginsSpec && modules_of golem-driver-global-test | grep -qx LocaleSpec; then ok; else
  ng "golem-driver.cabal: PluginsSpec and LocaleSpec are in golem-driver-global-test, not in golem-driver-test"
fi
# the threaded suite changes no state of the process: tasty runs its tests
# at the same time, and the others would read the state half changed
GLOBAL_STATE=$(for m in $(modules_of golem-driver-test) Main; do
  grep -lwE 'withEnv|setEnv|unsetEnv|setLocaleEncoding|setCurrentDirectory|withCurrentDirectory' "$HERE/../../modules/golem-driver/test/$m.hs" 2>/dev/null
done)
if [ -n "$(modules_of golem-driver-test)" ] && [ -z "$GLOBAL_STATE" ]; then ok; else
  ng "golem-driver-test: no test changes the state of the process ($GLOBAL_STATE)"
fi
# the time-out of the tests is hangTimeout of Support.hs, in one place
# (docs/adr/0237-raise-the-hang-time-outs-of-golem-driver-test-to-300-seconds.md)
OWN_TIMEOUT=$(for m in $(modules_of golem-driver-test) Main; do
  [ "$m" = Support ] || grep -lw 'mkTimeout' "$HERE/../../modules/golem-driver/test/$m.hs" 2>/dev/null
done)
if [ -n "$(modules_of golem-driver-test)" ] && [ -z "$OWN_TIMEOUT" ] &&
  grep -qw 'hangTimeout' "$HERE/../../modules/golem-driver/test/Support.hs"; then ok; else
  ng "golem-driver-test: no module but Support.hs has mkTimeout, and Support.hs has hangTimeout ($OWN_TIMEOUT)"
fi

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
# golem-test-support depends on no package of this repository (docs/adr/0087)
deps "golem-test-support depends on a local package" 1 "$PLANS/support-local-direct.json" golem-syntax,
deps "golem-test-support reaches a local package through Hackage" 1 "$PLANS/support-local-through-hackage.json" golem-syntax,
deps "golem-test-support depends on Hackage packages only" 0 "$PLANS/support-hackage-only.json"
# golem-doc-gen, the generators of the semantic IR, is only for the test
# suites too, and may depend on golem-doc (docs/adr/0191)
deps "a library depends directly on golem-doc-gen" 1 "$PLANS/docgen-direct.json" golem-driver:lib
deps "a library reaches golem-doc-gen through another package" 1 "$PLANS/docgen-transitive.json" golem-driver:lib golem-plugin:lib
deps "only test suites depend on golem-doc-gen, which depends on golem-doc" 0 "$PLANS/docgen-test-only.json"
deps "no such file" 2 "$WORK/no-such-plan.json"
printf 'not json\n' >"$WORK/bad.json"
deps "not JSON" 2 "$WORK/bad.json"
printf '{"cabal-version":"3.16.1.0"}\n' >"$WORK/no-plan.json"
deps "no install-plan" 2 "$WORK/no-plan.json"
: >"$WORK/in"
run test_only_deps
expect "test-only-deps: no argument" 2

# ---------------------------------------------------------------- determinism-hashes.sh
# (docs/adr/0173)

HASHES=$HERE/testdata/determinism-hashes
determinism_hashes() { sh "$HERE/determinism-hashes.sh" "$@"; }
# hashes NAME CODE LIST [LINE...]: compares LIST with hashes.txt of the
# testdata; the exit code, and the LINEs on stdout (exactly these, when the
# code is 1)
hashes() {
  name=$1 code=$2 list=$3
  shift 3
  : >"$WORK/in"
  run determinism_hashes "$HASHES/$list" "$HASHES/hashes.txt"
  if [ "$CODE" != "$code" ]; then
    ng "determinism-hashes: $name (exit code $CODE, expected $code)"
    return 0
  fi
  for l in "$@"; do
    if ! grep -qxF -- "$l" "$WORK/out"; then
      ng "determinism-hashes: $name (\"$l\" is not on stdout)"
      return 0
    fi
  done
  if [ "$code" = 1 ] && [ "$(wc -l <"$WORK/out" | tr -d ' ')" != $# ]; then
    ng "determinism-hashes: $name (stdout has not $# lines)"
    return 0
  fi
  ok
}
A=1111111111111111111111111111111111111111111111111111111111111111
C=3333333333333333333333333333333333333333333333333333333333333333
E=4444444444444444444444444444444444444444444444444444444444444444
hashes "the same list" 0 same.txt
hashes "the manuals are left out" 0 manuals.txt
hashes "one hash differs" 1 changed.txt "hashes.txt: $A  sample/build/html/index.html" "outputs: $E  sample/build/html/index.html"
hashes "a line is missing" 1 missing.txt "hashes.txt: $C  sample/stderr"
hashes "a line is more" 1 extra.txt "outputs: $E  sample/build/html/style.css"
hashes "an exit code differs" 1 exit.txt "hashes.txt: exit 0  sample" "outputs: exit 1  sample"
: >"$WORK/in"
run determinism_hashes "$HASHES/same.txt" "$WORK/no-such-hashes.txt"
expect "determinism-hashes: no hashes.txt" 2
run determinism_hashes "$HASHES/same.txt"
expect "determinism-hashes: one argument" 2

# ---------------------------------------------------------------- doc-deps.sh
# (docs/adr/0173)

DOC_PLANS=$HERE/testdata/doc-deps
doc_deps() { sh "$HERE/doc-deps.sh" "$@"; }
# docdeps NAME CODE PLAN [LINE...]: the exit code, and the lines on stderr
# (exactly these, when the code is 1)
docdeps() {
  name=$1 code=$2 plan=$3
  shift 3
  : >"$WORK/in"
  run doc_deps "$plan"
  if [ "$CODE" != "$code" ]; then
    ng "doc-deps: $name (exit code $CODE, expected $code)"
    return 0
  fi
  for l in "$@"; do
    if ! grep -qxF -- "$l" "$WORK/err"; then
      ng "doc-deps: $name (\"$l\" is not on stderr)"
      return 0
    fi
  done
  if [ "$code" = 1 ] && [ "$(wc -l <"$WORK/err" | tr -d ' ')" != $# ]; then
    ng "doc-deps: $name (stderr has not $# lines)"
    return 0
  fi
  ok
}
docdeps "the four packages as the ADR has them" 0 "$DOC_PLANS/ok.json"
docdeps "golem-doc depends on golem-assemble, and through it on golem-numerals" 1 "$DOC_PLANS/doc-assemble.json" \
  "doc-deps: golem-doc depends on golem-assemble" "doc-deps: golem-doc depends on golem-numerals"
docdeps "golem-doc reaches golem-numerals through another package" 1 "$DOC_PLANS/doc-numerals-through.json" \
  "doc-deps: golem-doc depends on golem-numerals"
docdeps "golem-bibliography depends on golem-doc" 1 "$DOC_PLANS/bibliography-doc.json" \
  "doc-deps: golem-bibliography depends on golem-doc"
docdeps "golem-numerals depends on golem-doc" 1 "$DOC_PLANS/numerals-doc.json" \
  "doc-deps: golem-numerals depends on golem-doc"
docdeps "the lib of a per-package element" 1 "$DOC_PLANS/per-package.json" \
  "doc-deps: golem-doc depends on golem-bibliography"
# the library of golem-typeset reaches none of the evaluation, the other
# outputs and the tools (docs/adr/0192)
docdeps "golem-typeset depends on golem-eval" 1 "$DOC_PLANS/typeset-eval.json" \
  "doc-deps: golem-typeset depends on golem-eval"
docdeps "a package missing from the plan" 2 "$DOC_PLANS/no-numerals.json"
docdeps "no such file" 2 "$WORK/no-such-plan.json"
printf 'not json\n' >"$WORK/bad.json"
docdeps "not JSON" 2 "$WORK/bad.json"
: >"$WORK/in"
run doc_deps
expect "doc-deps: no argument" 2

# ---------------------------------------------------------------- wasm-freeze.sh
# (docs/adr/0199 section 6, docs/adr/0202 section 2)

WF_DATA=$HERE/testdata/wasm-freeze
: >"$WORK/in"
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WF_DATA/wasm.freeze"
expect "wasm-freeze: the packages of both files have the same versions; cborg, skylighting, skylighting-core and the boot packages are not compared" 0
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WF_DATA/wasm-other-zlib-clib.freeze"
expect "wasm-freeze: another version of a package of both files fails" 1
if grep -qF "zlib-clib: 1.3.2 (native), 1.3.1 (wasm)" "$WORK/err"; then ok; else ng "wasm-freeze: names the package and both versions"; fi
# a boot package written in the wasm freeze is compared like the others:
# the boot packages stay out of cabal.project.wasm.freeze
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WF_DATA/wasm-with-time.freeze"
expect "wasm-freeze: time of the wasm GHC written in the wasm freeze fails" 1
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WORK/in"
expect "wasm-freeze: a wasm freeze without versions fails" 1
run sh "$HERE/wasm-freeze.sh"
expect "wasm-freeze: cabal.project.wasm.freeze has the versions of cabal.project.freeze" 0

# ---------------------------------------------------------------- wasm/compare.sh --check
# (docs/adr/0199 section 7)

WC_DATA=$HERE/testdata/wasm-compare
run sh "$HERE/../wasm/compare.sh" --check "$WC_DATA/native.txt" "$WC_DATA/native.txt"
expect "compare.sh --check: the same lists pass" 0
run sh "$HERE/../wasm/compare.sh" --check "$WC_DATA/native.txt" "$WC_DATA/changed-pdf.txt"
expect "compare.sh --check: a list with another SHA-256 of a PDF fails" 1
if grep -qF "kanikosen/pdf" "$WORK/out"; then ok; else ng "compare.sh --check: shows the line that differs"; fi
run sh "$HERE/../wasm/compare.sh" --check "$WC_DATA/native.txt"
expect "compare.sh --check: one list is a usage error" 2
run sh "$HERE/../wasm/compare.sh"
expect "compare.sh: no argument is a usage error" 2

# ---------------------------------------------------------------- wasm/legacy-eh.sh
# (docs/adr/0238 section 2, I1): small modules written as bytes. Each has
# one function of type [] -> []; the module with throw has one tag of it.
#   none     nop only
#   try      try catch_all end (the legacy exception handling)
#   exnref   block (result exnref) try_table (catch_all_ref 0) end
#            unreachable end throw_ref (the standard exception handling)
#   throw    throw 0 (in both forms)
#   broken   a header and a byte that is no section

if command -v node >/dev/null 2>&1 && node --v8-options 2>/dev/null | grep -q -- '--experimental-wasm-legacy-eh '; then
  LE=$WORK/legacy-eh
  mkdir -p "$LE"
  le_head='\000asm\001\000\000\000\001\004\001\140\000\000\003\002\001\000'
  printf "$le_head"'\012\004\001\002\000\013' >"$LE/none.wasm"
  printf "$le_head"'\012\010\001\006\000\006\100\031\013\013' >"$LE/try.wasm"
  printf "$le_head"'\012\017\001\015\000\002\151\037\100\001\003\000\013\000\013\012\013' >"$LE/exnref.wasm"
  printf "$le_head"'\015\003\001\000\000\012\006\001\004\000\010\000\013' >"$LE/throw.wasm"
  printf '\000asm\001\000\000\000\377' >"$LE/broken.wasm"
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/none.wasm"
  expect "legacy-eh: a module without exception handling passes (I1)" 0
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/try.wasm"
  expect "legacy-eh: a module with one try fails (I1)" 1
  if grep -qF 'legacy exception handling' "$WORK/err"; then ok; else ng "legacy-eh: says that the module has the legacy exception handling (I1)"; fi
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/exnref.wasm"
  expect "legacy-eh: a module with try_table and throw_ref only passes (I1)" 0
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/throw.wasm"
  expect "legacy-eh: a module with throw only passes (I1)" 0
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/broken.wasm"
  expect "legacy-eh: bytes that the default Node does not validate are another error (I1)" 2
  run sh "$HERE/../wasm/legacy-eh.sh" "$LE/nonexistent.wasm"
  expect "legacy-eh: a file that cannot be read is another error (I1)" 2
else
  skip 7 "legacy-eh: no node with --experimental-wasm-legacy-eh"
fi
run sh "$HERE/../wasm/legacy-eh.sh"
expect "legacy-eh: no argument is a usage error" 2
run sh "$HERE/../wasm/legacy-eh.sh" a.wasm b.wasm
expect "legacy-eh: two arguments are a usage error" 2

# ---------------------------------------------------------------- fetch-wasm-packages.sh
# (docs/adr/0202 section 2)

# A fake root with the script, fake archives of the two packages, their
# patches, and a fake curl that writes the archive of the URL to the file
# of -o. The SHA-256 of the script are those of the fake archives.
FW=$WORK/fetch-wasm
mkdir -p "$FW/root/scripts/wasm/patches" "$FW/src/skylighting-core-0.15" "$FW/src/skylighting-0.15" "$FW/archives" "$FW/bin"
printf 'module A\nimport Skylighting.Parser\n' >"$FW/src/skylighting-core-0.15/A.hs"
printf 'module B\nimport Skylighting.Loader\n' >"$FW/src/skylighting-0.15/B.hs"
for p in skylighting-core-0.15 skylighting-0.15; do (cd "$FW/src" && tar -czf "$FW/archives/$p.tar.gz" "$p"); done
cat >"$FW/root/scripts/wasm/patches/skylighting-core-0.15.patch" <<'EOF'
--- a/A.hs
+++ b/A.hs
@@ -1,2 +1 @@
 module A
-import Skylighting.Parser
EOF
cat >"$FW/root/scripts/wasm/patches/skylighting-0.15.patch" <<'EOF'
--- a/B.hs
+++ b/B.hs
@@ -1,2 +1 @@
 module B
-import Skylighting.Loader
EOF
fw_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
sed -e "s/^CORE_SHA=.*/CORE_SHA=$(fw_sha "$FW/archives/skylighting-core-0.15.tar.gz")/" \
  -e "s/^SKY_SHA=.*/SKY_SHA=$(fw_sha "$FW/archives/skylighting-0.15.tar.gz")/" \
  "$HERE/../fetch-wasm-packages.sh" >"$FW/root/scripts/fetch-wasm-packages.sh"
cat >"$FW/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$CURL_LOG"
out= url=
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; http*) url=$1 ;; esac
  shift
done
cp "$FW_ARCHIVES/${url##*/}" "$out" || exit 22
FAKE
chmod +x "$FW/bin/curl"
# fetch_wasm: runs the copy of the script with the fake curl
fetch_wasm() { env PATH="$FW/bin:$PATH" CURL_LOG="$FW/curl.log" FW_ARCHIVES="$FW/archives" sh "$FW/root/scripts/fetch-wasm-packages.sh"; }
# tree: every file under third_party/wasm-packages with its content
fw_tree() { (cd "$FW/root/third_party/wasm-packages" && find . -type f | LC_ALL=C sort | while read -r f; do printf '%s\n' "$f"; cat "$f"; done); }
: >"$FW/curl.log"
run fetch_wasm
expect "fetch-wasm-packages: the archives of the SHA-256 are unpacked and patched" 0
if grep -qF "https://hackage.haskell.org/package/skylighting-core-0.15/skylighting-core-0.15.tar.gz" "$FW/curl.log" &&
  grep -qF "https://hackage.haskell.org/package/skylighting-0.15/skylighting-0.15.tar.gz" "$FW/curl.log"; then ok; else ng "fetch-wasm-packages: the archives come from Hackage"; fi
if [ "$(cat "$FW/root/third_party/wasm-packages/skylighting-core-0.15/A.hs")" = "module A" ] &&
  [ "$(cat "$FW/root/third_party/wasm-packages/skylighting-0.15/B.hs")" = "module B" ]; then ok; else ng "fetch-wasm-packages: the patches are applied"; fi
fw_tree >"$FW/tree1"
run fetch_wasm
expect "fetch-wasm-packages: a second run passes" 0
fw_tree >"$FW/tree2"
if cmp -s "$FW/tree1" "$FW/tree2"; then ok; else ng "fetch-wasm-packages: two runs make the same tree"; fi
# one character of the SHA-256 changed: nothing is unpacked
rm -rf "$FW/root/third_party"
sed 's/^\(CORE_SHA=.\{63\}\)./\1x/' "$FW/root/scripts/fetch-wasm-packages.sh" >"$FW/bad-sha.sh"
cp "$FW/root/scripts/fetch-wasm-packages.sh" "$FW/good.sh"
cp "$FW/bad-sha.sh" "$FW/root/scripts/fetch-wasm-packages.sh"
run fetch_wasm
expect "fetch-wasm-packages: an archive of another SHA-256 fails" 1
if [ ! -e "$FW/root/third_party/wasm-packages/skylighting-core-0.15" ]; then ok; else ng "fetch-wasm-packages: an archive of another SHA-256 is not unpacked"; fi
cp "$FW/good.sh" "$FW/root/scripts/fetch-wasm-packages.sh"
# a patch that does not apply fails
printf -- '--- a/A.hs\n+++ b/A.hs\n@@ -1,2 +1 @@\n module X\n-import Y\n' >"$FW/root/scripts/wasm/patches/skylighting-core-0.15.patch"
run fetch_wasm
expect "fetch-wasm-packages: a patch that does not apply fails" 1

# ---------------------------------------------------------------- wasm-cache.sh
# (docs/adr/0219): why the toolchain cache of the wasm job missed, from
# the hit and whether the toolchain and the project are those of main

wasm_cache() { sh "$HERE/wasm-cache.sh" "$@"; }
: >"$WORK/in"
for t in true false; do
  for p in true false; do
    run wasm_cache true "$t" "$p"
    expect "wasm-cache: a hit (toolchain the same: $t, project the same: $p)" 0 "wasm-cache: the toolchain cache was restored"
  done
done
run wasm_cache false false true
expect "wasm-cache: the toolchain changed" 0 "wasm-cache: missed, as scripts/fetch-ghc-wasm.sh differs from main (the toolchain changed)"
run wasm_cache false false false
expect "wasm-cache: the toolchain and the project changed" 0 "wasm-cache: missed, as scripts/fetch-ghc-wasm.sh differs from main (the toolchain changed)"
run wasm_cache false true false
expect "wasm-cache: the project changed" 0 "wasm-cache: missed, as the project or its freeze differs from main"
run wasm_cache false true true
expect "wasm-cache: evicted" 0 "::warning::wasm-cache: missed, though the toolchain, the project and its freeze are those of main: the cache was evicted (docs/adr/0219)"
run wasm_cache false
expect "wasm-cache: too few arguments" 2
run wasm_cache yes true true
expect "wasm-cache: not true nor false" 2


# ---------------------------------------------------------------- stale-dist-caches.sh
# (docs/adr/0228): the IDs of the dist- caches of main to delete, from the
# list of gh cache list and the prefixes of the three families of the
# current keys (the keys without the commit hash)

stale() { sh "$HERE/stale-dist-caches.sh" "$@"; }
X64=dist-Linux-X64-ghc-9.10.3-aaaa-bbbb-
ARM=dist-Linux-ARM64-ghc-9.10.3-aaaa-bbbb-
WASM=dist-wasm-cccc-dddd-
# cache_rows ID DATE KEY [ID DATE KEY ...]: the list, one cache a line
cache_rows() {
  while [ $# -ge 3 ]; do
    printf '%s\t%s\t%s\n' "$1" "$2" "$3"
    shift 3
  done
}
: >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: an empty list writes nothing" 0 ""
cache_rows 11 2026-11-08T03:00:00Z "${X64}sha1" 12 2026-11-08T03:00:00Z "${ARM}sha1" 13 2026-11-08T03:00:00Z "${WASM}sha1" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: one cache of each family writes nothing" 0 ""
cache_rows 21 2026-11-08T01:00:00Z "${ARM}sha1" 23 2026-11-08T03:00:00Z "${ARM}sha3" 22 2026-11-08T02:00:00Z "${ARM}sha2" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: of three caches of a family, the two older are written" 0 "21
22"
cache_rows 32 2026-11-08T03:00:00Z "${WASM}sha1" 31 2026-11-08T03:00:00Z "${WASM}sha2" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: of two caches made at the same time, the smaller ID is written" 0 "31"
# the times of the API have a fraction of the second of any length:
# .72 is after .7, and a time without a fraction is before one with it
cache_rows 41 2026-11-08T03:22:56.72Z "${X64}sha1" 42 2026-11-08T03:22:56.7Z "${X64}sha2" 43 2026-11-08T03:22:56Z "${X64}sha3" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: the fractions of the second are compared as numbers" 0 "42
43"
cache_rows 51 2026-11-08T03:00:00Z "${X64}sha1" 52 2026-11-08T04:00:00Z dist-Linux-X64-ghc-9.10.2-aaaa-bbbb-sha2 53 2026-11-08T04:00:00Z dist-wasm-eeee-dddd-sha2 >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: the dist- caches of no family are written, even the newest" 0 "52
53"
cache_rows 61 2026-11-08T01:00:00Z ghc-Linux-X64-9.10.3-x 62 2026-11-08T01:00:00Z cabal-store-Linux-X64-ghc-9.10.3-x 63 2026-11-08T01:00:00Z "x${X64}sha1" 64 2026-11-08T03:00:00Z "${X64}sha2" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: no key that does not start with dist- is written (I4)" 0 ""
cache_rows 71 2026-11-08T03:00:00Z "${ARM}sha1" 72 2026-11-08T01:00:00Z "${X64}sha1" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: the prefix of x86-64 does not take the keys of aarch64" 0 ""
cache_rows 81 2026-11-08T01:00:00Z "${X64}sha1" 82 2026-11-08T02:00:00Z "${ARM}sha1" 83 2026-11-08T03:00:00Z "${X64}sha2" 84 2026-11-08T04:00:00Z "${ARM}sha2" >"$WORK/in"
run stale "$X64" "$ARM" "$WASM"
expect "stale-dist-caches: each family keeps its own newest (I3)" 0 "81
82"
# the response of gh cache list --json id,key,createdAt on main on
# 2026-11-08 (testdata), through the --jq of the caches job of ci.yml:
# two caches of each family a commit older than the newest, and a third
# dist-wasm (docs/adr/0078)
SDC_JQ='.[] | [.id, .createdAt, .key] | @tsv'
if job_lines caches | grep -qF -- "--jq '$SDC_JQ'"; then ok; else ng "ci.yml: caches writes the list with the --jq that the test of stale-dist-caches.sh reads"; fi
jq -r "$SDC_JQ" "$HERE/testdata/stale-dist-caches/main.json" >"$WORK/in"
run stale dist-Linux-X64-ghc-9.10.3-7641a7fffe79bb804fb6b4eccd3ed17d09ca861e25a646df9755060fa0b0ca62-e91b163216f435f37015ff67453bb2dff95f296da7a2e104b497e72e3247d12b- \
  dist-Linux-ARM64-ghc-9.10.3-7641a7fffe79bb804fb6b4eccd3ed17d09ca861e25a646df9755060fa0b0ca62-e91b163216f435f37015ff67453bb2dff95f296da7a2e104b497e72e3247d12b- \
  dist-wasm-02dd81e3eb0b193db19d41bed81ccb417e863b5bdfadc16d7cea7831b763eea0-06ccaeeceea4f2a730d1cd5041e88231d24171038588d870df08b367f536a362-
expect "stale-dist-caches: the caches of main of 2026-11-08" 0 "10180575021
10180816659
10180857328
10180865217"
# the input and the arguments are checked
: >"$WORK/in"
run stale
expect "stale-dist-caches: no prefix" 2
run stale ghc-Linux-X64-
expect "stale-dist-caches: a prefix that does not start with dist-" 2
run stale "dist-wasm- x"
expect "stale-dist-caches: a prefix with a space" 2
printf '1\t2026-11-08T03:00:00Z\n' >"$WORK/in"
run stale "$X64"
expect "stale-dist-caches: a line without a key" 1
printf 'x1\t2026-11-08T03:00:00Z\t%ssha1\n' "$X64" >"$WORK/in"
run stale "$X64"
expect "stale-dist-caches: an ID that is not a number" 1
printf '1\tyesterday\t%ssha1\n' "$X64" >"$WORK/in"
run stale "$X64"
expect "stale-dist-caches: a time that is not of the API" 1

# ---------------------------------------------------------------- wasm/compare.sh --deno, --browser
# (docs/adr/0234 section 5): the lists of Deno and of the browsers have the
# form of that of node:wasi, from a fake deno and a fake node

CB=$WORK/compare-hosts
mkdir -p "$CB/bin"
# deno run --allow-read --allow-write RUN.MJS build WASM DIR PDF: a PDF of
# the name of DIR, the warning of Deno and an empty JSON on stderr
cat >"$CB/deno" <<'FAKE'
#!/bin/sh
printf '%%PDF %s\n' "${7##*/}" >"$8"
printf '(node:123) ExperimentalWarning: WASI is an experimental feature and might change at any time\n[]\n' >&2
FAKE
# node RUN-BROWSER.MJS build BROWSER WASM DIR: the SHA-256 of a PDF on
# stdout, an empty JSON on stderr, for safari only; the input missing-font
# fails
cat >"$CB/bin/node" <<'FAKE'
#!/bin/sh
[ "$3" = safari ] || exit 9
case "$5" in
  */missing-font) printf -- '-\n'; printf '[{"severity":"error"}]' >&2; exit 1 ;;
esac
echo bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
printf '[]' >&2
FAKE
chmod +x "$CB/deno" "$CB/bin/node"
cb_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi; }
: >"$WORK/in"
# the form of the lists: three lines for each of the eight inputs
cb_form() {
  for name in kanikosen determinism pdf complex-vertical complex-horizontal broken-style missing-font broken-cmap; do
    grep -Eq "^([0-9a-f]{64}|-)  $name/pdf\$" "$1" && grep -Eq "^[0-9a-f]{64}  $name/diagnostics\$" "$1" && grep -Eq "^exit [0-9]+  $name\$" "$1" || return 1
  done
  [ "$(wc -l <"$1" | tr -d ' ')" = 24 ]
}
run env DENO="$CB/deno" sh "$HERE/../wasm/compare.sh" --deno golem.wasm
cp "$WORK/out" "$CB/deno.txt"
expect "compare.sh --deno: runs every input" 0
if cb_form "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the list has the form of that of node:wasi"; fi
if grep -qxF "$(printf '%%PDF kanikosen\n' | cb_sha)  kanikosen/pdf" "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the SHA-256 of the PDF that run.mjs wrote"; fi
if grep -qxF "$(printf '[]\n' | cb_sha)  kanikosen/diagnostics" "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the warning of Deno is not in the JSON"; fi
run env PATH="$CB/bin:$PATH" sh "$HERE/../wasm/compare.sh" --browser safari golem.wasm
cp "$WORK/out" "$CB/browser.txt"
expect "compare.sh --browser: runs every input" 0
if cb_form "$CB/browser.txt"; then ok; else ng "compare.sh --browser: the list has the form of that of node:wasi"; fi
if grep -qxF "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  kanikosen/pdf" "$CB/browser.txt"; then ok; else ng "compare.sh --browser: the SHA-256 that the page gave, of the browser asked"; fi
if grep -qxF -- "-  missing-font/pdf" "$CB/browser.txt" && grep -qxF "exit 1  missing-font" "$CB/browser.txt"; then ok; else ng "compare.sh --browser: no PDF and the exit code of a build with an error"; fi
run sh "$HERE/../wasm/compare.sh" --browser firefox golem.wasm
expect "compare.sh --browser: a browser that is not chromium nor safari is a usage error" 2
run sh "$HERE/../wasm/compare.sh" --browser chromium
expect "compare.sh --browser: without WASM is a usage error" 2
run sh "$HERE/../wasm/compare.sh" --deno
expect "compare.sh --deno: without WASM is a usage error" 2

# ---------------------------------------------------------------- wasm/compare.sh --wasmtime, broken-cmap
# (docs/adr/0238 sections 3 and 4): a fake root with compare.sh, the
# fixtures of the repository and a fake run-wasmtime.sh, whose PDF is the
# two bytes of Noto Serif JP at 30205 in hex; and a fake root whose Noto
# Serif JP is not the font that broken-cmap breaks

CW=$WORK/compare-wasmtime
mkdir -p "$CW/root/scripts/wasm"
cp "$HERE/../wasm/compare.sh" "$CW/root/scripts/wasm/compare.sh"
cp -R "$HERE/../determinism" "$CW/root/scripts/determinism"
ln -s "$HERE/../../modules" "$CW/root/modules"
cat >"$CW/root/scripts/wasm/run-wasmtime.sh" <<FAKE
#!/bin/sh
case "\$1" in
  compile) echo "compile \$2" >>"$CW/calls"; mkdir -p "\$3" && : >"\$3/golem.cwasm" ;;
  build)
    [ -f "\$2/golem.cwasm" ] || exit 9
    f=\$3/fonts/NotoSerifJP-Regular.otf
    if [ -f "\$f" ]; then od -An -tx1 -j30205 -N2 "\$f" | tr -d ' \n' >"\$4"; else rm -f "\$4"; fi
    printf '[]' >&2 ;;
  *) exit 9 ;;
esac
FAKE
run sh "$CW/root/scripts/wasm/compare.sh" --wasmtime golem.wasm
cp "$WORK/out" "$CW/list.txt"
expect "compare.sh --wasmtime: runs every input" 0
if cb_form "$CW/list.txt"; then ok; else ng "compare.sh --wasmtime: the list has the form of that of node:wasi"; fi
if [ "$(cat "$CW/calls")" = "compile golem.wasm" ]; then ok; else ng "compare.sh --wasmtime: golem.wasm is compiled once"; fi
if grep -qxF "$(printf '0001' | cb_sha)  kanikosen/pdf" "$CW/list.txt" && grep -qxF "$(printf 'ffff' | cb_sha)  broken-cmap/pdf" "$CW/list.txt"; then ok; else ng "compare.sh: broken-cmap is kanikosen with FF FF at 30205 of Noto Serif JP (I3)"; fi
if grep -qxF -- "-  missing-font/pdf" "$CW/list.txt"; then ok; else ng "compare.sh --wasmtime: no PDF"; fi
run sh "$HERE/../wasm/compare.sh" --wasmtime
expect "compare.sh --wasmtime: without WASM is a usage error" 2
run sh "$HERE/../wasm/compare.sh" --wasmtime a.wasm b.wasm
expect "compare.sh --wasmtime: two modules are a usage error" 2
CS=$WORK/compare-sha
mkdir -p "$CS/scripts/wasm" "$CS/modules/golem-driver/test/fixtures/kanikosen/fonts"
cp "$HERE/../wasm/compare.sh" "$CS/scripts/wasm/compare.sh"
printf 'not the font\n' >"$CS/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"
run sh "$CS/scripts/wasm/compare.sh" --native /nonexistent/golem
expect "compare.sh: another Noto Serif JP than the one broken-cmap breaks fails" 1
if grep -qF 'SHA-256' "$WORK/err"; then ok; else ng "compare.sh: says that the SHA-256 of the font differs"; fi

# ---------------------------------------------------------------- wasm/run-wasmtime.sh
# (docs/adr/0238 section 4): the arguments

run sh "$HERE/../wasm/run-wasmtime.sh"
expect "run-wasmtime: no argument is a usage error" 2
run sh "$HERE/../wasm/run-wasmtime.sh" compile golem.wasm
expect "run-wasmtime: compile without the folder is a usage error" 2
run sh "$HERE/../wasm/run-wasmtime.sh" build host dir
expect "run-wasmtime: build without the PDF is a usage error" 2
run sh "$HERE/../wasm/run-wasmtime.sh" run a b c
expect "run-wasmtime: an unknown command is a usage error" 2

# ---------------------------------------------------------------- fetch-chromium.sh, fetch-deno.sh
# (docs/adr/0234 sections 1 and 5): the arguments, and a zip of another
# SHA-256, from a fake curl, is not unpacked

FC=$WORK/fetch-pinned
mkdir -p "$FC/bin"
cat >"$FC/bin/curl" <<'FAKE'
#!/bin/sh
while [ $# -gt 0 ]; do
  case "$1" in -o) printf 'not the pinned zip\n' >"$2"; shift ;; esac
  shift
done
FAKE
chmod +x "$FC/bin/curl"
for f in browser/fetch-chromium.sh wasm/fetch-deno.sh; do
  n=${f##*/}
  run sh "$HERE/../$f" --bogus
  expect "$n: an unknown argument is a usage error" 2
  run sh "$HERE/../$f" --expected
  if [ "$CODE" = 0 ] && grep -Eqx '[0-9.]+ [0-9a-f]{64}' "$WORK/out"; then ok; else ng "$n --expected: the version and the SHA-256"; fi
  if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ]; then
    rm -rf "$FC/root"
    mkdir -p "$FC/root/scripts/browser" "$FC/root/scripts/wasm"
    cp "$HERE/../$f" "$FC/root/scripts/$f"
    run env PATH="$FC/bin:$PATH" sh "$FC/root/scripts/$f"
    expect "$n: a zip of another SHA-256 fails" 1
    if grep -qF 'SHA-256 mismatch' "$WORK/err" && [ ! -e "$FC/root/third_party" ]; then ok; else ng "$n: a zip of another SHA-256 is not unpacked"; fi
  else
    run sh "$HERE/../$f"
    expect "$n: another platform than x86-64 Linux fails" 1
    skip 2 "$n: the SHA-256 is checked on x86-64 Linux only"
  fi
done

# ---------------------------------------------------------------- browser/safari-versions.sh
# (docs/adr/0234 section 6, I7): the table of the versions of the safari
# job, from an Info.plist of the fixture and the variables of the runner.
# plutil is of macOS: scripts-macos runs these

if [ "$(uname -s)" = Darwin ]; then
  SV=$WORK/safari-versions
  mkdir -p "$SV"
  printf '#!/bin/sh\ncase "$1" in -productVersion) echo 15.8.2 ;; -buildVersion) echo 24H232 ;; esac\n' >"$SV/sw_vers"
  chmod +x "$SV/sw_vers"
  sv() { env SW_VERS="$SV/sw_vers" SAFARI_PLIST="$HERE/testdata/safari-versions/Info.plist" ImageOS=macos15 ImageVersion=20261104.0514.1 sh "$HERE/../browser/safari-versions.sh" "$@"; }
  run sv 27.2
  expect "safari-versions: the versions of macOS, the image, Safari and the session (I7)" 0 "| What | Version |
| --- | --- |
| macOS | 15.8.2 |
| macOS build | 24H232 |
| ImageOS | macos15 |
| ImageVersion | 20261104.0514.1 |
| Safari CFBundleShortVersionString | 27.2 |
| Safari CFBundleVersion | 20625.2.8.18.4 |
| WebDriver browserVersion | 27.2 |"
  # the session was not made: the other rows are there (I7)
  run sv ""
  if [ "$CODE" = 0 ] && [ "$(wc -l <"$WORK/out" | tr -d ' ')" = 8 ] && ! grep -q browserVersion "$WORK/out"; then ok; else ng "safari-versions: without browserVersion, the other rows"; fi
  run env SW_VERS=/nonexistent SAFARI_PLIST=/nonexistent ImageOS= ImageVersion= sh "$HERE/../browser/safari-versions.sh"
  if [ "$CODE" = 0 ] && [ "$(grep -c ' - |$' "$WORK/out")" = 6 ]; then ok; else ng "safari-versions: what cannot be read is -, and the table is written"; fi
else
  skip 3 "safari-versions: plutil is of macOS"
fi

# ----------------------------------------------------------------
printf '%s tests, %s failures, %s skipped\n' "$COUNT" "$FAILURES" "$SKIPPED"
[ "$FAILURES" -eq 0 ]
