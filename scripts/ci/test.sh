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

# ---------------------------------------------------------------- emet-grammar-doc.sh

emet_grammar_doc() { env GOLEM_ROOT="$1" sh "$HERE/emet-grammar-doc.sh"; }
run emet_grammar_doc "$HERE/../.."
expect "emet-grammar-doc: the repository" 0
EG=$WORK/emet-grammar
mkdir -p "$EG/modules/golem-emet/grammar" "$EG/docs/golem-emet"
printf 'Expr(nl :: Bool) :: Expr\nExpr <- Atom(nl)\nItems<p :: a> :: [a]\nItems<p> <- p*\nAtom <- [0-9]\n' >"$EG/modules/golem-emet/grammar/Emet.hpeg"
printf '```text\nExpr(nl) ::= Atom(nl)\nItems<p> ::= p*\nAtom ::= [0-9]\n```\n' >"$EG/docs/golem-emet/grammar.md"
run emet_grammar_doc "$EG"
expect "emet-grammar-doc: the same rules" 0
printf '```text\nExpr(nl) ::= Atom(nl)\nAtom ::= [0-9]\n```\n' >"$EG/docs/golem-emet/grammar.md"
run emet_grammar_doc "$EG"
expect "emet-grammar-doc: a rule that the document does not define" 1
if grep -qx '  Items' "$WORK/err"; then ok; else ng "emet-grammar-doc: the undefined rule is named"; fi
printf '```text\nExpr(nl) ::= Atom(nl)\nItems<p> ::= p*\nAtom ::= [0-9]\nOld ::= Atom\n```\n' >"$EG/docs/golem-emet/grammar.md"
run emet_grammar_doc "$EG"
expect "emet-grammar-doc: a rule that the grammar does not have" 1
if grep -qx '  Old' "$WORK/err"; then ok; else ng "emet-grammar-doc: the unknown rule is named"; fi
printf '```text\nExpr(nl) ::= Atom(nl)\nItems<p> ::= p*\nAtom ::= [0-9]\nAtom ::= [a-z]\n```\n' >"$EG/docs/golem-emet/grammar.md"
run emet_grammar_doc "$EG"
expect "emet-grammar-doc: a rule defined twice" 1
if grep -qx '  Atom' "$WORK/err"; then ok; else ng "emet-grammar-doc: the rule defined twice is named"; fi
rm "$EG/docs/golem-emet/grammar.md"
run emet_grammar_doc "$EG"
expect "emet-grammar-doc: no document" 1

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

# ---------------------------------------------------------------- werror.sh
# (docs/adr/0245 section 2, W3): the .cabal files of testdata/werror, one
# at a time, as modules/a/a.cabal of a small tree

werror() { sh "$HERE/werror.sh" "$@"; }
: >"$WORK/in"
run werror "$HERE/../.."
expect "werror: the repository (W3)" 0
WE=$WORK/werror
WD=$HERE/testdata/werror
# we_case NAME CODE CABAL [LINE]: modules/a/a.cabal is testdata/werror/CABAL;
# with LINE, stderr has it
we_case() {
  rm -rf "$WE" && mkdir -p "$WE/modules/a"
  cp "$WD/$3" "$WE/modules/a/a.cabal"
  run werror "$WE"
  expect "werror: $1 (W3)" "$2"
  if [ $# -ge 4 ]; then
    if grep -qxF "$4" "$WORK/err"; then ok; else ng "werror: $1: \"$4\" on stderr (W3)"; fi
  fi
}
we_case "a package with -Werror in its common stanza" 0 ok.cabal
we_case "a component without -Werror" 1 missing.cabal "modules/a/a.cabal: executable a"
if ! grep -q 'library' "$WORK/err"; then ok; else ng "werror: only the component without -Werror is named (W3)"; fi
we_case "-Werror, then -Wwarn" 1 wwarn.cabal "modules/a/a.cabal: library"
we_case "-Werror in the common stanza, then -Wno-error=name-shadowing" 1 no-error.cabal "modules/a/a.cabal: library"
we_case "-Wno-error, then -Werror" 0 after-negation.cabal
# -w turns every warning off, so -Werror has nothing to fail on, before or
# after it, in the component or in a common stanza (docs/adr/0259, decision 7)
we_case "-Werror, then -w" 1 w-after.cabal "modules/a/a.cabal: library"
we_case "-w, then -Werror" 1 w-before.cabal "modules/a/a.cabal: library"
we_case "-w in the common stanza, -Werror in the component" 1 w-common.cabal "modules/a/a.cabal: library"
we_case "an option that only starts with -w" 0 w-like.cabal
# OPTIONS_GHC -Wno-name-shadowing in a Haskell file
we_case "the tree with a pragma" 0 ok.cabal
mkdir -p "$WE/modules/a/src"
cp "$WD/Pragma.hs" "$WE/modules/a/src/A.hs"
run werror "$WE"
expect "werror: OPTIONS_GHC -Wno-name-shadowing (W3)" 1
if grep -qxF "modules/a/src/A.hs:1" "$WORK/err"; then ok; else ng "werror: the file and the line of the pragma (W3)"; fi
cp "$WD/PragmaW.hs" "$WE/modules/a/src/A.hs"
run werror "$WE"
expect "werror: OPTIONS_GHC -w (docs/adr/0259, decision 7)" 1
if grep -qxF "modules/a/src/A.hs:1" "$WORK/err"; then ok; else ng "werror: the file and the line of the pragma -w (docs/adr/0259, decision 7)"; fi
# the files that peg-hs writes keep its pragmas
mkdir -p "$WE/modules/golem-parser/src/Golem/Parser"
cp "$WD/ok.cabal" "$WE/modules/golem-parser/golem-parser.cabal"
rm "$WE/modules/a/src/A.hs"
cp "$WD/Pragma.hs" "$WE/modules/golem-parser/src/Golem/Parser/Generated.hs"
run werror "$WE"
expect "werror: the pragma of a file peg-hs writes" 0
# -Wwarn in the ghc-options of cabal.project.wasm
rm -rf "$WE/modules/golem-parser"
cp "$WD/cabal.project.wasm" "$WE/cabal.project.wasm"
run werror "$WE"
expect "werror: -Wwarn in cabal.project.wasm (W3)" 1
if grep -qxF "cabal.project.wasm: package a" "$WORK/err"; then ok; else ng "werror: the section of cabal.project.wasm (W3)"; fi
cp "$WD/cabal.project.wasm" "$WE/cabal.project.local"
rm "$WE/cabal.project.wasm"
run werror "$WE"
expect "werror: -Wwarn in cabal.project.local (W3)" 1
cp "$WD/cabal.project.w" "$WE/cabal.project.local"
run werror "$WE"
expect "werror: -w in cabal.project.local (docs/adr/0259, decision 7)" 1
if grep -qxF "cabal.project.local: package a" "$WORK/err"; then ok; else ng "werror: the section of cabal.project.local with -w (docs/adr/0259, decision 7)"; fi

# ---------------------------------------------------------------- log-warnings.sh
# (docs/adr/0245 section 5, W4, W5, W6): lines of the logs of 40eb98ce with
# their times, in testdata/log-warnings: one.txt the warning of
# download-artifact; two.txt it, a G03010 of golem, the name of a test with
# "warnings", the warning of the ld of macOS, the hint of git and a warning
# of GHC

lw() { sh "$HERE/log-warnings.sh" "$@"; }
LW=$HERE/testdata/log-warnings
LT=$WORK/log-warnings
mkdir -p "$LT"
: >"$LT/empty.log"
: >"$LT/empty.tsv"
run lw "$LW/allow-dep.tsv" "$LT/empty.log"
expect "log-warnings: an empty log (W4)" 0 ""
run lw "$LT/empty.tsv" "$LW/one.txt"
expect "log-warnings: one warning, nothing allowed (W4)" 1
if [ "$(cat "$WORK/out")" = "$LW/one.txt:1: $(cut -d' ' -f2- "$LW/one.txt")" ]; then ok; else ng "log-warnings: the warning as LOG:LINE: TEXT, without the time (W4)"; fi
run lw "$LW/allow-dep.tsv" "$LW/one.txt"
expect "log-warnings: one warning that the list allows (W4)" 0 ""
run lw "$LW/allow-dep.tsv" "$LW/two.txt"
expect "log-warnings: warnings, the list allowing one (W4)" 1
cp "$WORK/out" "$LT/two.out"
if [ "$(cut -d: -f2 "$LT/two.out" | tr '\n' ' ')" = "4 6 " ]; then ok; else ng "log-warnings: the ld and the GHC warnings, not the one allowed, nor the hint (W4)"; fi
if ! grep -qF 'G03010' "$LT/two.out" && ! grep -qF 'G05004' "$LT/two.out"; then ok; else ng "log-warnings: a diagnostic of golem and the name of a test are not warnings (W6)"; fi
run lw "$LT/empty.tsv" "$LW/two.txt"
expect "log-warnings: an empty list allows nothing (W4)" 1
if [ "$(wc -l <"$WORK/out" | tr -d ' ')" = 3 ]; then ok; else ng "log-warnings: every warning of an empty list (W4)"; fi
# W5: the lines of the log and of the list in the other order
awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }' "$LW/two.txt" >"$LT/reversed.log"
{ cat "$LW/allow-dep.tsv"; printf '^hint: \tthe hint\thttps://github.com/actions/checkout/issues/427\n'; } >"$LT/allow.tsv"
awk '{ a[NR] = $0 } END { for (i = NR; i >= 1; i--) print a[i] }' "$LT/allow.tsv" >"$LT/allow-reversed.tsv"
run lw "$LT/allow.tsv" "$LW/two.txt"
c1=$CODE
sed 's/^[^:]*:[0-9]*: //' "$WORK/out" | LC_ALL=C sort >"$LT/a.txt"
run lw "$LT/allow-reversed.tsv" "$LT/reversed.log"
sed 's/^[^:]*:[0-9]*: //' "$WORK/out" | LC_ALL=C sort >"$LT/b.txt"
if [ "$c1" = 1 ] && [ "$CODE" = 1 ] && cmp -s "$LT/a.txt" "$LT/b.txt"; then ok; else ng "log-warnings: the same warnings and code in any order of the lines (W5)"; fi
run lw "$LW/two-fields.tsv" "$LW/one.txt"
expect "log-warnings: a line of the list of two fields" 2
run lw "$LW/bad-regex.tsv" "$LW/one.txt"
expect "log-warnings: a regular expression grep -E does not take" 2
run lw "$LW/allow-dep.tsv"
expect "log-warnings: no log is a usage error" 2
run lw "$HERE/warnings-allowed.tsv" "$LW/two.txt"
expect "log-warnings: the list of the repository allows the ld of macOS but not GHC (W4)" 1
if [ "$(cut -d: -f2 "$WORK/out")" = 6 ]; then ok; else ng "log-warnings: the list of the repository leaves the warning of GHC alone (W4)"; fi

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
# the value of the last -with-rtsopts starts with -N; other options of
# the RTS may follow it (docs/adr/0249)
rts_case "-with-rtsopts that starts with -N, followed by -A64m" 0 'executable b
  ghc-options: -threaded "-with-rtsopts=-N -A64m"
'
rts_case "-with-rtsopts with -N after another option" 1 'executable b
  ghc-options: -threaded "-with-rtsopts=-A64m -N"
' "executable b"
rts_case "-with-rtsopts without -N" 1 'executable b
  ghc-options: -threaded -with-rtsopts="-A64m -qg"
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
  # without the table of limits, as by hand (docs/adr ADR 0292)
  suite_timeout() { SUITE_TIMEOUT=1 SUITE_LIMITS= sh "$HERE/suite-timeout.sh" "$@"; }
  : >"$WORK/in"
  run suite_timeout true
  expect "suite-timeout: a suite that passes" 0
  # the seconds of each suite that finished, one line on stderr, to choose
  # the suites of each runner of the tests (docs/adr/0244)
  if [ "$(wc -l <"$WORK/err" | tr -d ' ')" = 1 ] && grep -Eqx 'true: finished in [0-9]+ seconds' "$WORK/err"; then ok; else ng "suite-timeout: the seconds of a suite that passed are one line"; fi
  run suite_timeout sh -c 'exit 3'
  expect "suite-timeout: a suite that fails keeps its exit code" 3
  if [ "$(wc -l <"$WORK/err" | tr -d ' ')" = 1 ] && grep -Eqx 'sh: finished in [0-9]+ seconds' "$WORK/err"; then ok; else ng "suite-timeout: the seconds of a suite that failed are one line"; fi
  run suite_timeout sleep 30
  expect "suite-timeout: a suite that does not finish is stopped" 124
  if grep -qx 'sleep: did not finish in 1 seconds' "$WORK/err" && ! grep -q 'finished in' "$WORK/err"; then ok; else ng "suite-timeout: the suite that did not finish is named, without seconds"; fi

  # the limits of scripts/ci/testdata/suite-limits/limits.tsv (docs/adr ADR
  # 0292): golem-x-test is a suite that exits with $ST_CODE and says it ran;
  # date gives the times of a list, one per call, so that nothing sleeps
  ST=$WORK/suite-limits-wrapper
  mkdir -p "$ST/bin"
  printf '#!/bin/sh\necho ran >>"%s/ran"\nexit "${ST_CODE:-0}"\n' "$ST" >"$ST/golem-x-test"
  cp "$ST/golem-x-test" "$ST/golem-y-test"
  chmod +x "$ST/golem-x-test" "$ST/golem-y-test"
  printf '#!/bin/sh\nhead -n 1 "%s/times"\ntail -n +2 "%s/times" >"%s/times.next"\nmv "%s/times.next" "%s/times"\n' "$ST" "$ST" "$ST" "$ST" "$ST" >"$ST/bin/date"
  chmod +x "$ST/bin/date"
  # st_run CODE START END PROGRAM...: the suite exits with CODE, and runs from START to END
  st_run() {
    printf '%s\n%s\n' "$2" "$3" >"$ST/times"
    rm -f "$ST/ran"
    code=$1
    shift 3
    run env PATH="$ST/bin:$PATH" ST_CODE="$code" SUITE_LIMITS="$HERE/testdata/suite-limits/limits.tsv" sh "$HERE/suite-timeout.sh" "$@"
  }
  st_run 0 100 110 "$ST/golem-x-test"
  expect "suite-timeout: L1 a suite of exactly its limit keeps its exit code" 0
  if [ "$(cat "$WORK/err")" = "golem-x-test: finished in 10 seconds" ]; then ok; else ng "suite-timeout: L1 a suite within its limit says its seconds alone"; fi
  st_run 3 100 110 "$ST/golem-x-test"
  expect "suite-timeout: L1 a failing suite within its limit keeps its exit code" 3
  st_run 0 100 111 "$ST/golem-x-test"
  expect "suite-timeout: L2 a passing suite one second over its limit fails" 1
  if [ "$(cat "$WORK/err")" = "golem-x-test: finished in 11 seconds, over its limit of 10 seconds (scripts/ci/suite-limits.tsv)" ]; then ok; else ng "suite-timeout: L2 the line of the limit"; fi
  st_run 1 100 111 "$ST/golem-x-test"
  if [ "$CODE" = 1 ] && grep -qxF "golem-x-test: finished in 11 seconds, over its limit of 10 seconds (scripts/ci/suite-limits.tsv)" "$WORK/err"; then ok; else ng "suite-timeout: L2 a failing suite over its limit keeps its exit code 1, with the line of the limit"; fi
  st_run 3 100 111 "$ST/golem-x-test"
  if [ "$CODE" = 3 ] && grep -qF "over its limit of 10 seconds" "$WORK/err"; then ok; else ng "suite-timeout: L2 a failing suite over its limit keeps its exit code 3"; fi
  st_run 0 100 101 "$ST/golem-y-test"
  if [ "$CODE" = 1 ] && [ ! -e "$ST/ran" ] && [ "$(cat "$WORK/err")" = "golem-y-test: no limit in scripts/ci/suite-limits.tsv" ]; then ok; else ng "suite-timeout: L3 a suite without a row does not run, and fails"; fi
  printf '100\n200\n' >"$ST/times"
  rm -f "$ST/ran"
  run env PATH="$ST/bin:$PATH" SUITE_LIMITS= sh "$HERE/suite-timeout.sh" "$ST/golem-y-test"
  if [ "$CODE" = 0 ] && [ -e "$ST/ran" ] && [ "$(cat "$WORK/err")" = "golem-y-test: finished in 100 seconds" ]; then ok; else ng "suite-timeout: an empty SUITE_LIMITS puts no limit"; fi
  run env SUITE_TIMEOUT=1 SUITE_LIMITS="$HERE/testdata/suite-limits/limits.tsv" sh "$HERE/suite-timeout.sh" sleep 30
  if [ "$CODE" = 124 ] && grep -qx 'sleep: did not finish in 1 seconds' "$WORK/err" && ! grep -q 'over its limit' "$WORK/err"; then ok; else ng "suite-timeout: L6 SUITE_TIMEOUT stops a suite whatever its limit"; fi
else
  skip 19 "suite-timeout (no timeout command)"
fi

# ---------------------------------------------------------------- suite-limits.sh
# (docs/adr ADR 0292)

suite_limits() { sh "$HERE/suite-limits.sh" "$@"; }
SL=$WORK/suite-limits
mkdir -p "$SL"
# sl_lines ARCH SECONDS...: lines of suite-timeout.sh of golem-a-test, with the architecture before them
sl_lines() {
  a=$1
  shift
  for s in "$@"; do printf '%s\t2026-11-10T00:00:00.0000000Z golem-a-test: finished in %s seconds\n' "$a" "$s"; done
}
# L5 the limit is max(10, ceil(2 m)): m = 0, 4.9, 5 and 5.1 give 10, 10, 10 and 11
for case in "0 10" "4.9 10" "5 10" "5.1 11" "7 14"; do
  set -- $case
  sl_lines x86_64 "$1" >"$WORK/in"
  run suite_limits
  if [ "$CODE" = 0 ] && grep -qxF "x86_64	golem-a-test	$2" "$WORK/out"; then ok; else ng "suite-limits: L5 a median of $1 seconds gives a limit of $2"; fi
