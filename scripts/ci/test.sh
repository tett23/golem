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
  name=$1 code=$2
  shift 2
  abi_git add -A
  abi_git commit -q --allow-empty -m change
  : >"$WORK/in"
  run env GOLEM_ROOT="$AV" sh "$HERE/abi-version.sh"
  expect "abi-version: $name" "$code"
  for w in "$@"; do
    if grep -qF -- "$w" "$WORK/err"; then ok; else ng "$name: \"$w\" on stderr"; fi
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

# x86-64 builds three times: one runner for the tests, one for the outputs,
# one for the environment check; aarch64 does the tests and the outputs
# (docs/adr/0045, docs/adr/0097)
matrix_rows() { # the runner, part, tests, outputs and env of each row of the matrix
  awk '/^        include:/ { on = 1; next }
    on && /^    [a-z]/ { on = 0 }
    on && /- runner:/ { r = $3 } on && /part:/ { p = $2 } on && /tests:/ { t = $2 }
    on && /outputs:/ { o = $2 } on && /env:/ { print r, p, t, o, $2 }' "$1"
}
if [ "$(matrix_rows "$CI_YML")" = "ubuntu-24.04 tests true false false
ubuntu-24.04 outputs false true false
ubuntu-24.04 env false false true
ubuntu-24.04-arm all true true false" ]; then ok; else ng "ci.yml: the matrix of build has the tests, the outputs and the environment check of x86-64 and all of aarch64"; fi
# the step after a line that matches $1 has the condition $2
step_if() { awk -v s="$1" -v c="$2" 'index($0, s) { getline; if (index($0, c)) found = 1 } END { exit !found }' "$CI_YML"; }
if step_if "- run: cabal test all" "if: matrix.tests"; then ok; else ng "ci.yml: the tests run on the runners of the tests"; fi
if step_if "name: Outputs for the determinism check" "if: matrix.outputs"; then ok; else ng "ci.yml: the outputs are made on the runners of the outputs"; fi
# the step that starts at a line that matches $1 has a line that matches $2
step_has() {
  awk -v s="$1" -v c="$2" 'index($0, s) { on = 1; print; next } on && /^      - / { on = 0 } on' "$CI_YML" | grep -qF -- "$2"
}
# the lines of the job $1 of ci.yml
job_lines() { awk -v j="  $1:" '$0 == j { on = 1; next } on && /^  [a-z]/ { on = 0 } on' "$CI_YML"; }
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
if step_has "- run: cabal test all" 'GOLEM_PD_BOOKS: "1"'; then ok; else ng "ci.yml: cabal test all has GOLEM_PD_BOOKS"; fi
# a missing golden file fails the tests in CI instead of being created
# (tasty-golden's --no-create, given by the environment: a suite without
# tasty-golden would reject the flag on its command line)
if step_has "- run: cabal test all" 'TASTY_NO_CREATE: "true"'; then ok; else ng "ci.yml: cabal test all has TASTY_NO_CREATE"; fi
# apt installs qpdf on the runners of the tests only; epubcheck comes from
# its release, cached by its version and SHA-256, on the x86-64 runner of
# the outputs (docs/adr/0062)
if step_if "name: qpdf in the background" "if: matrix.tests" && step_has "name: qpdf in the background" "apt-install.sh qpdf"; then ok; else ng "ci.yml: apt installs qpdf on the runners of the tests"; fi
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
if step_if "name: qpdf is installed" "if: matrix.tests" && step_has "name: qpdf is installed" "bg.sh wait apt"; then ok; else ng "ci.yml: the runners of the tests wait for qpdf"; fi
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
for t in scripts/ci/test.sh scripts/manual/test.sh scripts/env-determinism/test.sh scripts/release/test.sh scripts/test.sh scripts/visual/test.sh; do
  if grep -qx "        run: sh $t" "$SM"; then ok; else ng "ci.yml: scripts-macos runs $t"; fi
done
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
DET_AT=$(grep -n 'name: Outputs for the determinism check' "$CI_YML" | cut -d: -f1)
VB_AT=$(grep -n 'name: The PDFs of the visual regression test' "$CI_YML" | cut -d: -f1)
if [ -n "$DET_AT" ] && [ -n "$VB_AT" ] && [ "$DET_AT" -lt "$VB_AT" ]; then ok; else ng "ci.yml: the PDFs of the visual regression test are built after determinism.sh"; fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?visual([],].*)?$'; then ok; else ng "ci.yml: ci needs visual"; fi
if job_lines ci | grep -Eq '^    needs: \[(.*[ ,])?scripts-macos([],].*)?$'; then ok; else ng "ci.yml: ci needs scripts-macos"; fi
if grep -qF "matrix.tests && steps.build.outcome == 'success' && steps.build.outputs.compiled == 'true' && github.event_name == 'pull_request'" "$CI_YML"; then ok; else ng "ci.yml: a pull request saves dist-newstyle when GHC compiled, from the runner of the tests"; fi

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
needs changes=success scripts-linux=success build=success determinism=success visual=success release-scripts=success scripts-macos=success format=success >"$WORK/in"
run gate
expect "gate: all succeeded" 0
needs changes=success scripts-linux=success build=skipped determinism=skipped visual=skipped release-scripts=skipped scripts-macos=skipped format=skipped >"$WORK/in"
run gate
expect "gate: docs only" 0
needs changes=success scripts-linux=success build=failure determinism=skipped visual=skipped release-scripts=success scripts-macos=success format=success >"$WORK/in"
run gate
expect "gate: a failed build" 1
if grep -q 'build' "$WORK/err" && grep -q 'failure' "$WORK/err"; then ok; else ng "gate: the failed job is named"; fi
needs changes=success scripts-linux=success build=success determinism=cancelled visual=cancelled release-scripts=success scripts-macos=success format=success >"$WORK/in"
run gate
expect "gate: a cancelled job" 1
needs changes=success scripts-linux=success build=success determinism=success visual=success release-scripts=success scripts-macos=success >"$WORK/in"
run gate
expect "gate: a missing job" 1
if grep -q 'format' "$WORK/err"; then ok; else ng "gate: the missing job is named"; fi
needs changes=success scripts-linux=success build=success determinism=success visual=failure release-scripts=success scripts-macos=success format=success >"$WORK/in"
run gate
expect "gate: a failed visual (docs/adr/0095)" 1
if grep -q 'visual' "$WORK/err"; then ok; else ng "gate: the failed visual is named"; fi
echo 'not json' >"$WORK/in"
run gate
expect "gate: not JSON" 1