done
# L5 two seconds: their mean; three: the middle; the order of the lines does not matter
sl_lines aarch64 6 9 >"$WORK/in"
run suite_limits
if [ "$CODE" = 0 ] && grep -qxF "aarch64	golem-a-test	15" "$WORK/out"; then ok; else ng "suite-limits: L5 the median of two is their mean (7.5, a limit of 15)"; fi
sl_lines x86_64 40 6 9 >"$WORK/in"
run suite_limits
if [ "$CODE" = 0 ] && grep -qxF "x86_64	golem-a-test	18" "$WORK/out"; then ok; else ng "suite-limits: L5 the median of three is the one in the middle"; fi
# each architecture and suite apart; the line of a suite over its limit counts; other lines do not
{
  sl_lines x86_64 30 30 30
  sl_lines aarch64 8
  printf 'x86_64\tgolem-b-test: finished in 12 seconds, over its limit of 10 seconds (scripts/ci/suite-limits.tsv)\n'
  printf 'x86_64\tgolem-c-test: did not finish in 600 seconds\n'
  printf 'x86_64\tsomething else\n'
} >"$WORK/in"
run suite_limits
if [ "$CODE" = 0 ] && [ "$(grep -v '^#' "$WORK/out")" = "aarch64	golem-a-test	16
x86_64	golem-a-test	60
x86_64	golem-b-test	24" ]; then ok; else ng "suite-limits: L5 one row for each architecture and suite, in order"; fi
: >"$WORK/in"
run suite_limits
expect "suite-limits: no line, no table" 1

# L4 every suite of test-suites.sh, on x86_64 and aarch64, has exactly one row
mkdir -p "$SL/modules/golem-p" "$SL/modules/golem-driver"
printf 'cabal-version: 3.0\nname: golem-p\n\ntest-suite golem-p-test\n  type: exitcode-stdio-1.0\n' >"$SL/modules/golem-p/golem-p.cabal"
printf 'cabal-version: 3.0\nname: golem-driver\n\ntest-suite golem-driver-test\n  type: exitcode-stdio-1.0\n' >"$SL/modules/golem-driver/golem-driver.cabal"
printf '# a comment\nx86_64\tgolem-p-test\t10\naarch64\tgolem-p-test\t10\nx86_64\tgolem-driver-test\t20\naarch64\tgolem-driver-test\t20\n' >"$SL/good.tsv"
: >"$WORK/in"
run suite_limits --check "$SL/good.tsv" "$SL/modules"
expect "suite-limits: L4 a table with one row for each suite and architecture" 0
grep -v 'aarch64	golem-p-test' "$SL/good.tsv" >"$SL/missing.tsv"
run suite_limits --check "$SL/missing.tsv" "$SL/modules"
if [ "$CODE" = 1 ] && grep -qF 'golem-p-test' "$WORK/err"; then ok; else ng "suite-limits: L4 a suite without its row on one architecture fails"; fi
{ cat "$SL/good.tsv"; printf 'x86_64\tgolem-p-test\t30\n'; } >"$SL/twice.tsv"
run suite_limits --check "$SL/twice.tsv" "$SL/modules"
if [ "$CODE" = 1 ] && grep -qF 'golem-p-test' "$WORK/err"; then ok; else ng "suite-limits: L4 two rows of the same suite and architecture fail"; fi
{ cat "$SL/good.tsv"; printf 'x86_64\tgolem-gone-test\t30\n'; } >"$SL/extra.tsv"
run suite_limits --check "$SL/extra.tsv" "$SL/modules"
if [ "$CODE" = 1 ] && grep -qF 'golem-gone-test' "$WORK/err"; then ok; else ng "suite-limits: L4 a row without its suite fails"; fi
run suite_limits --check
expect "suite-limits: L4 the table of the repository has every suite of test-suites.sh, once on each architecture" 0

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

# ---------------------------------------------------------------- fetch-url.sh
# (docs/adr/0243): a fake curl on PATH records its arguments, fails
# FAKE_FAILS times with the exit code FAKE_CODE, then writes FAKE_FILE to
# the file of -o; a fake sleep records its seconds and does not sleep

FU=$WORK/fetch-url
mkdir -p "$FU/bin"
cat >"$FU/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$FU_LOG"
n=$(($(cat "$FU_COUNT" 2>/dev/null || echo 0) + 1))
echo "$n" >"$FU_COUNT"
out=
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; esac
  shift
done
# a failed transfer may leave a partial file
if [ "$n" -le "${FAKE_FAILS:-0}" ]; then printf 'partial' >"$out"; exit "${FAKE_CODE:-22}"; fi
cp "$FAKE_FILE" "$out"
FAKE
cat >"$FU/bin/sleep" <<'FAKE'
#!/bin/sh
printf '%s\n' "$1" >>"$FU_SLEEPS"
FAKE
chmod +x "$FU/bin/curl" "$FU/bin/sleep"
printf 'the archive\n' >"$FU/good"
: >"$FU/empty"
fu_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
FU_SHA=$(fu_sha "$FU/good")
FU_EMPTY_SHA=$(fu_sha "$FU/empty")
export FU_LOG="$FU/curl.log" FU_COUNT="$FU/count" FU_SLEEPS="$FU/sleeps"
# fetch_url ENV... -- ARG...: runs fetch-url.sh with the fakes, after
# clearing the records of the fakes and the downloads
fu_reset() { rm -rf "$FU/d"; : >"$FU_LOG"; : >"$FU_SLEEPS"; rm -f "$FU_COUNT"; }
fetch_url() { env PATH="$FU/bin:$PATH" FAKE_FILE="${FAKE_FILE:-$FU/good}" "$@"; }
fu_calls() { wc -l <"$FU_LOG" | tr -d ' '; }
fu_sleeps() { tr '\n' ' ' <"$FU_SLEEPS" | sed 's/ $//'; }
fu_none() { [ ! -e "$FU/d/a.tar.gz" ] && [ ! -e "$FU/d/a.tar.gz.part" ]; }
URL1=https://example.org/1/a.tar.gz
URL2=https://example.org/2/a.tar.gz
: >"$WORK/in"

run sh "$HERE/fetch-url.sh"
expect "fetch-url: no argument is a usage error" 2
run sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA"
expect "fetch-url: no URL is a usage error" 2
if grep -qF 'usage: fetch-url.sh FILE SHA256 URL [URL...]' "$WORK/err"; then ok; else ng "fetch-url: the usage is written"; fi

# I1, I2: a FILE of the SHA-256 is used, and curl is not called
fu_reset
mkdir -p "$FU/d"
cp "$FU/good" "$FU/d/a.tar.gz"
run fetch_url sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 0 ] && [ "$(fu_sha "$FU/d/a.tar.gz")" = "$FU_SHA" ]; then ok; else ng "fetch-url: a FILE of the SHA-256 is not fetched (I1, I2)"; fi
# a FILE of another SHA-256 is fetched again
fu_reset
mkdir -p "$FU/d"
printf 'old\n' >"$FU/d/a.tar.gz"
run fetch_url sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 1 ] && [ "$(fu_sha "$FU/d/a.tar.gz")" = "$FU_SHA" ]; then ok; else ng "fetch-url: a FILE of another SHA-256 is fetched again (I1)"; fi
# a FILE.part alone is fetched again and overwritten
fu_reset
mkdir -p "$FU/d"
printf 'half' >"$FU/d/a.tar.gz.part"
run fetch_url sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_sha "$FU/d/a.tar.gz")" = "$FU_SHA" ] && [ ! -e "$FU/d/a.tar.gz.part" ]; then ok; else ng "fetch-url: a FILE.part left is fetched again"; fi
# the directory of FILE is made
fu_reset
run fetch_url sh "$HERE/fetch-url.sh" "$FU/d/x/y/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_sha "$FU/d/x/y/a.tar.gz")" = "$FU_SHA" ]; then ok; else ng "fetch-url: the directory of FILE is made"; fi
# the arguments of curl
if grep -qF -- "--proto =https --tlsv1.2 -fsSL --connect-timeout 30 --max-time 120 -o $FU/d/x/y/a.tar.gz.part $URL1" "$FU_LOG"; then ok; else ng "fetch-url: curl has --proto =https, --tlsv1.2, --connect-timeout 30 and --max-time 120"; fi
run fetch_url FETCH_MAX_TIME=7 sh "$HERE/fetch-url.sh" "$FU/d/z/a.tar.gz" "$FU_SHA" "$URL1"
if grep -qF -- "--max-time 7 " "$FU_LOG"; then ok; else ng "fetch-url: FETCH_MAX_TIME sets --max-time"; fi

# I3: the attempts and the waits
fu_reset
run fetch_url FETCH_ATTEMPTS=3 FETCH_WAITS="1 2" FAKE_FAILS=2 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 3 ] && [ "$(fu_sleeps)" = "1 2" ] && [ "$(fu_sha "$FU/d/a.tar.gz")" = "$FU_SHA" ]; then ok; else ng "fetch-url: two failures and a success in three attempts, after waits of 1 and 2 (I1, I3)"; fi
if [ "$(grep -c "^fetch-url: $URL1: curl exited with 22" "$WORK/err")" = 2 ] && grep -qF 'next in 2 seconds' "$WORK/err"; then ok; else ng "fetch-url: each failed attempt says the URL, the exit code of curl and the next wait (I3)"; fi
fu_reset
run fetch_url FETCH_ATTEMPTS=3 FETCH_WAITS="1 2" FAKE_FAILS=3 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 3 ] && [ "$(fu_sleeps)" = "1 2" ] && fu_none; then ok; else ng "fetch-url: three failures in three attempts fail, and leave no FILE nor FILE.part (I3)"; fi
fu_reset
mkdir -p "$FU/d"
printf 'old\n' >"$FU/d/a.tar.gz"
run fetch_url FETCH_WAITS=0 FAKE_FAILS=3 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 3 ] && fu_none; then ok; else ng "fetch-url: a FILE of another SHA-256 is gone when every attempt fails (I3)"; fi
fu_reset
run fetch_url FETCH_WAITS=5 FAKE_FAILS=2 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 3 ] && [ "$(fu_sleeps)" = "5 5" ]; then ok; else ng "fetch-url: three attempts by default, and the last wait is used again (I3)"; fi
fu_reset
run fetch_url FETCH_WAITS="1 2 3" FAKE_FAILS=2 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_sleeps)" = "1 2" ]; then ok; else ng "fetch-url: the waits in their order, as many as needed (I3)"; fi
fu_reset
run fetch_url FETCH_WAITS="" FAKE_FAILS=1 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_sleeps)" = 0 ]; then ok; else ng "fetch-url: no wait is a wait of 0 seconds (I3)"; fi
fu_reset
run fetch_url FAKE_FAILS=2 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_sleeps)" = "10 30" ]; then ok; else ng "fetch-url: the waits are 10 and 30 seconds by default (I3)"; fi
fu_reset
run fetch_url FETCH_ATTEMPTS=1 FAKE_FAILS=1 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 1 ] && [ ! -s "$FU_SLEEPS" ] && fu_none; then ok; else ng "fetch-url: one attempt that fails does not wait (I3)"; fi
fu_reset
run fetch_url FETCH_ATTEMPTS=2 FETCH_WAITS=1 FAKE_FAILS=1 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 2 ] && [ "$(fu_sleeps)" = 1 ]; then ok; else ng "fetch-url: one failure in two attempts (I3)"; fi
for c in 22 56 28 6; do
  fu_reset
  run fetch_url FETCH_WAITS=0 FAKE_FAILS=1 FAKE_CODE=$c sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
  if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 2 ] && grep -qF "curl exited with $c " "$WORK/err"; then ok; else ng "fetch-url: the exit code $c of curl is retried (I3)"; fi
done
for v in 0 x; do
  run fetch_url FETCH_ATTEMPTS=$v sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
  expect "fetch-url: FETCH_ATTEMPTS=$v is a usage error" 2
done
run fetch_url FETCH_WAITS="1 x" sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
expect "fetch-url: a wait that is not an integer is a usage error" 2

# I4: a file of another SHA-256 is not retried
fu_reset
run fetch_url FAKE_FILE="$FU/empty" sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1" "$URL2"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 1 ] && [ ! -s "$FU_SLEEPS" ] && fu_none; then ok; else ng "fetch-url: an empty file of another SHA-256 fails at once, and leaves no FILE nor FILE.part (I4)"; fi
if grep -qF "$FU_EMPTY_SHA" "$WORK/err" && grep -qF "expected $FU_SHA" "$WORK/err"; then ok; else ng "fetch-url: the actual and the expected SHA-256 are written (I4)"; fi
printf 'replaced\n' >"$FU/replaced"
fu_reset
run fetch_url FAKE_FILE="$FU/replaced" sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 1 ] && fu_none && grep -qF "$(fu_sha "$FU/replaced")" "$WORK/err"; then ok; else ng "fetch-url: a replaced file fails at once (I4)"; fi
fu_reset
mkdir -p "$FU/d"
printf 'old\n' >"$FU/d/a.tar.gz"
run fetch_url FAKE_FILE="$FU/replaced" sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 1 ] && fu_none; then ok; else ng "fetch-url: a FILE of another SHA-256 is gone when the fetched file does not match (I4)"; fi

# I5: the URLs in their order, until one answers
fu_reset
run fetch_url FAKE_FAILS=1 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1" "$URL2"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 2 ] && sed -n 1p "$FU_LOG" | grep -qF "$URL1" && sed -n 2p "$FU_LOG" | grep -qF "$URL2" && [ ! -s "$FU_SLEEPS" ]; then ok; else ng "fetch-url: the second URL is tried in the same attempt when the first fails (I5)"; fi
fu_reset
run fetch_url sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1" "$URL2"
if [ "$CODE" = 0 ] && [ "$(fu_calls)" = 1 ] && ! grep -qF "$URL2" "$FU_LOG"; then ok; else ng "fetch-url: the URLs after the one that answered are not tried (I5)"; fi
fu_reset
run fetch_url FETCH_ATTEMPTS=3 FETCH_WAITS=0 FAKE_FAILS=6 sh "$HERE/fetch-url.sh" "$FU/d/a.tar.gz" "$FU_SHA" "$URL1" "$URL2"
if [ "$CODE" = 1 ] && [ "$(fu_calls)" = 6 ] && [ "$(fu_sleeps)" = "0 0" ] && fu_none; then ok; else ng "fetch-url: both URLs fail in each of the attempts (I3, I5)"; fi
unset FU_LOG FU_COUNT FU_SLEEPS

# ---------------------------------------------------------------- fetch-hlint.sh, fetch-nvim.sh, helix/test.sh
# (docs/adr/0009, docs/adr/0231, docs/adr/0243): the archive is fetched by
# scripts/ci/fetch-url.sh into third_party/downloads, and one there of the
# SHA-256 is unpacked without curl. A copy of each script in a fake root
# pins the SHA-256 of a small archive of the layout of the release; a fake
# uname answers x86-64 Linux, and a fake curl writes the archive. The fake
# hx of the archive of Helix answers --version, --grammar build (it writes
# the two .so) and --health, so that helix/test.sh runs to its end
FN=$WORK/fetch-nh
HV=$(sed -n 's/^VERSION=//p' "$HERE/../../tools/editors/helix/test.sh")
HX=helix-$HV-x86_64-linux
mkdir -p "$FN/bin" "$FN/src/hlint-3.10/data" "$FN/src/nvim-linux-x86_64/bin" "$FN/src/$HX/runtime"
printf '#!/bin/sh\necho "HLint v3.10"\n' >"$FN/src/hlint-3.10/hlint"
: >"$FN/src/hlint-3.10/data/hlint.yaml"
printf '#!/bin/sh\necho "NVIM v%s"\n' "$(sed -n 's/^VERSION=//p' "$HERE/../../tools/editors/fetch-nvim.sh")" >"$FN/src/nvim-linux-x86_64/bin/nvim"
cat >"$FN/src/$HX/hx" <<FAKE
#!/bin/sh
case "\$1" in
  --version) echo "helix $HV (fake)" ;;
  --grammar) mkdir -p "\$HOME/.config/helix/runtime/grammars" && : >"\$HOME/.config/helix/runtime/grammars/golem.so" && : >"\$HOME/.config/helix/runtime/grammars/emet.so" ;;
  --health) printf 'Tree-sitter parser: \342\234\223\nHighlight queries: \342\234\223\n' ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$FN/src/hlint-3.10/hlint" "$FN/src/nvim-linux-x86_64/bin/nvim" "$FN/src/$HX/hx"
(cd "$FN/src" && tar -czf "$FN/hlint-3.10-x86_64-linux.tar.gz" hlint-3.10 && tar -czf "$FN/nvim-linux-x86_64.tar.gz" nvim-linux-x86_64 && tar -cJf "$FN/$HX.tar.xz" "$HX")
printf '#!/bin/sh\ncase "$1" in -s) echo Linux ;; -m) echo x86_64 ;; *) exit 1 ;; esac\n' >"$FN/bin/uname"
cat >"$FN/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$FN_LOG"
url=
for a in "$@"; do url=$a; done
while [ $# -gt 0 ]; do
  case "$1" in -o) cp "$FN_ARCHIVES/${url##*/}" "$2" || exit 22; shift ;; esac
  shift