# the jobs of ci.yml, but ci itself, are the jobs that gate.sh knows
ci_jobs() { # ci_jobs WORKFLOW: the names of its jobs
  awk '/^jobs:/ { on = 1; next } on && /^[^ #]/ { on = 0 } on && /^  [a-z][a-z0-9-]*:$/ { sub(/^  /, ""); sub(/:$/, ""); print }' "$1"
}
# names_match GATE: the names of the gate.sh at GATE are the jobs of ci.yml
names_match() {
  : >"$WORK/in"
  run sh "$1" --names
  [ "$CODE" = 0 ] && [ "$(sort "$WORK/out")" = "$(ci_jobs "$HERE/../../.github/workflows/ci.yml" | grep -vx ci | sort)" ]
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
if grep -qE ': *write' "$CI_YML"; then ng "ci.yml: no write permission"; else ok; fi
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
# GOLEM_MANUAL_ROOT with a LICENSE each, built without their fonts.
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
if grep -qE '^[0-9a-f]{64}  diagnostics/stderr$' "$WORK/out"; then ok; else ng "determinism: the stderr of diagnostics"; fi
if grep -qx 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  sample/stdout' "$WORK/out"; then ok; else ng "determinism: the empty stdout of sample"; fi
if grep -qE '^[0-9a-f]{64}  manual/build/out$' "$WORK/out"; then ok; else ng "determinism: the files of a manual"; fi
run determinism '{"diagnostics":[{"code":"G00001"}]}'
expect "determinism: another stderr" 0
if [ "$(grep '  diagnostics/stderr$' "$DET/first")" != "$(grep '  diagnostics/stderr$' "$WORK/out")" ]; then ok; else ng "determinism: a change of one character in stderr changes the list"; fi
if [ "$(grep -v '  diagnostics/stderr$' "$DET/first")" = "$(grep -v '  diagnostics/stderr$' "$WORK/out")" ]; then ok; else ng "determinism: the rest of the list stays"; fi

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
deps "no such file" 2 "$WORK/no-such-plan.json"
printf 'not json\n' >"$WORK/bad.json"
deps "not JSON" 2 "$WORK/bad.json"
printf '{"cabal-version":"3.16.1.0"}\n' >"$WORK/no-plan.json"
deps "no install-plan" 2 "$WORK/no-plan.json"
: >"$WORK/in"
run test_only_deps
expect "test-only-deps: no argument" 2

# ----------------------------------------------------------------
printf '%s tests, %s failures, %s skipped\n' "$COUNT" "$FAILURES" "$SKIPPED"
[ "$FAILURES" -eq 0 ]