done
FAKE
chmod +x "$FN/bin/uname" "$FN/bin/curl"
mkdir -p "$FN/root/scripts/ci" "$FN/root/tools/editors/helix" "$FN/root/tools/editors/tree-sitter-golem/queries" "$FN/root/tools/editors/tree-sitter-emet/queries"
cp "$HERE/fetch-url.sh" "$FN/root/scripts/ci/"
# the README and the queries its sh block of Helix copies
cp "$HERE/../../tools/editors/README.md" "$FN/root/tools/editors/"
: >"$FN/root/tools/editors/tree-sitter-golem/queries/highlights.scm"
: >"$FN/root/tools/editors/tree-sitter-emet/queries/highlights.scm"
sed "s/^SHA=.*/SHA=$(fu_sha "$FN/hlint-3.10-x86_64-linux.tar.gz")/" "$HERE/fetch-hlint.sh" >"$FN/root/scripts/ci/fetch-hlint.sh"
sed "s/\(Linux-x86_64) NAME=nvim-linux-x86_64; SHA=\)[0-9a-f]*/\1$(fu_sha "$FN/nvim-linux-x86_64.tar.gz")/" "$HERE/../../tools/editors/fetch-nvim.sh" >"$FN/root/tools/editors/fetch-nvim.sh"
sed "s/\(Linux-x86_64) NAME=helix-\$VERSION-x86_64-linux; SHA=\)[0-9a-f]*/\1$(fu_sha "$FN/$HX.tar.xz")/" "$HERE/../../tools/editors/helix/test.sh" >"$FN/root/tools/editors/helix/test.sh"
if ! cmp -s "$HERE/fetch-hlint.sh" "$FN/root/scripts/ci/fetch-hlint.sh" && ! cmp -s "$HERE/../../tools/editors/fetch-nvim.sh" "$FN/root/tools/editors/fetch-nvim.sh" && ! cmp -s "$HERE/../../tools/editors/helix/test.sh" "$FN/root/tools/editors/helix/test.sh"; then ok; else ng "fetch-hlint, fetch-nvim, helix/test.sh: the copies pin the fixtures"; fi
fn_run() { env PATH="$FN/bin:$PATH" HOME="$FN/home" FN_LOG="$FN/curl.log" FN_ARCHIVES="$FN" sh "$FN/root/$1"; }
for sa in "scripts/ci/fetch-hlint.sh hlint-3.10-x86_64-linux.tar.gz home/.local/lib/hlint-3.10" \
  "tools/editors/fetch-nvim.sh nvim-linux-x86_64.tar.gz root/third_party/nvim" \
  "tools/editors/helix/test.sh $HX.tar.xz root/third_party/helix"; do
  set -- $sa
  f=$1 a=$2 tree=$FN/$3 n=${1##*/}
  : >"$FN/curl.log"
  run fn_run "$f"
  if [ "$CODE" = 0 ] && [ -d "$tree" ] && cmp -s "$FN/$a" "$FN/root/third_party/downloads/$a"; then ok; else ng "$n: the archive is unpacked and kept in third_party/downloads (docs/adr/0243)"; fi
  if grep -qF -- "--proto =https --tlsv1.2 -fsSL --connect-timeout 30 --max-time 120 -o $FN/root/third_party/downloads/$a.part https://github.com/" "$FN/curl.log"; then ok; else ng "$n: scripts/ci/fetch-url.sh fetches the archive from its release (docs/adr/0243)"; fi
  rm -rf "$tree"
  : >"$FN/curl.log"
  run fn_run "$f"
  if [ "$CODE" = 0 ] && [ -d "$tree" ] && [ ! -s "$FN/curl.log" ]; then ok; else ng "$n: an archive of the SHA-256 in third_party/downloads is unpacked without curl (docs/adr/0243)"; fi
  rm -rf "$tree"
  printf 'other\n' >"$FN/root/third_party/downloads/$a"
  run fn_run "$f"
  if [ "$CODE" = 0 ] && [ -s "$FN/curl.log" ] && cmp -s "$FN/$a" "$FN/root/third_party/downloads/$a"; then ok; else ng "$n: an archive of another SHA-256 in third_party/downloads is fetched again (docs/adr/0243)"; fi
done
if [ "$("$FN/home/.local/bin/hlint" --version 2>/dev/null)" = "HLint v3.10" ]; then ok; else ng "fetch-hlint: hlint is installed in ~/.local/bin"; fi

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
# (fetch-url.sh tries once, without waits)
epubcheck_install() {
  env PATH="$EC/fakebin:$PATH" FETCH_ATTEMPTS=1 EPUBCHECK_HOME="$1" JAVA_HOME_17_X64="$EC/java" sh "$HERE/epubcheck-install.sh" "$2" "$3"
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
# a cached zip of a wrong SHA-256 is fetched again with fetch-url.sh
# (docs/adr/0243)
mkdir -p "$EC/h4/zip"
printf 'not a zip\n' >"$EC/h4/zip/epubcheck-9.9.9.zip"
: >"$CURL_LOG"
run epubcheck_install "$EC/h4" 9.9.9 "$EC_SHA"
expect "epubcheck-install: a cached zip of a wrong SHA-256 is fetched again" 0
if [ -s "$CURL_LOG" ] && cmp -s "$EC/release.zip" "$EC/h4/zip/epubcheck-9.9.9.zip" && [ -x "$EC/h4/bin/epubcheck" ]; then ok; else ng "epubcheck-install: the zip fetched again replaces the cached zip of a wrong SHA-256 (docs/adr/0243)"; fi
if grep -qF -- "--proto =https --tlsv1.2 -fsSL --connect-timeout 30 --max-time 120 -o $EC/h4/zip/epubcheck-9.9.9.zip.part" "$CURL_LOG"; then ok; else ng "epubcheck-install: the zip is fetched with fetch-url.sh (docs/adr/0243)"; fi
# a failed download fails
run env PATH="$EC/fakebin:$PATH" FETCH_ATTEMPTS=1 CURL_ZIP="$EC/no-such.zip" EPUBCHECK_HOME="$EC/h5" JAVA_HOME_17_X64="$EC/java" sh "$HERE/epubcheck-install.sh" 9.9.9 "$EC_SHA"
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

# ---------------------------------------------------------------- pdf-text.sh
# (docs/adr/0233): the text of a PDF by pdftotext, and the strings it has
# and lacks
# text_pdf FILE TEXT: a PDF of one page with TEXT in Helvetica, TEXT
# without parentheses and backslashes but \| for a backslash and a bar
text_pdf() {
  stream="BT /F1 12 Tf 10 20 Td ($2) Tj ET"
  {
    printf '%%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n'
    printf '3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 50] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>\nendobj\n'
    printf '4 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n'
    printf '5 0 obj\n<< /Length %s >>\nstream\n%s\nendstream\nendobj\n' "$(printf '%s' "$stream" | wc -c | tr -d ' ')" "$stream"
    printf 'trailer\n<< /Root 1 0 R >>\n%%%%EOF\n'
  } >"$1"
}
if command -v pdftotext >/dev/null 2>&1; then
  text_pdf "$WORK/bar.pdf" 'the guard | and a || b'
  text_pdf "$WORK/escaped.pdf" 'the guard \\| and a \\|\\| b'
  run sh "$HERE/pdf-text.sh" "$WORK/bar.pdf"
  if [ "$CODE" = 0 ] && grep -qF 'the guard | and a || b' "$WORK/out"; then ok; else ng "pdf-text.sh: without a check it writes the text"; fi
  run sh "$HERE/pdf-text.sh" "$WORK/bar.pdf" --has 'guard |' --has 'a || b' --lacks '\|'
  expect "pdf-text.sh: a bar shown as a bar passes" 0
  run sh "$HERE/pdf-text.sh" "$WORK/escaped.pdf" --has 'guard |' --has 'a || b' --lacks '\|'
  expect "pdf-text.sh: a bar shown with its backslash fails" 1
  if grep -qF 'does not have: a || b' "$WORK/err" && grep -qF 'has: \|' "$WORK/err"; then ok; else ng "pdf-text.sh: the strings missing and the strings found are named"; fi
  run sh "$HERE/pdf-text.sh" "$WORK/no-such.pdf" --has x
  expect "pdf-text.sh: a missing PDF exits with 2" 2
else
  skip 5 "pdf-text.sh: pdftotext is not installed"
fi
run sh "$HERE/pdf-text.sh"
expect "pdf-text.sh: no PDF is a usage error" 2
run sh "$HERE/pdf-text.sh" "$WORK/bar.pdf" --has
expect "pdf-text.sh: a check without its text is a usage error" 2
run sh "$HERE/pdf-text.sh" "$WORK/bar.pdf" --contains x
expect "pdf-text.sh: an unknown check is a usage error" 2

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
  awk -v s="$1" 'index($0, s) { on = 1; print; next } on && /^      - / { on = 0 } on' "$CI_YML" | grep -qF -- "$2"
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
  step_has "name: epubcheck in the background" 'sh scripts/ci/bg.sh start epubcheck timeout -k 10 600 sh scripts/ci/epubcheck-install.sh "$EPUBCHECK_VERSION" "$EPUBCHECK_SHA256"'; then ok; else
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
# the code of the developer manual written \| shows | in its PDF, by
# pdftotext (docs/adr/0233)
if step_if "name: The bars of the code of the developer manual" "$MANUAL_IF" && step_has "name: The bars of the code of the developer manual" "sh scripts/ci/pdf-text.sh \"\$pdf\"" && step_has "name: The bars of the code of the developer manual" "--lacks '\\|'"; then ok; else ng "ci.yml: the x86-64 runner of the outputs checks the bars of the developer manual with pdftotext"; fi
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
# the archive of shem is cached by the hash of fetch-shem.sh (docs/adr/0243)
if visual_step "name: Restore the archives of the downloads" | grep -qF 'uses: actions/cache/restore@' &&
  visual_step "name: Restore the archives of the downloads" | grep -qxF '          path: third_party/downloads' &&
  visual_step "name: Restore the archives of the downloads" | grep -qxF "          key: downloads-visual-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/visual/fetch-shem.sh') }}"; then ok; else
  ng "ci.yml: visual restores the archive of shem by the hash of fetch-shem.sh (docs/adr/0243)"
fi
if grep -qxF '        run: sh scripts/visual/fetch-shem.sh' "$VJ" && visual_step "name: shem (docs/adr/0093)" | grep -qxF '        timeout-minutes: 10'; then ok; else ng "ci.yml: visual runs fetch-shem.sh with a timeout of 10 minutes (docs/adr/0243)"; fi
CACHE_AT=$(grep -n 'name: Restore the archives of the downloads' "$VJ" | head -1 | cut -d: -f1)
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

# ---------------------------------------------------------------- ci.yml and verapdf
# (docs/adr/0183, docs/adr/0244)

VPJ=$WORK/verapdf.yml
job_lines verapdf >"$VPJ"
if [ -s "$VPJ" ]; then ok; else ng "ci.yml: there is a verapdf job"; fi
# I3: verapdf does not need build, and ci needs verapdf
if grep -qx '    needs: \[changes\]' "$VPJ" && grep -qxF "    if: needs.changes.outputs.build == 'true'" "$VPJ"; then ok; else ng "ci.yml: verapdf needs only changes and is skipped as build is (docs/adr/0244, I3)"; fi
if grep -Eq '^    needs: .*build' "$VPJ"; then ng "ci.yml: verapdf does not need build (docs/adr/0244, I3)"; else ok; fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?verapdf([],].*)?$'; then ok; else ng "ci.yml: ci needs verapdf (docs/adr/0244, I3)"; fi
if grep -qx '    timeout-minutes: 75' "$VPJ"; then ok; else ng "ci.yml: verapdf has a timeout of 75 minutes, as visual (docs/adr/0244)"; fi
# I1, I2: verapdf waits for conformance-pdfs of the outputs runner
if grep -qxF "        run: timeout -k 10 3600 sh scripts/visual/wait-pdfs.sh \"\$GITHUB_RUN_ID\" \"\$GITHUB_RUN_ATTEMPT\" 'build (ubuntu-24.04, outputs)' conformance-pdfs" "$VPJ"; then ok; else
  ng "ci.yml: verapdf waits for conformance-pdfs of build (ubuntu-24.04, outputs) (docs/adr/0244, I1, I2)"
fi
# I4: what verapdf takes from the network comes before the wait; the
# download of the artifact and the check after it
VP_NIX_AT=$(grep -n 'uses: cachix/install-nix-action@' "$VPJ" | head -1 | cut -d: -f1)
VP_BUILD_AT=$(grep -n 'nix build ' "$VPJ" | head -1 | cut -d: -f1)
VP_WAIT_AT=$(grep -n 'sh scripts/visual/wait-pdfs.sh' "$VPJ" | head -1 | cut -d: -f1)
VP_DOWNLOAD_AT=$(grep -n 'uses: actions/download-artifact@' "$VPJ" | head -1 | cut -d: -f1)
VP_CHECK_AT=$(grep -n 'sh scripts/ci/verapdf.sh' "$VPJ" | head -1 | cut -d: -f1)
if [ -n "$VP_NIX_AT" ] && [ -n "$VP_BUILD_AT" ] && [ -n "$VP_WAIT_AT" ] && [ -n "$VP_DOWNLOAD_AT" ] && [ -n "$VP_CHECK_AT" ] &&
  [ "$VP_NIX_AT" -lt "$VP_WAIT_AT" ] && [ "$VP_BUILD_AT" -lt "$VP_WAIT_AT" ] &&
  [ "$VP_WAIT_AT" -lt "$VP_DOWNLOAD_AT" ] && [ "$VP_DOWNLOAD_AT" -lt "$VP_CHECK_AT" ]; then ok; else
  ng "ci.yml: verapdf installs Nix and veraPDF, waits for conformance-pdfs, then downloads and checks it (docs/adr/0244, I4)"
fi
if grep -qxF '          GH_TOKEN: ${{ github.token }}' "$VPJ" && grep -qxF '          GH_REPO: ${{ github.repository }}' "$VPJ"; then ok; else ng "ci.yml: the wait of verapdf has GH_TOKEN and GH_REPO (docs/adr/0244)"; fi

# ---------------------------------------------------------------- the workflows and the downloads
# (docs/adr/0243)

WORKFLOWS=$HERE/../../.github/workflows
# cache_paths FILE...: the paths of the steps of actions/cache,
# actions/cache/restore and actions/cache/save, one per line, as
# "FILE:LINE PATH"; a path: | block gives one line per path
cache_paths() {
  awk '
    function flush() { if (cache) for (i = 1; i <= n; i++) print FILENAME ":" at[i] " " p[i]; cache = 0; n = 0; block = 0 }
    FNR == 1 { flush() }
    /^ *- / && match($0, /^ */) && RLENGTH <= 6 { flush() }
    /^  [a-z]/ { flush() }
    /uses: actions\/cache(\/restore|\/save)?@/ { cache = 1 }
    block && /^ *[a-z-]+:/ { block = 0 }
    block && NF { v = $0; sub(/^ */, "", v); n++; p[n] = v; at[n] = FNR; next }
    /^ +path: *\|$/ { block = 1; next }
    /^ +path: / { v = $0; sub(/^ +path: */, "", v); n++; p[n] = v; at[n] = FNR }
    END { flush() }
  ' "$@"
}
# I6: under third_party/, the caches hold the archives, the toolchain of
# wasm and the host tools only
if cache_paths "$WORKFLOWS"/*.yml | awk '$2 ~ /^third_party\// && $2 != "third_party/downloads" && $2 != "third_party/ghc-wasm" && $2 != "third_party/hosttools"' | grep -q .; then
  cache_paths "$WORKFLOWS"/*.yml | awk '$2 ~ /^third_party\// && $2 != "third_party/downloads" && $2 != "third_party/ghc-wasm" && $2 != "third_party/hosttools"' | sed 's/^/  /'
  ng "workflows: no cache holds an unpacked tree of third_party/ (docs/adr/0243, I6)"
else ok; fi
printf '      - uses: actions/cache@v6\n        with:\n          path: |\n            third_party/downloads\n            third_party/shem\n          key: k\n      - uses: actions/cache/save@v6\n        with:\n          path: third_party/nvim\n' >"$WORK/paths.yml"
if [ "$(cache_paths "$WORK/paths.yml" | awk '{print $2}' | tr '\n' ' ')" = "third_party/downloads third_party/shem third_party/nvim " ]; then ok; else ng "test.sh: cache_paths reads a path and the lines of a path block"; fi
# saves_of_downloads FILE...: "FILE:LINE IF" of each step of
# actions/cache/save whose path is third_party/downloads
saves_of_downloads() {
  awk '
    function flush() { if (save && dl) print FILENAME ":" at " " cond; save = 0; dl = 0; cond = "" }
    FNR == 1 { flush() }
    /^ *- / && match($0, /^ */) && RLENGTH <= 6 { flush(); at = FNR }
    /^  [a-z]/ { flush() }
    /uses: actions\/cache\/save@/ { save = 1 }
    /third_party\/downloads/ { dl = 1 }
    /^ +if: / { cond = $0 }
  ' "$@"
}
# I7: only a push to main saves the archives
SAVES=$(saves_of_downloads "$WORKFLOWS"/*.yml)
if [ -n "$SAVES" ] && ! printf '%s\n' "$SAVES" | grep -vF "github.ref == 'refs/heads/main'" | grep -q .; then ok; else
  printf '%s\n' "$SAVES" | sed 's/^/  /'
  ng "workflows: each save of third_party/downloads is on main only (docs/adr/0243, I7)"
fi
# each job that fetches restores the archives of its own key, without
# restore-keys, and saves them on main
for jk in "ci.yml build downloads-build-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/fetch-wasmtime.sh') }}" \
  "ci.yml format downloads-format-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/ci/fetch-hlint.sh') }}" \
  "ci.yml visual downloads-visual-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/visual/fetch-shem.sh') }}" \
  "ci.yml editors downloads-editors-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('tools/editors/helix/test.sh') }}" \
  "ci.yml editors-lsp downloads-editors-lsp-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('tools/editors/fetch-nvim.sh') }}" \
  "models.yml models downloads-models-\${{ runner.os }}-\${{ runner.arch }}-\${{ hashFiles('scripts/models/check.sh') }}"; do
  set -- $jk
  wf=$1 job=$2
  shift 2
  key=$*
  JL=$(awk -v j="  $job:" '$0 == j { on = 1; next } on && /^  [a-z]/ { on = 0 } on' "$WORKFLOWS/$wf")
  if printf '%s\n' "$JL" | grep -A4 'uses: actions/cache/restore@' | grep -qxF "          key: $key" &&
    printf '%s\n' "$JL" | grep -A4 'uses: actions/cache/save@' | grep -qxF '          path: third_party/downloads'; then ok; else
    ng "$wf: $job restores third_party/downloads by $key and saves it (docs/adr/0243)"
  fi
done
if grep -q 'restore-keys: downloads-' "$WORKFLOWS"/*.yml; then ng "workflows: the archives have no restore-keys (docs/adr/0243)"; else ok; fi
# the archives of build are restored before the wasmtime C API, and saved
# by the runner that saves, on a push to main
BJ=$(job_lines build)
DL_AT=$(printf '%s\n' "$BJ" | grep -n 'key: downloads-build-' | head -1 | cut -d: -f1)
WT_AT=$(printf '%s\n' "$BJ" | grep -n 'name: wasmtime C API' | head -1 | cut -d: -f1)
if [ -n "$DL_AT" ] && [ -n "$WT_AT" ] && [ "$DL_AT" -lt "$WT_AT" ]; then ok; else ng "ci.yml: build restores the archives before the wasmtime C API (docs/adr/0243)"; fi
if printf '%s\n' "$BJ" | grep -B2 -A3 'uses: actions/cache/save@' | grep -A5 -F 'third_party/downloads' >/dev/null &&
  printf '%s\n' "$BJ" | awk '/^      - /{ s = "" } { s = s $0 "\n" } /path: third_party\/downloads/ && s ~ /cache\/save/ { print s }' | grep -qF 'matrix.save'; then ok; else
  ng "ci.yml: the runner of build that saves saves the archives (docs/adr/0243)"
fi
# the steps that fetch have a timeout-minutes, and no timeout of 300
# seconds around them
for f in scripts/fetch-wasmtime.sh scripts/ci/fetch-hlint.sh scripts/visual/fetch-shem.sh tools/editors/fetch-nvim.sh tools/editors/helix/test.sh scripts/fetch-wasm-packages.sh; do
  STEP=$(awk -v s="$f" '/^      - /{ if (found) exit; s0 = "" } { s0 = s0 $0 "\n" } index($0, s) && /run: / { found = 1 } END { if (found) printf "%s", s0 }' "$CI_YML")
  if printf '%s\n' "$STEP" | grep -Eq '^        timeout-minutes: [0-9]+$' && ! printf '%s\n' "$STEP" | grep -q 'timeout -k 10 300'; then ok; else
    ng "ci.yml: the step that runs $f has a timeout-minutes, and no timeout -k 10 300 (docs/adr/0243)"
  fi
done
# so do the steps of browser.yml and release.yml; the fetch that runs in
# the background, epubcheck, is wrapped in 600 seconds, more than the worst
# time of the retries of fetch-url.sh (docs/adr/0259, decision 4)
for wf_f in "browser.yml scripts/browser/fetch-chromium.sh" "browser.yml scripts/wasm/fetch-deno.sh" "browser.yml scripts/fetch-wasmtime.sh" "release.yml scripts/fetch-wasm-packages.sh"; do
  set -- $wf_f
  STEP=$(awk -v s="$2" '/^      - /{ if (found) exit; s0 = "" } { s0 = s0 $0 "\n" } index($0, s) && /(run: |^ +timeout |^ +sh )/ { found = 1 } END { if (found) printf "%s", s0 }' "$WORKFLOWS/$1")
  if printf '%s\n' "$STEP" | grep -Eq '^        timeout-minutes: [0-9]+$' && ! printf '%s\n' "$STEP" | grep -q 'timeout -k 10 300' &&
    [ "$(printf '%s\n' "$STEP" | grep -c 'scripts/')" -eq 1 ]; then ok; else
    ng "$1: the step that runs $2 runs it alone, has a timeout-minutes, and no timeout -k 10 300 (docs/adr/0259, decision 4)"
  fi
done
if grep -n 'timeout -k 10 300' "$WORKFLOWS"/*.yml | grep -Eq 'fetch-|epubcheck-install'; then
  ng "workflows: no fetch is wrapped in timeout -k 10 300 (docs/adr/0259, decision 4)"
else ok; fi
# the nix of verapdf fetches nixpkgs with the token of the job
VB=$(job_lines verapdf | awk '/^      - /{ if (found) exit; s = "" } { s = s $0 "\n" } /nix build / { found = 1 } END { if (found) printf "%s", s }')
if printf '%s\n' "$VB" | grep -qxF '          NIX_CONFIG: access-tokens = github.com=${{ github.token }}'; then ok; else ng "ci.yml: the nix build of verapdf has NIX_CONFIG with access-tokens = github.com= (docs/adr/0243)"; fi

# the native alex and happy read their templates from data files, which
# the cabal store of the runner that built them had: the cache of the host
# tools keeps them too, and the wasm jobs point alex_datadir and
# happy_lib_datadir at them, so that a hit of the host tools builds the
# wasm store without that cabal store (docs/adr/0243, after the run
# 42537562660 that missed the toolchain)
for wf in ci.yml release.yml; do
  WJ=$(awk '$0 == "  wasm:" { on = 1; next } on && /^  [a-z]/ { on = 0 } on' "$WORKFLOWS/$wf")
  if printf '%s\n' "$WJ" | grep -qxF '      alex_datadir: ${{ github.workspace }}/third_party/hosttools/alex-data' &&
    printf '%s\n' "$WJ" | grep -qxF '      happy_lib_datadir: ${{ github.workspace }}/third_party/hosttools/happy-lib-data' &&
    printf '%s\n' "$WJ" | grep -qF 'key: hosttools-alex-3.5.4.2-happy-2.2-data-' &&
    printf '%s\n' "$WJ" | grep -qF 'AlexTemplate.hs' && printf '%s\n' "$WJ" | grep -qF 'HappyTemplate.hs'; then ok; else
    ng "$wf: the cache of the native alex and happy has their data files, and the wasm job points them there"
  fi
done

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
if [ -n "$UPD_AT" ] && build_lines | sed -n "$UPD_AT,\$p" | awk 'NR > 1 && /^      - / { done = 1 } !done { print }' >"$WORK/update-step" &&
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
if job_of "$RELEASE_YML" notes | grep -q 'jdx/mise-action@'; then ok; else ng "release.yml: the notes job installs Claude Code with mise"; fi
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
  if [ "$(grep -cF 'uses: haskell-actions/setup@' "$1")" = "$(grep -cF "$CABAL_DIR_RUN" "$1")" ]; then ok; else
    ng "$3: as many steps give CABAL_DIR as run haskell-actions/setup (docs/adr/0201)"
  fi
  setup=$(step_line "$1" "$2" 'uses: haskell-actions/setup@')
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
  if [ -n "$setup" ] && [ "$(step_cond "$1" "$2" "$CABAL_DIR_RUN")" = "$(step_cond "$1" "$2" 'uses: haskell-actions/setup@')" ] &&
    [ "$(step_cond "$1" "$2" 'cabal path -z --config-file')" = "$(step_cond "$1" "$2" 'uses: haskell-actions/setup@')" ]; then ok; else
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

# the checks of the release (docs/adr/0230): the wasm archive is checked
# right after package-wasm.sh makes it, and the attestations after the draft
# release is made, with the SHA256SUMS of the release against dist/
wasm_pack=$(step_line "$RELEASE_YML" wasm 'sh scripts/release/package-wasm.sh')
wasm_check=$(step_line "$RELEASE_YML" wasm 'sh scripts/release/check-wasm-archive.sh')
if [ -n "$wasm_pack" ] && [ -n "$wasm_check" ] && [ "$wasm_check" -gt "$wasm_pack" ]; then ok; else ng "release.yml: the wasm job runs check-wasm-archive.sh after package-wasm.sh (docs/adr/0230)"; fi
rel_create=$(step_line "$RELEASE_YML" release 'gh release create')
rel_verify=$(step_line "$RELEASE_YML" release 'gh attestation verify')
if [ -n "$rel_create" ] && [ -n "$rel_verify" ] && [ "$rel_verify" -gt "$rel_create" ]; then ok; else ng "release.yml: the release job runs gh attestation verify after gh release create (docs/adr/0230, I3)"; fi
if job_of "$RELEASE_YML" release | awk -v s="$rel_verify" 'NR >= s' | grep -q 'gh attestation verify "$f" -R tett23/golem' &&
  job_of "$RELEASE_YML" release | awk -v s="$rel_verify" 'NR >= s' | grep -q 'gh release download "$TAG" -p SHA256SUMS' &&
  job_of "$RELEASE_YML" release | awk -v s="$rel_verify" 'NR >= s' | grep -q 'sha256sum -c'; then ok; else
  ng "release.yml: the step of gh attestation verify checks dist/ against the SHA256SUMS of the release (docs/adr/0230, I3)"
fi
# the source of GMP is in SHA256SUMS: it is fetched before the sums are
# written and checked (docs/adr/0259, decision 1)
SUMS=$(job_of "$RELEASE_YML" release | awk '/^      - /{ if (found) exit; s = "" } { s = s $0 "\n" } /cat golem-\*\.tar\.gz\.sha256 > SHA256SUMS/ { found = 1 } END { if (found) printf "%s", s }')
gmp_fetch=$(printf '%s\n' "$SUMS" | grep -n 'scripts/release/fetch-gmp.sh' | head -1 | cut -d: -f1)
gmp_sum=$(printf '%s\n' "$SUMS" | grep -nxF '          sha256sum gmp-*.tar.xz >> SHA256SUMS' | head -1 | cut -d: -f1)
sums_check=$(printf '%s\n' "$SUMS" | grep -nxF '          sha256sum -c SHA256SUMS' | head -1 | cut -d: -f1)
if [ -n "$gmp_fetch" ] && [ -n "$gmp_sum" ] && [ -n "$sums_check" ] && [ "$gmp_fetch" -lt "$gmp_sum" ] && [ "$gmp_sum" -lt "$sums_check" ]; then ok; else
  ng "release.yml: the release job fetches the source of GMP, adds it to SHA256SUMS and then checks SHA256SUMS (docs/adr/0259, decision 1)"
fi

# ---------------------------------------------------------------- step-timeouts.sh
# (docs/adr/0230)

# The fake gh answers with the copies of the API in testdata/step-timeouts/:
# runs.json and jobs-<id>.json are answers of GitHub of 2026-11-08, cut to
# the fields read; runs-2.json and jobs-1.json, a second page with a run
# whose steps failed and were cancelled, are made by hand. Every call is
# written to $WORK/gh.args.
ST=$WORK/step-timeouts
STD=$HERE/testdata/step-timeouts
mkdir -p "$ST"
cat >"$ST/gh" <<GH
#!/bin/sh
printf '%s\n' "\$*" >>"$WORK/gh.args"
[ -z "\${FAKE_GH_FAIL-}" ] || exit 1
for a in "\$@"; do
  case \$a in
    page=1) cat "$STD/runs.json"; exit 0 ;;
    page=2) cat "$STD/runs-2.json"; exit 0 ;;
    page=*) echo '{"total_count":5,"workflow_runs":[]}'; exit 0 ;;
    repos/tett23/golem/actions/runs/*/jobs)
      id=\${a#repos/tett23/golem/actions/runs/}
      cat "$STD/jobs-\${id%/jobs}.json"; exit ;;
  esac
done
exit 1
GH
chmod +x "$ST/gh"
step_timeouts() { rm -f "$WORK/gh.args"; GH=$ST/gh GITHUB_REPOSITORY=tett23/golem sh "$HERE/step-timeouts.sh" "$@"; }
: >"$WORK/in"
TAB=$(printf '\t')
run step_timeouts 2026-10-23 10
expect "step-timeouts: the runs with the steps, newest first" 0 "run${TAB}created${TAB}qpdf is installed${TAB}epubcheck is installed
42476899008${TAB}2026-11-08T11:42:09Z${TAB}success=3${TAB}success=1
42475288545${TAB}2026-11-08T11:20:12Z${TAB}success=8${TAB}success=2
1${TAB}2026-11-08T11:00:00Z${TAB}cancelled=1${TAB}failure=1 success=1"
if grep -qxF -- 'api -X GET repos/tett23/golem/actions/workflows/ci.yml/runs -f per_page=100 -f page=3' "$WORK/gh.args" 2>/dev/null; then ok; else ng "step-timeouts: the runs of ci.yml page by page until a page without a run"; fi
if grep -qF -- 'repos/tett23/golem/actions/runs/42475288545/jobs -f filter=all -f per_page=100' "$WORK/gh.args" 2>/dev/null; then ok; else ng "step-timeouts: the jobs of every attempt of a run"; fi
# the runs without the steps (build skipped for documents only) are not
# counted: two runs are the two newest that have the steps
run step_timeouts 2026-10-23 2
expect "step-timeouts: two runs with the steps" 0 "run${TAB}created${TAB}qpdf is installed${TAB}epubcheck is installed
42476899008${TAB}2026-11-08T11:42:09Z${TAB}success=3${TAB}success=1
42475288545${TAB}2026-11-08T11:20:12Z${TAB}success=8${TAB}success=2"
if ! grep -qF 'actions/runs/1/jobs' "$WORK/gh.args" 2>/dev/null; then ok; else ng "step-timeouts: no run is read after the count is reached"; fi
run step_timeouts 2026-10-23T00:00:00Z 1
expect "step-timeouts: a date and time" 0 "run${TAB}created${TAB}qpdf is installed${TAB}epubcheck is installed
42476899008${TAB}2026-11-08T11:42:09Z${TAB}success=3${TAB}success=1"
# the runs created after the time only, and no page after the one that
# reaches it: the filter created of the API gives at most 1000 runs
run step_timeouts 2026-11-08T11:30:00Z 10
expect "step-timeouts: the runs after a time" 0 "run${TAB}created${TAB}qpdf is installed${TAB}epubcheck is installed
42476899008${TAB}2026-11-08T11:42:09Z${TAB}success=3${TAB}success=1"
if ! grep -q 'page=2' "$WORK/gh.args" 2>/dev/null && ! grep -q 'created' "$WORK/gh.args" 2>/dev/null; then ok; else ng "step-timeouts: no page after the one that reaches the time, and no filter created"; fi
run step_timeouts 2026-11-08T11:00:00Z 10
expect "step-timeouts: a run created at the time is not after it" 0 "run${TAB}created${TAB}qpdf is installed${TAB}epubcheck is installed
42476899008${TAB}2026-11-08T11:42:09Z${TAB}success=3${TAB}success=1
42475288545${TAB}2026-11-08T11:20:12Z${TAB}success=8${TAB}success=2"
run step_timeouts 2026-10-23
expect "step-timeouts: one argument" 2
run step_timeouts 2026-10-23 x
expect "step-timeouts: a count that is not a number" 2
run step_timeouts 2026-10-23 0
expect "step-timeouts: a count of zero" 2
run step_timeouts yesterday 10
expect "step-timeouts: a date that is not of the API" 2
FAKE_GH_FAIL=1 run step_timeouts 2026-10-23 10
expect "step-timeouts: gh fails" 1
unset FAKE_GH_FAIL

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
# the warnings of CI (docs/adr/0245 sections 2 and 6): werror.sh in the
# changes job, and the logs read in the ci job, apart from gate.sh
if job_of "$CI_YML" changes | grep -qxF '        run: sh scripts/ci/werror.sh'; then ok; else ng "ci.yml: the changes job runs werror.sh"; fi
if [ "$(perms_of "$CI_YML" ci | sort | tr '\n' ' ')" = "actions: read contents: read " ]; then ok; else ng "ci.yml: the ci job has contents: read and actions: read"; fi
if job_of "$CI_YML" ci | grep -qF 'sh scripts/ci/log-warnings.sh scripts/ci/warnings-allowed.tsv' &&
  job_of "$CI_YML" ci | awk '/log-warnings/ { exit } /^      - name: No warning in the logs/ { s = 1 } s && /^        if: always\(\)$/ { f = 1 } END { exit !f }'; then ok; else ng "ci.yml: the ci job checks the logs in a step of its own, also when gate.sh failed"; fi
if [ "$(perms_of "$CI_YML" visual)" = "contents: read
actions: read" ]; then ok; else ng "ci.yml: visual has contents: read and actions: read"; fi
ACTIONS_READ_JOBS=$(ci_jobs "$CI_YML" | while IFS= read -r j; do if perms_of "$CI_YML" "$j" | grep -qx 'actions: read'; then printf '%s\n' "$j"; fi; done)
if [ "$(printf '%s\n' "$ACTIONS_READ_JOBS" | LC_ALL=C sort | tr '\n' ' ')" = "ci visual " ]; then ok; else ng "ci.yml: no job but visual and ci (docs/adr/0245) has actions: read"; fi
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
# determinism.sh builds in the fixtures of its repository and removes their
# build/: here it runs in a copy of what it reads, so that it never writes
# into the fixtures of this repository while scripts/release/test.sh copies
# them at the same time (scripts-macos runs the two at once, run
# 42492125517); the fonts are empty files, which the fake golem does not read
DR=$DET/repo
mkdir -p "$DR/scripts/env-determinism" "$DR/modules/golem-driver/test/fixtures/kanikosen/fonts" "$DR/modules/golem-font/test/fonts"
cp "$HERE/../determinism.sh" "$DR/scripts/"
cp -R "$HERE/../determinism" "$HERE/../manual" "$DR/scripts/"
cp -R "$HERE/../env-determinism/diagnostics" "$DR/scripts/env-determinism/"
for f in sample functions emet-samples complex-vertical complex-horizontal; do
  cp -R "$HERE/../../modules/golem-driver/test/fixtures/$f" "$DR/modules/golem-driver/test/fixtures/"
  rm -rf "${DR:?}/modules/golem-driver/test/fixtures/$f/build"
done
: >"$DR/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf"
: >"$DR/modules/golem-font/test/fonts/SourceSansPro-Regular.otf"
determinism() {
  GOLEM=$DET/bin/golem GOLEM_MANUAL_ROOT=$DET/root GOLEM_MANUAL_SKIP_FONTS=1 \
    GOLEM_MANUAL_COMMIT=0 GOLEM_MANUAL_TAG=v0 FAKE_STDERR=$1 \
    sh "$DR/scripts/determinism.sh"
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
    sh "$DR/scripts/determinism.sh" --no-manuals
}
run determinism_no_manuals '{"diagnostics":[{"code":"G00000"}]}'
expect "determinism: --no-manuals" 0
if grep -qE '  manual(-dev)?/' "$WORK/out"; then ng "determinism: --no-manuals lists no file of the manuals"; else ok; fi
if [ "$(grep -vE '  manual(-dev)?/' "$DET/first")" = "$(cat "$WORK/out")" ]; then ok; else ng "determinism: --no-manuals is the list without the manuals"; fi
determinism_unknown() {
  GOLEM=$DET/bin/golem GOLEM_MANUAL_ROOT=$DET/root sh "$DR/scripts/determinism.sh" --no-such-option
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

# ---------------------------------------------------------------- release.yml calls ci.yml
# A called workflow gets at most the permissions of the job that calls it,
# and a job of ci.yml that asks for more makes every run of release.yml
# end in startup_failure, whether the job would run or not: the ci job of
# release.yml grants each permission that a job of ci.yml asks for, at the
# same level or write (run 42480681991, the caches job of docs/adr/0228).
# It grants actions: write, which caches alone receives, and caches does
# not run on the push of a tag (docs/adr ADR 0287)
# ci_perms CI RELEASE: the predicates P1 to P4 of docs/adr ADR 0287 that
# the two workflows break, one per line with what breaks it
ci_perms() {
  cp_ci=$1 cp_rel=$2
  cp_asked=$(ci_jobs "$cp_ci" | while IFS= read -r j; do perms_of "$cp_ci" "$j"; done | LC_ALL=C sort -u)
  cp_granted=$(perms_of "$cp_rel" ci | LC_ALL=C sort -u)
  # P1 no job but caches asks for actions: write
  ci_jobs "$cp_ci" | while IFS= read -r j; do
    if [ "$j" != caches ] && perms_of "$cp_ci" "$j" | grep -qx 'actions: write'; then printf 'P1 %s\n' "$j"; fi
  done
  # P2 caches runs on pushes to main only
  cp_if=$(job_of "$cp_ci" caches | sed -n 's/^    if: //p')
  case "$cp_if" in
    *"github.event_name == 'push'"*) ;;
    *) echo "P2 github.event_name == 'push'" ;;
  esac
  case "$cp_if" in
    *"github.ref == 'refs/heads/main'"*) ;;
    *) echo "P2 github.ref == 'refs/heads/main'" ;;
  esac
  # P3 nothing granted that no job asks for
  printf '%s\n' "$cp_granted" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\n' "$cp_asked" | grep -qxF "$p" || printf 'P3 %s\n' "$p"
  done
  # P4 everything asked is granted, at the same level or write
  printf '%s\n' "$cp_asked" | while IFS= read -r p; do
    [ -n "$p" ] || continue
    printf '%s\n' "$cp_granted" | grep -qxF -e "$p" -e "${p%%:*}: write" || printf 'P4 %s\n' "$p"
  done
}
CP=$HERE/testdata/ci-permissions
broken=$(ci_perms "$CI_YML" "$RELEASE_YML")
if [ -z "$broken" ]; then ok; else ng "ci.yml and release.yml: P1 to P4 hold (docs/adr ADR 0287): $broken"; fi
# p4 grants no actions: write, which visual asks for as read and caches as write
for cp_case in "now:" "none:" "p1:P1 visual" "p2:P2 github.ref == 'refs/heads/main'" "p3:P3 contents: write" "p4:P4 actions: read|P4 actions: write"; do
  cp_dir=${cp_case%%:*}
  cp_want=$(printf '%s\n' "${cp_case#*:}" | tr '|' '\n')
  cp_got=$(ci_perms "$CP/$cp_dir/ci.yml" "$CP/$cp_dir/release.yml")
  case "$cp_dir" in
    now) cp_name="P1 to P4 hold for the two workflows of testdata" ;;
    none) cp_name="P1 to P4: a job without permissions asks for nothing" ;;
    *) cp_name="$(printf '%s' "$cp_want" | cut -c1-2) breaks for $cp_dir ($cp_want)" ;;
  esac
  if [ "$cp_got" = "$cp_want" ]; then ok; else ng "ci-permissions: $cp_name, got: $cp_got"; fi
done

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
# nothing for the others, as Alloy does; FAKE_JAVA_FAIL makes it fail,
# FAKE_SLOW sleeps for its commands until it is stopped, FAKE_CALLS counts
# the calls, and FAKE_MODELS writes the scopes of the model it was given. A
# model of three commands and its expected.txt.
MC=$WORK/models
mkdir -p "$MC/root/docs/m/models" "$MC/bin"
: >"$MC/alloy.jar"
cat >"$MC/root/docs/m/models/a.als" <<'ALS'
sig A {}
run one { some A } for 3 but 2 Int
run two { no A } for 3 but 2 Int
check three { some A } for 3 but 2 Int
ALS
cat >"$MC/bin/java" <<'JAVA'
#!/bin/sh
[ -z "${FAKE_JAVA_FAIL-}" ] || { echo "java: failed" >&2; exit 1; }
[ -z "${FAKE_CALLS-}" ] || echo call >>"$FAKE_CALLS"
while [ $# -gt 0 ]; do
  case $1 in -c) cmd=$2; shift 2 ;; *) model=$1; shift ;; esac
done
[ -z "${FAKE_MODELS-}" ] || echo "$cmd $(grep -o ' for [0-9]* but ' "$model" | sort -u | tr -d '\n')" >>"$FAKE_MODELS"
case " ${FAKE_SLOW-} " in *" $cmd "*) exec sleep 30 ;; esac
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
# the lists and the commands (docs/adr/0242): -f LIST reads another list,
# COMMANDs run only those, TIMEOUT stops a command and is exit code 3
printf 'one found\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
printf 'two none\n' >"$MC/root/docs/m/models/other.txt"
run models_check -f other.txt
expect "models: -f reads the list of that name" 0 "check: not in other.txt, not run: docs/m/models/a.als one
check: not in other.txt, not run: docs/m/models/a.als three
docs/m/models/a.als two none"
run models_check -f missing.txt
expect "models: a model without the list of -f" 1
if grep -q 'a.als has no missing.txt' "$WORK/err"; then ok; else ng "models: names the list the model does not have"; fi
run models_check -f
expect "models: -f without a list" 2
run models_check three
expect "models: I5 one COMMAND runs that command only" 0 "docs/m/models/a.als three found"
run models_check three one
expect "models: I5 two COMMANDs run those two only" 0 "docs/m/models/a.als one found
docs/m/models/a.als three found"
: >"$MC/calls"
FAKE_CALLS=$MC/calls run models_check one four
expect "models: I5 a COMMAND in no list is an error of the usage" 2
if [ ! -s "$MC/calls" ]; then ok; else ng "models: I5 nothing runs when a COMMAND is in no list"; fi
FAKE_CALLS=$MC/calls run models_check one
unset FAKE_CALLS
if [ "$(wc -l <"$MC/calls" | tr -d ' ')" = 1 ]; then ok; else ng "models: the fake java counts its calls"; fi
FAKE_SLOW=two TIMEOUT=1 run models_check
unset FAKE_SLOW TIMEOUT
expect "models: I3 I4 a time-out alone is exit code 3" 3 "docs/m/models/a.als one found
check: time-out after 1 s, not decided: docs/m/models/a.als two
docs/m/models/a.als three found"
if grep -qE 'a\.als two (found|none)' "$WORK/out" "$WORK/err"; then ng "models: I3 a time-out is neither found nor none"; else ok; fi
printf 'one none\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
FAKE_SLOW=two TIMEOUT=1 run models_check
unset FAKE_SLOW TIMEOUT
expect "models: I4 a time-out does not hide a wrong result" 1
if grep -q 'a.als one: found, but expected.txt says none' "$WORK/err" && grep -q 'time-out after 1 s, not decided: docs/m/models/a.als two' "$WORK/out"; then ok; else ng "models: I4 the wrong result and the time-out are both written"; fi
printf 'one found\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
TIMEOUT=0 run models_check
unset TIMEOUT
expect "models: TIMEOUT=0 is no limit" 0 "docs/m/models/a.als one found
docs/m/models/a.als two none
docs/m/models/a.als three found"
TIMEOUT= run models_check
unset TIMEOUT
expect "models: an empty TIMEOUT is no limit" 0 "docs/m/models/a.als one found
docs/m/models/a.als two none
docs/m/models/a.als three found"
TIMEOUT=x run models_check
unset TIMEOUT
expect "models: a TIMEOUT that is not a number" 2
rm "$MC/root/docs/m/models/other.txt"
# a scope in the list runs a copy of the model at that scope
: >"$MC/models"
printf 'one found 2\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"
FAKE_MODELS=$MC/models run models_check
unset FAKE_MODELS
expect "models: a command with a scope in the list" 0 "docs/m/models/a.als one found
docs/m/models/a.als two none
docs/m/models/a.als three found"
if grep -qx 'one  for 2 but ' "$MC/models" && grep -qx 'two  for 3 but ' "$MC/models"; then ok; else ng "models: the scope of the list replaces that of the model for its command only"; fi
# every "for <n> but" of a line is replaced, not the first alone (docs/adr/0242)
mkdir -p "$MC/root/docs/m2/models"
printf 'sig B {}\nrun four { some B } for 3 but 2 Int -- was for 2 but 2 Int\n' >"$MC/root/docs/m2/models/b.als"
printf 'four none 4\n' >"$MC/root/docs/m2/models/expected.txt"
: >"$MC/models"
FAKE_MODELS=$MC/models run models_check
unset FAKE_MODELS
expect "models: a model of two \"for <n> but\" on a line" 0 "docs/m/models/a.als one found
docs/m/models/a.als two none
docs/m/models/a.als three found
docs/m2/models/b.als four none"
if grep -qx 'four  for 4 but ' "$MC/models"; then ok; else ng "models: every \"for <n> but\" of a line gets the scope of the list (docs/adr/0242)"; fi
rm -r "$MC/root/docs/m2"
printf 'one found x\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: a scope that is not a number" 1
if grep -q 'one: not a scope: x' "$WORK/err"; then ok; else ng "models: names the scope that is not a number"; fi
printf 'one found 2 more\n' >"$MC/root/docs/m/models/expected.txt"
run models_check
expect "models: more than a command, its result and its scope" 1
printf 'one found\ntwo none\nthree found\n' >"$MC/root/docs/m/models/expected.txt"

# the models of the repository (docs/adr/0242): I2 each command of a model
# is in exactly one of expected.txt and nightly.txt
for model in "$HERE"/../../docs/*/models/*.als; do
  [ -f "$model" ] || continue
  dir=$(dirname "$model")
  name=${model#"$HERE"/../../}
  sed -n 's/^run[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p; s/^check[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$model" | sort -u >"$WORK/model-commands"
  cat "$dir/expected.txt" "$dir/nightly.txt" 2>/dev/null | awk '$1 !~ /^#/ && NF { print $1 }' | sort >"$WORK/listed-commands"
  if [ -s "$WORK/model-commands" ] && [ "$(sort -u "$WORK/listed-commands")" = "$(cat "$WORK/model-commands")" ] &&
    [ -z "$(uniq -d "$WORK/listed-commands")" ]; then ok; else ng "models: I2 each command of $name is in exactly one of expected.txt and nightly.txt"; fi
done
# the jar: fetched by scripts/ci/fetch-url.sh into GOLEM_DOWNLOADS, by its
# name of the release, and one there of the SHA-256 is used without curl
# (docs/adr/0243). A copy of check.sh pins the SHA-256 of a fake jar
mkdir -p "$MC/fr/scripts/models" "$MC/fr/scripts/ci"
cp "$HERE/fetch-url.sh" "$MC/fr/scripts/ci/"
printf 'a jar\n' >"$MC/fake.jar"
sed "s/^ALLOY_SHA256=.*/ALLOY_SHA256=$(fu_sha "$MC/fake.jar")/" "$HERE/../models/check.sh" >"$MC/fr/scripts/models/check.sh"
cat >"$MC/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$MC_CURL_LOG"
while [ $# -gt 0 ]; do
  case "$1" in -o) cp "$MC_JAR" "$2" || exit 22; shift ;; esac
  shift
done
FAKE
chmod +x "$MC/bin/curl"
mc_fetch() { env PATH="$MC/bin:$PATH" MC_CURL_LOG="$MC/curl.log" GOLEM_ROOT="$MC/root" JAVA="$MC/bin/java" JOBS=2 FAKE_FOUND="one three" "$@" sh "$MC/fr/scripts/models/check.sh"; }
MC_DL=$MC/fr/third_party/downloads/org.alloytools.alloy.dist.jar
: >"$MC/curl.log"
run mc_fetch MC_JAR="$MC/fake.jar"
if [ "$CODE" = 0 ] && cmp -s "$MC/fake.jar" "$MC_DL" && grep -qF "https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v6.2.0/org.alloytools.alloy.dist.jar" "$MC/curl.log"; then ok; else ng "models: the jar is fetched into third_party/downloads (docs/adr/0243)"; fi
: >"$MC/curl.log"
run mc_fetch MC_JAR="$MC/fake.jar"
if [ "$CODE" = 0 ] && [ ! -s "$MC/curl.log" ]; then ok; else ng "models: a jar of the SHA-256 in third_party/downloads is not fetched again (docs/adr/0243)"; fi
printf 'other\n' >"$MC_DL"
run mc_fetch MC_JAR="$MC/fake.jar"
if [ "$CODE" = 0 ] && [ -s "$MC/curl.log" ] && cmp -s "$MC/fake.jar" "$MC_DL"; then ok; else ng "models: a jar of another SHA-256 in third_party/downloads is fetched again (docs/adr/0243)"; fi
rm -rf "$MC/elsewhere"
run mc_fetch MC_JAR="$MC/fake.jar" GOLEM_DOWNLOADS="$MC/elsewhere"
if [ "$CODE" = 0 ] && cmp -s "$MC/fake.jar" "$MC/elsewhere/org.alloytools.alloy.dist.jar"; then ok; else ng "models: GOLEM_DOWNLOADS is where the jar is kept (docs/adr/0243)"; fi
printf 'replaced\n' >"$MC/replaced.jar"
rm -rf "$MC/fr/third_party"
run mc_fetch MC_JAR="$MC/replaced.jar" FETCH_ATTEMPTS=1
if [ "$CODE" = 1 ] && [ ! -e "$MC_DL" ] && grep -qF 'SHA-256 mismatch' "$WORK/err"; then ok; else ng "models: a jar of another SHA-256 fails, and is not kept"; fi
# I6 models.yml runs expected.txt, models-nightly.yml runs nightly.txt, only
# on a schedule and by hand, reading the repository and the runs
MODELS_YML=$HERE/../../.github/workflows/models.yml
NIGHTLY_YML=$HERE/../../.github/workflows/models-nightly.yml
if grep -q 'sh scripts/models/check.sh$' "$MODELS_YML" && ! grep -q 'check.sh -f' "$MODELS_YML"; then ok; else ng "models.yml: I6 check.sh reads expected.txt"; fi
if grep -qF 'sh scripts/models/check.sh -f nightly.txt "$COMMAND"' "$NIGHTLY_YML"; then ok; else ng "models-nightly.yml: I6 check.sh reads nightly.txt, one command a job"; fi
if [ "$(awk '/^on:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z_]/' "$NIGHTLY_YML")" = "  schedule:
  workflow_dispatch:" ]; then ok; else ng "models-nightly.yml: I6 only schedule and workflow_dispatch"; fi
if [ "$(awk '/^permissions:/ { on = 1; next } on && /^[^ ]/ { on = 0 } on && /^  [a-z]/' "$NIGHTLY_YML")" = "  contents: read
  actions: read" ]; then ok; else ng "models-nightly.yml: the permissions are contents: read and actions: read"; fi
if grep -qF 'sh scripts/ci/race-needed.sh "$GITHUB_SHA" models-nightly.yml' "$NIGHTLY_YML"; then ok; else ng "models-nightly.yml: race-needed.sh decides whether it runs"; fi

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

# ---------------------------------------------------------------- enum.yml
# (docs/adr/0281-budgets-of-the-exhaustive-tests-and-what-moves-to-the-nightly-job.md)

ENUM_YML=$HERE/../../.github/workflows/enum.yml
enum_timings() { sh "$HERE/enum-timings.sh" "$@"; }
: >"$WORK/in"
run enum_timings --list "$ENUM_YML"
EA=$WORK/enum-areas
cp "$WORK/out" "$EA"
: >"$WORK/out"
# every step with the depth of an area is an area
if [ "$CODE" = 0 ] && [ "$(wc -l <"$EA" | tr -d ' ')" = "$(grep -c '^          GOLEM_ENUM_[A-Z0-9_]*DEPTH:' "$ENUM_YML")" ] && [ -s "$EA" ]; then ok; else ng "enum.yml: every step with GOLEM_ENUM_*DEPTH is an area"; fi
# N4 the step of every area runs whatever the steps before it gave, unless the job is cancelled
if [ -s "$EA" ] && ! awk -F '\t' 'index($3, "!cancelled()") == 0 { bad = 1 } END { exit bad }' "$EA"; then
  ng "enum.yml: N4 the step of every area has !cancelled()"
  awk -F '\t' 'index($3, "!cancelled()") == 0 { print "  " $1 ": " $3 }' "$EA"
else ok; fi
# N5 exactly one step times the areas, before the step of the first area, into the summary of the job
first_area=$(grep -n '^          GOLEM_ENUM_[A-Z0-9_]*DEPTH:' "$ENUM_YML" | head -n 1 | cut -d: -f1)
timing_lines=$(grep -n 'sh scripts/ci/enum-timings.sh' "$ENUM_YML" | grep -v -- '--median' | cut -d: -f1)
if [ "$(printf '%s\n' "$timing_lines" | grep -c .)" = 1 ] && [ -n "$first_area" ] && [ "$timing_lines" -lt "$first_area" ] &&
  grep -qF 'sh scripts/ci/enum-timings.sh > "$RUNNER_TEMP/enum-timings.md"' "$ENUM_YML" &&
  grep -qF 'cat "$RUNNER_TEMP/enum-timings.md" >> "$GITHUB_STEP_SUMMARY"' "$ENUM_YML"; then ok; else
  ng "enum.yml: N5 one step runs enum-timings.sh into \$GITHUB_STEP_SUMMARY, before the first area"
fi

# started by hand with timings, four jobs time the areas alone, and a job
# after them writes the medians of their tables into the summary
# (docs/adr ADR 0286)
if awk '/^  workflow_dispatch:/ { on = 1; next } on && /^  [a-z]/ { on = 0 } on' "$ENUM_YML" | grep -qx '        type: boolean' &&
  grep -qxF "        job: \${{ fromJSON(inputs.timings && '[1, 2, 3, 4]' || '[1]') }}" "$ENUM_YML"; then ok; else
  ng "enum.yml: the input timings runs four jobs, and one without it"
fi
if [ -s "$EA" ] && ! awk -F '\t' 'index($3, "!inputs.timings") == 0 { bad = 1 } END { exit bad }' "$EA"; then
  ng "enum.yml: the step of every area is left out when timing"
else ok; fi
if grep -qF '          name: enum-timings-${{ matrix.job }}' "$ENUM_YML" &&
  awk '/^  medians:/ { on = 1 } on' "$ENUM_YML" | grep -qF '    needs: enum' &&
  awk '/^  medians:/ { on = 1 } on' "$ENUM_YML" | grep -qF "    if: \${{ !cancelled() && inputs.timings }}" &&
  awk '/^  medians:/ { on = 1 } on' "$ENUM_YML" | grep -qF 'sh scripts/ci/enum-timings.sh --median "$RUNNER_TEMP"/tables/enum-timings-*/enum-timings.md > "$RUNNER_TEMP/medians.md"' &&
  awk '/^  medians:/ { on = 1 } on' "$ENUM_YML" | grep -qF 'cat "$RUNNER_TEMP/medians.md" >> "$GITHUB_STEP_SUMMARY"'; then ok; else
  ng "enum.yml: each job keeps its table, and the job medians writes their medians into the summary"
fi

# enum-timings.sh on workflows of its own: a cabal whose list-bin names a
# test executable that says what it was given, and a clock that gives the
# times of a list, one per call; the three write what they did, in order,
# to one log (docs/adr ADR 0286)
ET=$WORK/enum-timings
mkdir -p "$ET"
cat >"$ET/cabal" <<'CABAL'
#!/bin/sh
printf 'cabal %s\n' "$*" >>"$ET_DIR/events"
case "$*" in
  "list-bin golem-layout-test") [ -z "${ET_NO_BIN-}" ] || exit 1; printf '%s\n' "$ET_DIR/bin" ;;
  *) exit 1 ;;
esac
CABAL
chmod +x "$ET/cabal"
cat >"$ET/bin" <<'BIN'
#!/bin/sh
printf 'bin %s|%s|%s\n' "$*" "${GOLEM_ENUM_DEPTH-unset}" "${GOLEM_ENUM_LINES_SAMPLES-unset}" >>"$ET_DIR/events"
case "$*" in *"/broken/"*) exit 1 ;; esac
exit 0
BIN
chmod +x "$ET/bin"
cat >"$ET/clock" <<'CLOCK'
#!/bin/sh
echo clock >>"$ET_DIR/events"
head -n 1 "$ET_DIR/times"
tail -n +2 "$ET_DIR/times" >"$ET_DIR/times.next"
mv "$ET_DIR/times.next" "$ET_DIR/times"
CLOCK
chmod +x "$ET/clock"
# et_workflow FILE PATTERN...: a workflow with one area per pattern, and a step that is not one
et_workflow() {
  out=$1
  shift
  {
    printf 'name: Enum\njobs:\n  enum:\n    steps:\n      - uses: actions/checkout@v7\n      - name: Build\n        run: cabal build golem-layout-test\n'
    n=0
    for p in "$@"; do
      n=$((n + 1))
      printf "      - name: Area %s\n        if: \${{ !cancelled() }}\n        env:\n          GOLEM_ENUM_A%s_DEPTH: \"3\"\n        run: cabal test golem-layout-test --test-option=-p --test-option='%s'\n" "$n" "$n" "$p"
    done
  } >"$out"
}
et_run() {
  printf '%s\n' "$@" >"$ET/times"
  : >"$ET/events"
  run env ET_DIR="$ET" CABAL="$ET/cabal" CLOCK="$ET/clock" GOLEM_ENUM_DEPTH=5 GOLEM_ENUM_LINES_SAMPLES=9 sh "$HERE/enum-timings.sh" "$ET/w.yml"
}
et_workflow "$ET/w.yml" '/one/' '/two/&&/three/'
run enum_timings --list "$ET/w.yml"
expect "enum-timings: --list writes the variable, the pattern and the condition of each area" 0 "GOLEM_ENUM_A1_DEPTH	/one/	\${{ !cancelled() }}
GOLEM_ENUM_A2_DEPTH	/two/&&/three/	\${{ !cancelled() }}"
# the budget of an area is 10 seconds: exactly 10 is within it, 10.01 is over
et_run 100 110 200 210.01
expect "enum-timings: N5 a row per area and the sum, 10 seconds within the budget and 10.01 over" 0 "| 範囲 | \`-p\` の式 | 秒 | 予算 | テスト |
| --- | --- | --- | --- | --- |
| \`GOLEM_ENUM_A1_DEPTH\` | \`/one/\` | 10.00 | 10 秒以内 | 通る |
| \`GOLEM_ENUM_A2_DEPTH\` | \`/two/&&/three/\` | 10.01 | 10 秒を超える | 通る |
| 和 | | 20.01 | 30 秒以内 | |"
# M1 the executable of cabal list-bin runs once an area, with -p and the
# pattern and no variable GOLEM_ENUM_*, between the two readings of the
# clock; cabal runs no test
if [ "$(cat "$ET/events")" = "cabal list-bin golem-layout-test
clock
bin -p /one/|unset|unset
clock
clock
bin -p /two/&&/three/|unset|unset
clock" ]; then ok; else ng "enum-timings: M1 two areas time the executable alone, once each, with -p and the pattern"; sed 's/^/  /' "$ET/events"; fi
et_workflow "$ET/w.yml" '/a/' '/b/' '/c/' '/d/' '/e/' '/f/'
et_run 0 1 1 2 2 3 3 4 4 5 5 6
if [ "$CODE" = 0 ] && [ "$(grep -c '^bin -p /[a-f]/|unset|unset$' "$ET/events")" = 6 ] && [ "$(grep -c '^cabal ' "$ET/events")" = 1 ] &&
  [ "$(grep -c '^clock$' "$ET/events")" = 12 ] && [ "$(tail -n 1 "$WORK/out")" = "| 和 | | 6.00 | 30 秒以内 | |" ]; then ok; else
  ng "enum-timings: M1 six areas run the executable six times, and cabal once"
fi
# M1 without the executable: no table, no test, and the script fails
et_workflow "$ET/w.yml" '/one/'
printf '0\n1\n' >"$ET/times"
: >"$ET/events"
run env ET_DIR="$ET" ET_NO_BIN=1 CABAL="$ET/cabal" CLOCK="$ET/clock" sh "$HERE/enum-timings.sh" "$ET/w.yml"
if [ "$CODE" != 0 ] && [ ! -s "$WORK/out" ] && [ "$(cat "$ET/events")" = "cabal list-bin golem-layout-test" ]; then ok; else ng "enum-timings: M1 cabal list-bin fails, and so does the script, before any test"; fi
# the sum: 30 seconds within the budget, over it when every area is within its own
et_workflow "$ET/w.yml" '/a/' '/b/' '/c/'
et_run 0 10 10 20 20 30
if [ "$CODE" = 0 ] && [ "$(tail -n 1 "$WORK/out")" = "| 和 | | 30.00 | 30 秒以内 | |" ]; then ok; else ng "enum-timings: a sum of 30 seconds is within the budget"; fi
et_workflow "$ET/w.yml" '/a/' '/b/' '/c/' '/d/'
et_run 0 8 8 16 16 24 24 32
if [ "$CODE" = 0 ] && [ "$(tail -n 1 "$WORK/out")" = "| 和 | | 32.00 | 30 秒を超える | |" ] && [ "$(grep -c '10 秒以内' "$WORK/out")" = 4 ]; then ok; else ng "enum-timings: only the sum over its budget, and the script does not fail"; fi
# tests that fail fail the script, after every area has run
et_workflow "$ET/w.yml" '/broken/' '/b/'
et_run 0 1 1 2
if [ "$CODE" = 1 ] && grep -qF '| `/broken/` | 1.00 | 10 秒以内 | 落ちる |' "$WORK/out" && grep -qF '| `/b/` | 1.00 | 10 秒以内 | 通る |' "$WORK/out"; then ok; else ng "enum-timings: a failing area fails the script after the others ran"; fi
# a step without the depth of an area, or another command, is not an area
printf "jobs:\n  enum:\n    steps:\n      - name: no depth\n        run: cabal test golem-layout-test --test-option=-p --test-option='/x/'\n      - name: other\n        env:\n          GOLEM_ENUM_X_DEPTH: \"3\"\n        run: cabal test golem-layout-test\n" >"$ET/none.yml"
run enum_timings --list "$ET/none.yml"
expect "enum-timings: a step is an area with both a depth and a pattern" 0 ""
run enum_timings "$ET/none.yml"
expect "enum-timings: a workflow without areas fails" 1

# enum-timings.sh --median on tables of its own (docs/adr ADR 0286)
# et_table FILE SUM SECONDS...: a table of enum-timings.sh with an area
# /aN/ of GOLEM_ENUM_AN_DEPTH for each of SECONDS, and the sum SUM
et_table() {
  out=$1 sum=$2
  shift 2
  {
    printf '| 範囲 | `-p` の式 | 秒 | 予算 | テスト |\n| --- | --- | --- | --- | --- |\n'
    n=0
    for s in "$@"; do
      n=$((n + 1))
      printf '| `GOLEM_ENUM_A%s_DEPTH` | `/a%s/` | %s | - | 通る |\n' "$n" "$n" "$s"
    done
    printf '| 和 | | %s | - | |\n' "$sum"
  } >"$out"
}
EM=$ET/median
mkdir -p "$EM"
# M2 one table: its own seconds
et_table "$EM/1" 3.00 1.00 2.00
run enum_timings --median "$EM/1"
expect "enum-timings: M2 the median of one table is its seconds" 0 "| 範囲 | \`-p\` の式 | 1 | 中央値 | 予算 |
| --- | --- | --- | --- | --- |
| \`GOLEM_ENUM_A1_DEPTH\` | \`/a1/\` | 1.00 | 1.00 | 10 秒以内 |
| \`GOLEM_ENUM_A2_DEPTH\` | \`/a2/\` | 2.00 | 2.00 | 10 秒以内 |
| 和 | | 3.00 | 3.00 | 30 秒以内 |"
# M2 two tables: the mean of the two in the middle
et_table "$EM/2" 7.00 2.00 5.00
run enum_timings --median "$EM/1" "$EM/2"
expect "enum-timings: M2 the median of two tables is the mean of the two" 0 "| 範囲 | \`-p\` の式 | 1 | 2 | 中央値 | 予算 |
| --- | --- | --- | --- | --- | --- |
| \`GOLEM_ENUM_A1_DEPTH\` | \`/a1/\` | 1.00 | 2.00 | 1.50 | 10 秒以内 |
| \`GOLEM_ENUM_A2_DEPTH\` | \`/a2/\` | 2.00 | 5.00 | 3.50 | 10 秒以内 |
| 和 | | 3.00 | 7.00 | 5.00 | 30 秒以内 |"
# M2 three tables: the one in the middle, whatever the order of the tables
et_table "$EM/3" 4.00 9.00 0.50
run enum_timings --median "$EM/3" "$EM/1" "$EM/2"
if [ "$CODE" = 0 ] && grep -qxF '| `GOLEM_ENUM_A1_DEPTH` | `/a1/` | 9.00 | 1.00 | 2.00 | 2.00 | 10 秒以内 |' "$WORK/out" &&
  grep -qxF '| `GOLEM_ENUM_A2_DEPTH` | `/a2/` | 0.50 | 2.00 | 5.00 | 2.00 | 10 秒以内 |' "$WORK/out" &&
  grep -qxF '| 和 | | 4.00 | 3.00 | 7.00 | 4.00 | 30 秒以内 |' "$WORK/out"; then ok; else ng "enum-timings: M2 the median of three tables is the one in the middle"; fi
# M2 four tables, where the median of the sums (8, 9, 10, 10: 9.50) is not
# the sum of the medians of the areas (5.00 + 3.50 = 8.50)
et_table "$EM/4a" 10.00 1.00 9.00
et_table "$EM/4b" 10.00 9.00 1.00
et_table "$EM/4c" 8.00 4.00 4.00
et_table "$EM/4d" 9.00 6.00 3.00
run enum_timings --median "$EM/4a" "$EM/4b" "$EM/4c" "$EM/4d"
expect "enum-timings: M2 the sum is the median of the sums of four tables, not the sum of the medians" 0 "| 範囲 | \`-p\` の式 | 1 | 2 | 3 | 4 | 中央値 | 予算 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| \`GOLEM_ENUM_A1_DEPTH\` | \`/a1/\` | 1.00 | 9.00 | 4.00 | 6.00 | 5.00 | 10 秒以内 |
| \`GOLEM_ENUM_A2_DEPTH\` | \`/a2/\` | 9.00 | 1.00 | 4.00 | 3.00 | 3.50 | 10 秒以内 |
| 和 | | 10.00 | 10.00 | 8.00 | 9.00 | 9.50 | 30 秒以内 |"
# M3 the budgets on the medians: 10.00 and 30.00 within, 10.01 and 30.01 over
et_table "$EM/b1" 30.00 10.00 20.00
run enum_timings --median "$EM/b1"
if [ "$CODE" = 0 ] && grep -qxF '| `GOLEM_ENUM_A1_DEPTH` | `/a1/` | 10.00 | 10.00 | 10 秒以内 |' "$WORK/out" &&
  grep -qxF '| 和 | | 30.00 | 30.00 | 30 秒以内 |' "$WORK/out"; then ok; else ng "enum-timings: M3 a median of 10.00 an area and 30.00 in all is within the budgets"; fi
et_table "$EM/b2" 30.01 10.01 20.00
run enum_timings --median "$EM/b2"
if [ "$CODE" = 0 ] && grep -qxF '| `GOLEM_ENUM_A1_DEPTH` | `/a1/` | 10.01 | 10.01 | 10 秒を超える |' "$WORK/out" &&
  grep -qxF '| 和 | | 30.01 | 30.01 | 30 秒を超える |' "$WORK/out"; then ok; else ng "enum-timings: M3 a median of 10.01 an area and 30.01 in all is over the budgets"; fi
# M3 one table over the budgets, the median within: no mark
et_table "$EM/c1" 40.00 12.00 1.00
et_table "$EM/c2" 20.00 8.00 1.00
et_table "$EM/c3" 20.00 9.00 1.00
run enum_timings --median "$EM/c1" "$EM/c2" "$EM/c3"
if [ "$CODE" = 0 ] && ! grep -q '超える' "$WORK/out" && grep -qxF '| `GOLEM_ENUM_A1_DEPTH` | `/a1/` | 12.00 | 8.00 | 9.00 | 9.00 | 10 秒以内 |' "$WORK/out" &&
  grep -qxF '| 和 | | 40.00 | 20.00 | 20.00 | 20.00 | 30 秒以内 |' "$WORK/out"; then ok; else ng "enum-timings: M3 one table over the budgets, the medians within, marks nothing"; fi
# M4 the areas of the tables differ: no table, and the script fails
et_table "$EM/m1" 3.00 1.00 2.00
et_table "$EM/m2" 1.00 1.00
run enum_timings --median "$EM/m1" "$EM/m1" "$EM/m2"
if [ "$CODE" != 0 ] && [ ! -s "$WORK/out" ]; then ok; else ng "enum-timings: M4 a table without one of the areas fails, writing no table"; fi
sed 's|`/a1/`|`/a9/`|' "$EM/m1" >"$EM/m3"
run enum_timings --median "$EM/m1" "$EM/m3"
if [ "$CODE" != 0 ] && [ ! -s "$WORK/out" ]; then ok; else ng "enum-timings: M4 a table with another pattern fails, writing no table"; fi
{ sed -n 1,2p "$EM/m1"; sed -n 4p "$EM/m1"; sed -n 3p "$EM/m1"; sed -n 5p "$EM/m1"; } >"$EM/m4"
run enum_timings --median "$EM/m1" "$EM/m4"
if [ "$CODE" != 0 ] && [ ! -s "$WORK/out" ]; then ok; else ng "enum-timings: M4 the areas in another order fail, writing no table"; fi
run enum_timings --median "$EM/m1" "$EM/m1"
expect "enum-timings: M4 the same areas in the same order make a table" 0
run enum_timings --median
expect "enum-timings: --median needs a table" 2

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
# (docs/adr/0293 A1): wasm is every suite of the golem packages that the
# packages: of cabal.project.wasm, next to MODULES, lists, and no other
printf 'packages:\n  modules/golem-pdf\n  modules/other-dir\n  third_party/wasm-packages/skylighting-0.15\n\ntests: False\n\npackage golem-driver\n  flags: -plugins\n' >"$WORK/cabal.project.wasm"
run test_suites wasm "$TS"
expect "A1 test-suites: wasm has the suites of the golem packages of cabal.project.wasm" 0 "golem-pdf:test:golem-pdf-test
golem-renamed:test:renamed-test"
rm -f "$WORK/cabal.project.wasm"
run test_suites wasm "$TS"
expect "A1 test-suites: wasm without cabal.project.wasm" 1
test_suites wasm >"$WORK/ts-wasm" 2>"$WORK/err" || true
for d in $(sed -n 's|^  modules/\([a-z0-9-]*\)[[:space:]]*$|\1|p' "$HERE/../../cabal.project.wasm"); do
  f="$HERE/../../modules/$d/$d.cabal"
  pkg=$(awk 'tolower($1) == "name:" { print $2; exit }' "$f")
  awk -v p="$pkg" 'tolower($1) == "test-suite" { print p ":test:" $2 }' "$f"
done | LC_ALL=C sort >"$WORK/ts-wasm-every"
if [ -s "$WORK/ts-wasm-every" ] && [ "$(LC_ALL=C sort "$WORK/ts-wasm")" = "$(cat "$WORK/ts-wasm-every")" ]; then ok; else
  ng "A1 test-suites: wasm is every suite of the golem packages of cabal.project.wasm"
fi
if grep -qF 'sh scripts/ci/test-suites.sh wasm' "$HERE/../../.github/workflows/wasm-tests.yml" 2>/dev/null; then ok; else
  ng "A1 wasm-tests.yml: runs the suites of test-suites.sh wasm"
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
# The options are under if !arch(wasm32), indented (docs/adr/0293)

# stanza NAME: the lines of the test-suite NAME of golem-driver.cabal
DRIVER_CABAL=$HERE/../../modules/golem-driver/golem-driver.cabal
stanza() { awk -v n="test-suite $1" '$0 == n { on = 1; next } on && /^[^ \t-]/ { on = 0 } on' "$DRIVER_CABAL"; }
# modules NAME: the other-modules of the test-suite NAME, one per line, those
# under a condition too (the flag plugins, docs/adr ADR 0300)
modules_of() {
  stanza "$1" | awk '
    /^ +other-modules:/ { on = 1; sub(/^ +other-modules: */, ""); if ($0 != "") print $1; next }
    on && /^ +([a-z-]+:|if |else)/ { on = 0 }
    on { print $1 }'
}
if stanza golem-driver-test | grep -Eq '^ +ghc-options: .*-threaded' && stanza golem-driver-test | grep -qF '"-with-rtsopts=-N"'; then ok; else
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
# (docs/adr/0293 section 1): the project of the test suites on wasm32
# takes cabal.project.wasm and its freeze, which cabal does not read for
# a project file of another name
printf 'import: cabal.project.wasm\n\ntests: True\n' >"$WORK/wasm-tests.project"
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WF_DATA/wasm.freeze" "$WORK/wasm-tests.project"
expect "wasm-freeze: a project of the tests that does not import cabal.project.wasm.freeze fails" 1
printf 'import: cabal.project.wasm\nimport: cabal.project.wasm.freeze\n\ntests: True\n' >"$WORK/wasm-tests.project"
run sh "$HERE/wasm-freeze.sh" "$WF_DATA/native.freeze" "$WF_DATA/wasm.freeze" "$WORK/wasm-tests.project"
expect "wasm-freeze: a project of the tests that imports cabal.project.wasm and its freeze passes" 0

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
mkdir -p "$FW/root/scripts/wasm/patches" "$FW/root/scripts/ci" "$FW/src/skylighting-core-0.15.0.1" "$FW/src/skylighting-0.15.0.1" "$FW/archives" "$FW/bin"
cp "$HERE/fetch-url.sh" "$FW/root/scripts/ci/"
printf 'module A\nimport Skylighting.Parser\n' >"$FW/src/skylighting-core-0.15.0.1/A.hs"
printf 'module B\nimport Skylighting.Loader\n' >"$FW/src/skylighting-0.15.0.1/B.hs"
for p in skylighting-core-0.15.0.1 skylighting-0.15.0.1; do (cd "$FW/src" && tar -czf "$FW/archives/$p.tar.gz" "$p"); done
cat >"$FW/root/scripts/wasm/patches/skylighting-core-0.15.0.1.patch" <<'EOF'
--- a/A.hs
+++ b/A.hs
@@ -1,2 +1 @@
 module A
-import Skylighting.Parser
EOF
cat >"$FW/root/scripts/wasm/patches/skylighting-0.15.0.1.patch" <<'EOF'
--- a/B.hs
+++ b/B.hs
@@ -1,2 +1 @@
 module B
-import Skylighting.Loader
EOF
fw_sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
sed -e "s/^CORE_SHA=.*/CORE_SHA=$(fw_sha "$FW/archives/skylighting-core-0.15.0.1.tar.gz")/" \
  -e "s/^SKY_SHA=.*/SKY_SHA=$(fw_sha "$FW/archives/skylighting-0.15.0.1.tar.gz")/" \
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
if grep -qF "https://hackage.haskell.org/package/skylighting-core-0.15.0.1/skylighting-core-0.15.0.1.tar.gz" "$FW/curl.log" &&
  grep -qF "https://hackage.haskell.org/package/skylighting-0.15.0.1/skylighting-0.15.0.1.tar.gz" "$FW/curl.log"; then ok; else ng "fetch-wasm-packages: the archives come from Hackage"; fi
if [ "$(cat "$FW/root/third_party/wasm-packages/skylighting-core-0.15.0.1/A.hs")" = "module A" ] &&
  [ "$(cat "$FW/root/third_party/wasm-packages/skylighting-0.15.0.1/B.hs")" = "module B" ]; then ok; else ng "fetch-wasm-packages: the patches are applied"; fi
fw_tree >"$FW/tree1"
# the archives are kept in third_party/downloads, and not fetched again
# (docs/adr/0243)
if cmp -s "$FW/archives/skylighting-core-0.15.0.1.tar.gz" "$FW/root/third_party/downloads/skylighting-core-0.15.0.1.tar.gz" &&
  cmp -s "$FW/archives/skylighting-0.15.0.1.tar.gz" "$FW/root/third_party/downloads/skylighting-0.15.0.1.tar.gz"; then ok; else ng "fetch-wasm-packages: the archives are kept in third_party/downloads (docs/adr/0243)"; fi
: >"$FW/curl.log"
run fetch_wasm
expect "fetch-wasm-packages: a second run passes" 0
fw_tree >"$FW/tree2"
if cmp -s "$FW/tree1" "$FW/tree2"; then ok; else ng "fetch-wasm-packages: two runs make the same tree"; fi
if [ ! -s "$FW/curl.log" ]; then ok; else ng "fetch-wasm-packages: the archives in third_party/downloads are not fetched again (docs/adr/0243)"; fi
printf 'other\n' >"$FW/root/third_party/downloads/skylighting-0.15.0.1.tar.gz"
run fetch_wasm
if [ "$CODE" = 0 ] && [ "$(grep -c . "$FW/curl.log")" = 1 ] && cmp -s "$FW/archives/skylighting-0.15.0.1.tar.gz" "$FW/root/third_party/downloads/skylighting-0.15.0.1.tar.gz"; then ok; else ng "fetch-wasm-packages: an archive of another SHA-256 in third_party/downloads is fetched again (docs/adr/0243)"; fi
# one character of the SHA-256 changed: nothing is unpacked
rm -rf "$FW/root/third_party"
sed 's/^\(CORE_SHA=.\{63\}\)./\1x/' "$FW/root/scripts/fetch-wasm-packages.sh" >"$FW/bad-sha.sh"
cp "$FW/root/scripts/fetch-wasm-packages.sh" "$FW/good.sh"
cp "$FW/bad-sha.sh" "$FW/root/scripts/fetch-wasm-packages.sh"
rm -rf "$FW/root/third_party"
run fetch_wasm
expect "fetch-wasm-packages: an archive of another SHA-256 fails" 1
if [ ! -e "$FW/root/third_party/wasm-packages/skylighting-core-0.15.0.1" ]; then ok; else ng "fetch-wasm-packages: an archive of another SHA-256 is not unpacked"; fi
cp "$FW/good.sh" "$FW/root/scripts/fetch-wasm-packages.sh"
# a patch that does not apply fails
printf -- '--- a/A.hs\n+++ b/A.hs\n@@ -1,2 +1 @@\n module X\n-import Y\n' >"$FW/root/scripts/wasm/patches/skylighting-core-0.15.0.1.patch"
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
# the form of the lists: three lines for each of the fourteen inputs
# (the six of int-width, docs/adr/0247 section 7)
cb_form() {
  for name in kanikosen determinism pdf complex-vertical complex-horizontal broken-style missing-font broken-cmap \
    int-width int-width-reference int-width-icc int-width-png int-width-png-chunk int-width-printing; do
    grep -Eq "^([0-9a-f]{64}|-)  $name/pdf\$" "$1" && grep -Eq "^[0-9a-f]{64}  $name/diagnostics\$" "$1" && grep -Eq "^exit [0-9]+  $name\$" "$1" || return 1
  done
  [ "$(wc -l <"$1" | tr -d ' ')" = 42 ]
}
run env DENO="$CB/deno" sh "$HERE/../wasm/compare.sh" --deno golem.wasm
cp "$WORK/out" "$CB/deno.txt"
expect "compare.sh --deno: runs every input" 0
if cb_form "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the list has the form of that of node:wasi (docs/adr/0234 I5)"; fi
if grep -qxF "$(printf '%%PDF kanikosen\n' | cb_sha)  kanikosen/pdf" "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the SHA-256 of the PDF that run.mjs wrote"; fi
if grep -qxF "$(printf '[]\n' | cb_sha)  kanikosen/diagnostics" "$CB/deno.txt"; then ok; else ng "compare.sh --deno: the warning of Deno is not in the JSON"; fi
run env PATH="$CB/bin:$PATH" sh "$HERE/../wasm/compare.sh" --browser safari golem.wasm
cp "$WORK/out" "$CB/browser.txt"
expect "compare.sh --browser: runs every input" 0
if cb_form "$CB/browser.txt"; then ok; else ng "compare.sh --browser: the list has the form of that of node:wasi (docs/adr/0234 I5)"; fi
if grep -qxF "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb  kanikosen/pdf" "$CB/browser.txt"; then ok; else ng "compare.sh --browser: the SHA-256 that the page gave, of the browser asked"; fi
if grep -qxF -- "-  missing-font/pdf" "$CB/browser.txt" && grep -qxF "exit 1  missing-font" "$CB/browser.txt"; then ok; else ng "compare.sh --browser: no PDF and the exit code of a build with an error"; fi
# an input that does not end is stopped past COMPARE_TIMEOUT, its exit
# `exit timeout`, the host and its children with it, and the inputs after
# it still run (docs/adr/0247 section 7)
cat >"$CB/deno-hangs" <<'FAKE'
#!/bin/sh
case "$7" in
  */int-width-png-chunk) sleep 300 ;;
esac
printf '%%PDF %s\n' "${7##*/}" >"$8"
printf '[]\n' >&2
FAKE
chmod +x "$CB/deno-hangs"
s0=$(date +%s)
run env DENO="$CB/deno-hangs" COMPARE_TIMEOUT=2 sh "$HERE/../wasm/compare.sh" --deno golem.wasm
s1=$(date +%s)
cp "$WORK/out" "$CB/hangs.txt"
expect "compare.sh: an input past COMPARE_TIMEOUT does not fail the list (I1)" 0
if grep -qxF "exit timeout  int-width-png-chunk" "$CB/hangs.txt" && grep -qxF "exit 0  int-width-printing" "$CB/hangs.txt"; then ok; else ng "compare.sh: exit timeout for the input stopped, and the next input runs (I1)"; fi
if grep -qF "int-width-png-chunk: stopped after 2 s" "$WORK/err"; then ok; else ng "compare.sh: says which input it stopped (I1)"; fi
if [ $((s1 - s0)) -lt 60 ]; then ok; else ng "compare.sh: the input is stopped near COMPARE_TIMEOUT, not after the sleep of the host (I1)"; fi
if pgrep -f "sleep 300" >/dev/null 2>&1; then ng "compare.sh: the children of the host stopped are stopped too (I1)"; else ok; fi
# browser.yml gives its jobs that compare a COMPARE_TIMEOUT of fewer seconds
# than their timeout-minutes, so that an input that does not end is in the
# list as `exit timeout` before the job is cancelled (docs/adr/0247 section 7)
BROWSER_YML=$HERE/../../.github/workflows/browser.yml
for j in chromium safari; do
  ct=$(job_of "$BROWSER_YML" "$j" | sed -n 's/^      COMPARE_TIMEOUT: *//p')
  tm=$(job_of "$BROWSER_YML" "$j" | sed -n 's/^    timeout-minutes: *//p')
  if [ -n "$ct" ] && [ -n "$tm" ] && [ "$ct" -lt $((tm * 60)) ]; then ok; else ng "browser.yml: the $j job sets COMPARE_TIMEOUT below its timeout-minutes (docs/adr/0247 I1)"; fi
done
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
if cb_form "$CW/list.txt"; then ok; else ng "compare.sh --wasmtime: the list has the form of that of node:wasi (docs/adr/0234 I5, docs/adr/0238 I2)"; fi
if [ "$(cat "$CW/calls")" = "compile golem.wasm" ]; then ok; else ng "compare.sh --wasmtime: golem.wasm is compiled once"; fi
if grep -qxF "$(printf '0001' | cb_sha)  kanikosen/pdf" "$CW/list.txt" && grep -qxF "$(printf 'ffff' | cb_sha)  broken-cmap/pdf" "$CW/list.txt"; then ok; else ng "compare.sh: broken-cmap is kanikosen with FF FF at 30205 of Noto Serif JP (docs/adr/0238 I2, I3)"; fi
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

# ---------------------------------------------------------------- wasm/tasty-results.sh, run-suite.sh, check-skips.sh
# (docs/adr/0293 sections 4 and 5): the results of a tasty log; a suite
# against the list of the tests known to fail on wasm32, with a fake
# suite; the SKIPs of wasm32 against the native ones

WT=$WORK/wasm-tests
mkdir -p "$WT"
cat >"$WT/tasty.log" <<'LOG'
suite
  group one
    a test:                OK (0.01s)
    with: a colon:         FAIL (0.02s)
      test/Main.hs:10:
      expected: 1
       but got: 2
      Use -p '/with: a colon/' to rerun this test only.
    nested
      deep:                SKIP
        qpdf is not installed; GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes this a failure
  last:                    OK

1 out of 4 tests failed (0.03s)
2 tests skipped: qpdf is not installed (GOLEM_REQUIRE_EXTERNAL_TOOLS=1 makes them failures)
LOG
run sh "$HERE/../wasm/tasty-results.sh" "$WT/tasty.log"
expect "tasty-results: each test, its result and its full name, the description of a failure left out" 0 "OK	suite.group one.a test
FAIL	suite.group one.with: a colon
SKIP	suite.group one.nested.deep
OK	suite.last"
# the fake suite: g.a passes, g.b is a SKIP, g.c fails (passes with
# FAKE_C=OK); -p with $0 == "NAME" runs NAME alone, -p !(...) leaves the
# names in it out
cat >"$WT/fake.sh" <<'FAKE'
shift 2
[ "$1" = --color ] && [ "$2" = never ] || exit 9
shift 2
pattern=
if [ "${1:-}" = -p ]; then pattern=$2; fi
names=$(printf '%s' "$pattern" | grep -o '"[^"]*"' | tr -d '"')
echo g
code=0
for t in a b c; do
  case "$pattern" in
    "!("*) if printf '%s\n' "$names" | grep -qx "g.$t"; then continue; fi ;;
    "") ;;
    *) printf '%s\n' "$names" | grep -qx "g.$t" || continue ;;
  esac
  case $t in
    a) echo "  a: OK" ;;
    b) echo "  b: SKIP" ;;
    c) if [ "${FAKE_C:-FAIL}" = OK ]; then echo "  c: OK"; else echo "  c: FAIL"; code=1; fi ;;
  esac
done
exit $code
FAKE
printf 'suite\ttest\treason\tclass\n' >"$WT/none.tsv"
printf 'suite\ttest\treason\tclass\nfake-test\tg.c\tthe width of Int\tproduct\nother-test\tg.a\tanother suite\ttest\n' >"$WT/listed.tsv"
printf 'suite\ttest\treason\tclass\nfake-test\tg.c\tthe width of Int\tproduct\nfake-test\tg.zz\tno such test\ttest\n' >"$WT/stale.tsv"
run env RUN="sh $WT/fake.sh" FAILURES="$WT/listed.tsv" sh "$HERE/../wasm/run-suite.sh" golem-fake:test:fake-test fake.wasm "$WT/out"
if [ "$CODE" = 0 ] && [ "$(cut -f1,3- "$WORK/out")" = "fake-test	0	1	0	1" ] && [ "$(cat "$WT/out/fake-test.skipped")" = g.b ]; then ok; else
  ng "A2 A3 run-suite: the listed test left out passes the others, and fails alone"
fi
run env RUN="sh $WT/fake.sh" FAILURES="$WT/none.tsv" sh "$HERE/../wasm/run-suite.sh" golem-fake:test:fake-test fake.wasm "$WT/out"
if [ "$CODE" = 1 ] && grep -qx 'A2 fake-test: failed: g.c' "$WORK/err"; then ok; else ng "A2 run-suite: a test that fails and is not listed fails the suite"; fi
run env RUN="sh $WT/fake.sh" FAILURES="$WT/listed.tsv" FAKE_C=OK sh "$HERE/../wasm/run-suite.sh" golem-fake:test:fake-test fake.wasm "$WT/out"
if [ "$CODE" = 1 ] && grep -qx 'A3 fake-test: listed, but passes or is not a test of the suite: g.c' "$WORK/err"; then ok; else ng "A3 run-suite: a listed test that passes fails the suite"; fi
run env RUN="sh $WT/fake.sh" FAILURES="$WT/stale.tsv" sh "$HERE/../wasm/run-suite.sh" golem-fake:test:fake-test fake.wasm "$WT/out"
if [ "$CODE" = 1 ] && grep -qx 'A3 fake-test: listed, but passes or is not a test of the suite: g.zz' "$WORK/err" && ! grep -q 'g\.c' "$WORK/err"; then ok; else ng "A3 run-suite: a listed test the suite does not have fails the suite"; fi
run sh "$HERE/../wasm/run-suite.sh" golem-fake fake.wasm "$WT/out"
expect "run-suite: a target without :test: is a usage error" 2
# check-skips.sh
mkdir -p "$WT/native" "$WT/wasm"
printf 'OK\tg.a\nSKIP\tg.b\nOK\tg.c\n' >"$WT/native/fake-test.results"
printf 'OK\tg.a\nSKIP\tg.b\n' >"$WT/wasm/fake-test.results"
printf 'suite\ttest\treason\tclass\nfake-test\tg.c\tthe width of Int\tproduct\n' >"$WT/one.tsv"
run env FAILURES="$WT/one.tsv" sh "$HERE/../wasm/check-skips.sh" "$WT/native" "$WT/wasm"
expect "A3 A4 check-skips: the SKIPs of wasm32 are native SKIPs, and the listed test passes natively" 0
printf 'OK\tg.a\nSKIP\tg.b\nSKIP\tg.c\n' >"$WT/wasm/fake-test.results"
run env FAILURES="$WT/one.tsv" sh "$HERE/../wasm/check-skips.sh" "$WT/native" "$WT/wasm"
if [ "$CODE" = 1 ] && grep -qx 'A4 fake-test: a SKIP on wasm32, not natively: g.c' "$WORK/err"; then ok; else ng "A4 check-skips: a SKIP on wasm32 that is not a native SKIP fails"; fi
printf 'OK\tg.a\nSKIP\tg.b\n' >"$WT/wasm/fake-test.results"
printf 'OK\tg.a\nSKIP\tg.b\nFAIL\tg.c\n' >"$WT/native/fake-test.results"
run env FAILURES="$WT/one.tsv" sh "$HERE/../wasm/check-skips.sh" "$WT/native" "$WT/wasm"
if [ "$CODE" = 1 ] && grep -qx 'A3 fake-test: listed, but does not pass natively: g.c' "$WORK/err"; then ok; else ng "A3 check-skips: a listed test that fails natively fails"; fi
# a listed test of needsTool is a SKIP natively without the tool; a name
# with a backslash is read as it is
printf 'OK\tg.a\nSKIP\tg.b\nOK\tg.\\u{d800}\n' >"$WT/native/fake-test.results"
printf 'suite\ttest\treason\tclass\nfake-test\tg.b\tno PATH\ttest\nfake-test\tg.\\u{d800}\tthe width of Int\tproduct\n' >"$WT/two.tsv"
run env FAILURES="$WT/two.tsv" sh "$HERE/../wasm/check-skips.sh" "$WT/native" "$WT/wasm"
expect "A3 check-skips: a listed test that is a native SKIP, and a name with a backslash, pass natively" 0
# the list itself: a header and four fields, a known suite, product or test
WTF=$HERE/../wasm/test-failures.tsv
if [ "$(head -n 1 "$WTF")" = "$(printf 'suite\ttest\treason\tclass')" ] &&
  awk -F '\t' 'NR > 1 && (NF != 4 || $4 !~ /^(product|test)$/ || $2 == "" || $3 == "") { bad = 1 } END { exit bad }' "$WTF"; then ok; else
  ng "test-failures.tsv: a header, then a suite, a test, a reason and product or test on each line"
fi
sh "$HERE/test-suites.sh" wasm | sed 's/.*://' | LC_ALL=C sort >"$WORK/wasm-suites"
if [ -z "$(awk -F '\t' 'NR > 1 { print $1 }' "$WTF" | LC_ALL=C sort -u | LC_ALL=C comm -23 - "$WORK/wasm-suites")" ]; then ok; else
  ng "test-failures.tsv: every suite is one of test-suites.sh wasm"
fi

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

# (docs/adr/0289 H4): the engine is made with memory64 off, so that the
# linear memory stays within 4 GiB whatever the default of wasmtime
if grep -qF 'wasmtime_config_wasm_memory64_set(config, false)' "$HERE/../wasm/run-wasmtime.c"; then ok; else ng "H4 run-wasmtime.c: engine() turns memory64 off"; fi

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
    mkdir -p "$FC/root/scripts/browser" "$FC/root/scripts/wasm" "$FC/root/scripts/ci"
    cp "$HERE/../$f" "$FC/root/scripts/$f"
    cp "$HERE/fetch-url.sh" "$FC/root/scripts/ci/"
    run env PATH="$FC/bin:$PATH" sh "$FC/root/scripts/$f"
    expect "$n: a zip of another SHA-256 fails" 1
    if grep -qF 'SHA-256 mismatch' "$WORK/err" && [ -z "$(find "$FC/root/third_party" -type f 2>/dev/null)" ]; then ok; else ng "$n: a zip of another SHA-256 is not unpacked nor kept"; fi
  else
    run sh "$HERE/../$f"
    expect "$n: another platform than x86-64 Linux fails" 1
    skip 2 "$n: the SHA-256 is checked on x86-64 Linux only"
  fi
done
# the zip is kept in third_party/downloads, and one there of the SHA-256 is
# unpacked without curl (docs/adr/0243): a copy of each script pins the
# SHA-256 of a small zip of the layout of the release
if [ "$(uname -s)-$(uname -m)" = Linux-x86_64 ] && command -v zip >/dev/null 2>&1; then
  mkdir -p "$FC/src/chromium/chrome-headless-shell-linux64" "$FC/src/deno"
  printf '#!/bin/sh\n' >"$FC/src/chromium/chrome-headless-shell-linux64/chrome-headless-shell"
  DENO_VERSION=$(sed -n 's/^VERSION=//p' "$HERE/../wasm/fetch-deno.sh")
  printf '#!/bin/sh\necho "deno %s (stable, release, x86_64-unknown-linux-gnu)"\n' "$DENO_VERSION" >"$FC/src/deno/deno"
  (cd "$FC/src/chromium" && zip -qr "$FC/chrome-headless-shell-linux64.zip" chrome-headless-shell-linux64)
  (cd "$FC/src/deno" && zip -q "$FC/deno-x86_64-unknown-linux-gnu.zip" deno)
  cat >"$FC/bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$FC_LOG"
url=
for a in "$@"; do url=$a; done
while [ $# -gt 0 ]; do
  case "$1" in -o) cp "$FC_ZIPS/${url##*/}" "$2" || exit 22; shift ;; esac
  shift
done
FAKE
  for fz in "browser/fetch-chromium.sh chrome-headless-shell-linux64.zip third_party/chromium chrome-headless-shell-linux64/chrome-headless-shell" \
    "wasm/fetch-deno.sh deno-x86_64-unknown-linux-gnu.zip third_party/deno deno"; do
    set -- $fz
    f=$1 z=$2 dest=$3 bin=$3/$4 n=${1##*/}
    rm -rf "$FC/root"
    mkdir -p "$FC/root/scripts/browser" "$FC/root/scripts/wasm" "$FC/root/scripts/ci"
    cp "$HERE/fetch-url.sh" "$FC/root/scripts/ci/"
    sed "s/^SHA256=.*/SHA256=$(fu_sha "$FC/$z")/" "$HERE/../$f" >"$FC/root/scripts/$f"
    : >"$FC/curl.log"
    run env PATH="$FC/bin:$PATH" FC_LOG="$FC/curl.log" FC_ZIPS="$FC" sh "$FC/root/scripts/$f"
    if [ "$CODE" = 0 ] && [ -f "$FC/root/$bin" ] && cmp -s "$FC/$z" "$FC/root/third_party/downloads/$z"; then ok; else ng "$n: the zip is unpacked and kept in third_party/downloads (docs/adr/0243)"; fi
    rm -rf "$FC/root/$dest"
    : >"$FC/curl.log"
    run env PATH="$FC/bin:$PATH" FC_LOG="$FC/curl.log" FC_ZIPS="$FC" sh "$FC/root/scripts/$f"
    if [ "$CODE" = 0 ] && [ -f "$FC/root/$bin" ] && [ ! -s "$FC/curl.log" ]; then ok; else ng "$n: a zip of the SHA-256 in third_party/downloads is unpacked without curl (docs/adr/0243)"; fi
    rm -rf "$FC/root/$dest"
    printf 'other\n' >"$FC/root/third_party/downloads/$z"
    run env PATH="$FC/bin:$PATH" FC_LOG="$FC/curl.log" FC_ZIPS="$FC" sh "$FC/root/scripts/$f"
    if [ "$CODE" = 0 ] && [ -s "$FC/curl.log" ] && cmp -s "$FC/$z" "$FC/root/third_party/downloads/$z"; then ok; else ng "$n: a zip of another SHA-256 in third_party/downloads is fetched again (docs/adr/0243)"; fi
  done
else
  skip 6 "fetch-chromium, fetch-deno: the archives are of x86-64 Linux, and zip is needed"
fi

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

# ---------------------------------------------------------------- actions-pins.sh
# every action of the workflows is pinned by the SHA of a commit with the tag
# of its version as a comment (docs/adr/0296); git and gh are stubs that
# answer from scripts/ci/testdata/actions-pins/ and the files below

AP=$WORK/actions-pins
AP_DATA=$HERE/testdata/actions-pins
mkdir -p "$AP/bin" "$AP/tags" "$AP/gh"
: >"$WORK/in"
cp "$AP_DATA"/*.tags "$AP/tags/"
# git ls-remote --tags https://github.com/OWNER/REPO.git: $AP/tags/OWNER_REPO.tags
cat >"$AP/bin/git" <<'STUB'
#!/bin/sh
[ "$1" = ls-remote ] || exit 2
r=${3#https://github.com/}
r=${r%.git}
f=$AP_TAGS/$(printf '%s' "$r" | tr / _).tags
[ -f "$f" ] || { echo "fatal: repository not found" >&2; exit 128; }
cat "$f"
STUB
# gh api -H ... repos/OWNER/REPO/contents/PATH?ref=SHA: the file of that
# argument with /, ? and = turned into _, or a failure (not found)
cat >"$AP/bin/gh" <<'STUB'
#!/bin/sh
for a; do last=$a; done
f=$AP_GH/$(printf '%s' "$last" | tr '/?=' '___')
[ -f "$f" ] || { echo "HTTP 404" >&2; exit 1; }
cat "$f"
STUB
chmod +x "$AP/bin/git" "$AP/bin/gh"
ap() { env PATH="$AP/bin:$PATH" AP_TAGS="$AP/tags" AP_GH="$AP/gh" sh "$HERE/actions-pins.sh" "$@"; }
# action_yml REPO PATH SHA USING [FILE]: the action.yml of the stub
action_yml() {
  printf 'name: x\nruns:\n  using: %s\n  main: index.js\n' "$4" >"$AP/gh/$(printf 'repos/%s/contents/%s%s?ref=%s' "$1" "${2:+$2/}" "${5:-action.yml}" "$3" | tr '/?=' '___')"
}
CO=3d3c42e5aac5ba805825da76410c181273ba90b1     # actions/checkout v7, v7.0.1 (lightweight)
CO0=9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0    # actions/checkout v7.0.0
HS=0f8e8c99d88aeb3fbfd523f1ef2c6f762d10d64d     # haskell-actions/setup v2.12.1 (annotated)
HSTAG=0f7370ccbc65f22514ec3e094f6601b8d61fbbf7  # the tag object of v2.12.1
FM=1b9df64b784203126500372730b9725c97e4040b     # haskell-actions/run-fourmolu v13 (only majors)
action_yml actions/checkout "" "$CO" node24
action_yml haskell-actions/setup "" "$HS" node24
action_yml haskell-actions/run-fourmolu "" "$FM" node24
# ap_dir NAME: a new directory of workflows, $AP/NAME
ap_dir() { rm -rf "${AP:?}/$1"; mkdir -p "$AP/$1"; }

# check: the form of every uses: line (I1), and the lines that are not (I2)
ap_dir good
cat >"$AP/good/a.yml" <<YML
jobs:
  a:
    steps:
      - uses: actions/checkout@$CO # v7.0.1
      - name: setup
        uses: haskell-actions/setup@$HS # v2.12.1
      - uses: haskell-actions/run-fourmolu@$FM # v13
      - uses: actions/cache/restore@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1
      # uses: a comment is not a uses: line
  b:
    uses: ./.github/workflows/ci.yml
YML
cat >"$AP/good/b.yml" <<YML
      - uses: actions/cache/save@55cc8345863c7cc4c66a329aec7e433d2d1c52a9 # v6.1
YML
printf 'not a workflow: uses: x\n' >"$AP/good/c.yaml"
run ap check "$AP/good"
expect "actions-pins check: the pinned forms, ./ and the paths of a repository pass, 6 lines (I1, I3, I4)" 0 "6 uses: lines checked"
for bad in "actions/checkout@v7" "actions/checkout@main" "actions/checkout@3d3c42e" \
  "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b # v7.0.1" \
  "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1a # v7.0.1" \
  "actions/checkout@3D3C42E5AAC5BA805825DA76410C181273BA90B1 # v7.0.1" \
  "actions/checkout@$CO" "actions/checkout@$CO # v7.0.1.2" "actions/checkout@$CO # 7.0.1" \
  "actions/checkout@$CO # v7.0.1 " "actions/checkout@$CO #v7.0.1" "actions/checkout@$CO # v7.0.1 x" \
  "\"actions/checkout@$CO\" # v7.0.1" "docker://alpine:3" "checkout@$CO # v7.0.1"; do
  ap_dir bad
  printf '      - uses: haskell-actions/setup@%s # v2.12.1\n      - uses: %s\n' "$HS" "$bad" >"$AP/bad/w.yml"
  run ap check "$AP/bad"
  if [ "$CODE" = 1 ] && grep -qF "$AP/bad/w.yml:2: " "$WORK/out" && ! grep -qF "w.yml:1:" "$WORK/out" &&
    grep -qxF "2 uses: lines checked" "$WORK/out"; then ok; else ng "actions-pins check: '$bad' fails at FILE:LINE (I2)"; fi
done
# the forms of the line: name: above, a uses: under a step
ap_dir bad
printf '      - name: x\n        uses: actions/checkout@v7\n' >"$AP/bad/w.yml"
run ap check "$AP/bad"
if [ "$CODE" = 1 ] && grep -qF "$AP/bad/w.yml:2: " "$WORK/out"; then ok; else ng "actions-pins check: a uses: under name: is checked (I2)"; fi

# check: the same repository is pinned alike in every file (I3)
for pair in "$CO0 # v7.0.0" "$CO # v7"; do
  ap_dir two
  printf '      - uses: actions/checkout@%s # v7.0.1\n' "$CO" >"$AP/two/a.yml"
  printf 'x: 1\n      - uses: actions/checkout/sub@%s\n' "$pair" >"$AP/two/b.yml"
  run ap check "$AP/two"
  if [ "$CODE" = 1 ] && grep -qF "$AP/two/b.yml:2: actions/checkout is pinned" "$WORK/out"; then ok; else
    ng "actions-pins check: actions/checkout at '$pair' and at $CO # v7.0.1 fails (I3)"
  fi
done

# check: the number of lines, and 0 lines fails (I4)
ap_dir none
printf 'on: push\njobs:\n  a:\n    steps:\n      - run: true\n' >"$AP/none/a.yml"
run ap check "$AP/none"
expect "actions-pins check: no uses: line fails (I4)" 1 "0 uses: lines checked"
ap_dir one
printf '      - uses: ./.github/workflows/ci.yml\n' >"$AP/one/a.yml"
run ap check "$AP/one"
expect "actions-pins check: one uses: line (I4)" 0 "1 uses: lines checked"
run ap check "$AP/nonexistent"
expect "actions-pins check: no directory is an error" 2

# verify: the tag of the comment is the pinned commit, peeled (I5)
ap_dir v
printf '      - uses: actions/checkout@%s # v7.0.1\n      - uses: haskell-actions/setup@%s # v2.12.1\n      - uses: haskell-actions/run-fourmolu@%s # v13\n      - uses: ./.github/workflows/ci.yml\n' "$CO" "$HS" "$FM" >"$AP/v/a.yml"
run ap verify "$AP/v"
expect "actions-pins verify: a lightweight tag, an annotated tag peeled, a major tag (I5)" 0 "4 uses: lines checked"
for case in "haskell-actions/setup@$HSTAG # v2.12.1:the tag object of an annotated tag" \
  "actions/checkout@$CO # v7.0.9:a tag that is not upstream" \
  "actions/checkout@$CO # v7.0.0:a tag of another commit"; do
  ap_dir v
  printf '      - uses: %s\n' "${case%%:*}" >"$AP/v/a.yml"
  run ap verify "$AP/v"
  if [ "$CODE" = 1 ] && [ "$(grep -vc 'uses: lines checked' "$WORK/out")" = 1 ]; then ok; else ng "actions-pins verify: ${case#*:} fails (I5)"; fi
done
# the tag was moved to another commit
cp "$AP/tags/actions_checkout.tags" "$AP/checkout.tags"
sed "s|^$CO	refs/tags/v7.0.1\$|$CO0	refs/tags/v7.0.1|" "$AP/checkout.tags" >"$AP/tags/actions_checkout.tags"
ap_dir v
printf '      - uses: actions/checkout@%s # v7.0.1\n' "$CO" >"$AP/v/a.yml"
run ap verify "$AP/v"
if [ "$CODE" = 1 ] && grep -qF "actions/checkout: v7.0.1 is $CO0 upstream" "$WORK/out"; then ok; else ng "actions-pins verify: a moved tag fails (I5)"; fi
cp "$AP/checkout.tags" "$AP/tags/actions_checkout.tags"
# a repository that is not upstream is an error
ap_dir v
printf '      - uses: nobody/nothing@%s # v1\n' "$CO" >"$AP/v/a.yml"
run ap verify "$AP/v"
expect "actions-pins verify: git ls-remote fails, an error" 2

# latest: the pinned SHA is the commit of the greatest version, and the
# action runs on node 24 or later or is composite (I6)
ap_dir l
printf '      - uses: actions/checkout@%s # v7.0.1\n      - uses: haskell-actions/setup@%s # v2.12.1\n      - uses: haskell-actions/run-fourmolu@%s # v13\n' "$CO" "$HS" "$FM" >"$AP/l/a.yml"
run ap latest "$AP/l"
expect "actions-pins latest: the newest versions, v13 above v9, only majors (I6)" 0 "3 uses: lines checked"
# latest_tags NAME LINE: latest with LINE added to the tags of actions/checkout
latest_tags() {
  { cat "$AP/checkout.tags"; printf '%s\n' "$2"; } >"$AP/tags/actions_checkout.tags"
  run ap latest "$AP/l"
  cp "$AP/checkout.tags" "$AP/tags/actions_checkout.tags"
}
latest_tags patch "$CO0	refs/tags/v7.0.2"
if [ "$CODE" = 1 ] && grep -qF "actions/checkout: the newest is v7.0.2 ($CO0)" "$WORK/out"; then ok; else ng "actions-pins latest: a newer patch fails with its name (I6)"; fi
latest_tags major "$CO0	refs/tags/v8"
if [ "$CODE" = 1 ] && grep -qF "actions/checkout: the newest is v8 " "$WORK/out"; then ok; else ng "actions-pins latest: a newer major fails (I6)"; fi
latest_tags beta "$CO0	refs/tags/v8.0.0-beta.1"
expect "actions-pins latest: a version with a suffix is not newer (I6)" 0 "3 uses: lines checked"
ap_dir l0
printf '      - uses: actions/checkout@%s # v7.0.0\n' "$CO0" >"$AP/l0/a.yml"
action_yml actions/checkout "" "$CO0" node24
run ap latest "$AP/l0"
if [ "$CODE" = 1 ] && grep -qF "the newest is v7.0.1 ($CO), pinned v7.0.0" "$WORK/out"; then ok; else ng "actions-pins latest: an older version fails (I6)"; fi
for u in node26:0 node20:1 composite:0 docker:1 "'node24':0"; do
  action_yml actions/checkout "" "$CO" "${u%%:*}"
  run ap latest "$AP/l"
  expect "actions-pins latest: runs.using ${u%%:*} (I6)" "${u#*:}"
done
# CRLF, as actions/checkout writes its action.yml
printf 'name: x\r\nruns:\r\n  using: node24\r\n  main: index.js\r\n' >"$AP/gh/repos_actions_checkout_contents_action.yml_ref_$CO"
run ap latest "$AP/l"
expect "actions-pins latest: an action.yml with CRLF (I6)" 0 "3 uses: lines checked"
rm -f "$AP/gh/repos_actions_checkout_contents_action.yml_ref_$CO"
action_yml actions/checkout "" "$CO" node24 action.yaml
run ap latest "$AP/l"
expect "actions-pins latest: only action.yaml (I6)" 0 "3 uses: lines checked"
rm -f "$AP/gh/repos_actions_checkout_contents_action.yaml_ref_$CO"
run ap latest "$AP/l"
if [ "$CODE" = 1 ] && grep -qF "runs.using is missing" "$WORK/out"; then ok; else ng "actions-pins latest: no action.yml fails (I6)"; fi
action_yml actions/checkout "" "$CO" node24
# the action of a path is read at its path
ap_dir lp
printf '      - uses: actions/checkout/sub@%s # v7.0.1\n' "$CO" >"$AP/lp/a.yml"
run ap latest "$AP/lp"
if [ "$CODE" = 1 ] && grep -qF "actions/checkout/sub@$CO: runs.using is missing" "$WORK/out"; then ok; else ng "actions-pins latest: the action.yml of a path (I6)"; fi
action_yml actions/checkout sub "$CO" composite
run ap latest "$AP/lp"
expect "actions-pins latest: the action.yml of a path is composite (I6)" 0 "1 uses: lines checked"

# update: rewrites to the newest versions; the result passes check, verify
# and latest, and a second update changes nothing (I7)
ap_dir u
cat >"$AP/u/a.yml" <<YML
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - name: setup
        uses: haskell-actions/setup@v2
      - uses: ./.github/workflows/ci.yml
YML
cat >"$AP/u/b.yml" <<YML
      - uses: haskell-actions/setup@v2
      - uses: haskell-actions/run-fourmolu@v13
      - uses: actions/checkout@$CO0 # v7.0.0
YML
run ap update "$AP/u"
if [ "$CODE" = 0 ] && [ "$(sort "$WORK/out")" = "actions/checkout: v7 -> v7.0.1
haskell-actions/setup: v2 -> v2.12.1" ]; then ok; else ng "actions-pins update: says what it raised (I7)"; fi
if [ "$(cat "$AP/u/a.yml")" = "      - uses: actions/checkout@$CO # v7.0.1
        with:
          persist-credentials: false
      - name: setup
        uses: haskell-actions/setup@$HS # v2.12.1
      - uses: ./.github/workflows/ci.yml" ] && [ "$(cat "$AP/u/b.yml")" = "      - uses: haskell-actions/setup@$HS # v2.12.1
      - uses: haskell-actions/run-fourmolu@$FM # v13
      - uses: actions/checkout@$CO # v7.0.1" ]; then ok; else ng "actions-pins update: the rewritten workflows (I7)"; fi
run ap check "$AP/u"
expect "actions-pins update: the result passes check (I7)" 0 "6 uses: lines checked"
run ap verify "$AP/u"
expect "actions-pins update: the result passes verify (I7)" 0 "6 uses: lines checked"
run ap latest "$AP/u"
expect "actions-pins update: the result passes latest (I7)" 0 "6 uses: lines checked"
cp -R "$AP/u" "$AP/u1"
run ap update "$AP/u"
if [ "$CODE" = 0 ] && [ ! -s "$WORK/out" ] && diff -r "$AP/u1" "$AP/u" >/dev/null; then ok; else ng "actions-pins update: a second update changes nothing (I7)"; fi
# the newest version runs on node20: nothing is written
ap_dir u
printf '      - uses: actions/checkout@v7\n      - uses: haskell-actions/setup@v2\n' >"$AP/u/a.yml"
cp "$AP/u/a.yml" "$AP/u.orig"
action_yml actions/checkout "" "$CO" node20
run ap update "$AP/u"
if [ "$CODE" = 1 ] && grep -qF "actions/checkout@$CO: runs.using is node20" "$WORK/out" && cmp -s "$AP/u.orig" "$AP/u/a.yml"; then ok; else
  ng "actions-pins update: node20 at the newest version fails and writes nothing (I7)"
fi
action_yml actions/checkout "" "$CO" node24

# the workflows of the repository pass check, and the daily job checks
# them against upstream with contents: read only (docs/adr/0296)
run sh "$HERE/actions-pins.sh" check
if [ "$CODE" = 0 ] && grep -Eq '^[1-9][0-9]* uses: lines checked$' "$WORK/out"; then ok; else ng "actions-pins check: the workflows of the repository (I1, I3)"; fi
if [ "$(perms_of "$ADV_YML" actions)" = "contents: read" ]; then ok; else ng "advisories.yml: the actions job has contents: read only"; fi
if job_of "$ADV_YML" actions | grep -qF 'sh scripts/ci/actions-pins.sh verify' &&
  job_of "$ADV_YML" actions | grep -qF 'sh scripts/ci/actions-pins.sh latest' &&
  job_of "$ADV_YML" actions | grep -qF 'GH_TOKEN: ${{ github.token }}' &&
  job_of "$ADV_YML" actions | grep -qxF '    timeout-minutes: 10'; then ok; else ng "advisories.yml: the actions job runs verify and latest with GH_TOKEN in 10 minutes"; fi
if job_lines scripts-linux | grep -qF 'run: sh scripts/ci/actions-pins.sh check'; then ok; else ng "ci.yml: scripts-linux runs actions-pins.sh check"; fi

# ----------------------------------------------------------------
printf '%s tests, %s failures, %s skipped\n' "$COUNT" "$FAILURES" "$SKIPPED"
[ "$FAILURES" -eq 0 ]
