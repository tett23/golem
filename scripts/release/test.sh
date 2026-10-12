#!/bin/sh
# Tests of the release scripts (docs/adr/0004-binary-distribution-and-release.md).
# Each test builds its input (cabal files, a Git repository, plan.json) in a
# temporary directory. CI runs this in the release-scripts job.
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

# run CMD...: stdout to $WORK/out, stderr to $WORK/err, the exit code to $CODE
run() {
  CODE=0
  "$@" >"$WORK/out" 2>"$WORK/err" || CODE=$?
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
    return 0
  fi
  ok
}

# ---------------------------------------------------------------- check-version.sh

# mkroot VERSION PACKAGE-VERSION...: a root with VERSION and one cabal file per package
mkroot() {
  rm -rf "${WORK:?}/root"
  mkdir -p "$WORK/root"
  printf '%s\n' "$1" >"$WORK/root/VERSION"
  shift
  i=0
  for v in "$@"; do
    i=$((i + 1))
    mkdir -p "$WORK/root/modules/p$i"
    printf 'cabal-version:      3.0\nname:               p%s\nversion:            %s\n' "$i" "$v" >"$WORK/root/modules/p$i/p$i.cabal"
  done
}

check_version() { GOLEM_ROOT="$WORK/root" sh "$HERE/check-version.sh" "$@"; }

mkroot 0.1.0 0.1.0 0.1.0
run check_version
expect "check-version: 0.1.0" 0 "version=0.1.0"

mkroot 0.1.0-rc1 0.1.0 0.1.0
run check_version
expect "check-version: 0.1.0-rc1" 0 "version=0.1.0-rc1"

mkroot 0.1.0 0.1.0 0.1.1
run check_version
expect "check-version: one package differs" 1

for v in 0.1 v0.1.0 0.1.0-; do
  mkroot "$v" 0.1.0 0.1.0
  run check_version
  expect "check-version: VERSION $v" 1
done

mkroot 0.1.0 0.1.0 0.1.0
run check_version v0.1.0
expect "check-version: tag v0.1.0" 0 "version=0.1.0
prerelease=false"

mkroot 0.1.0-rc1 0.1.0 0.1.0
run check_version v0.1.0-rc1
expect "check-version: tag v0.1.0-rc1" 0 "version=0.1.0-rc1
prerelease=true"

mkroot 0.1.0-rc.1 0.1.0 0.1.0
run check_version v0.1.0-rc.1
expect "check-version: tag v0.1.0-rc.1" 0 "version=0.1.0-rc.1
prerelease=true"

mkroot 0.1.0 0.1.0 0.1.0
run check_version v0.1.0-rc1
expect "check-version: tag v0.1.0-rc1 for 0.1.0" 1
run check_version v0.1.1
expect "check-version: tag v0.1.1 for 0.1.0" 1
for t in v0.1 0.1.0 v0.1.0+build v0.1.0-; do
  run check_version "$t"
  expect "check-version: tag $t" 1
done
# an error is one line on stderr
run check_version v0.1
if [ "$(wc -l <"$WORK/err")" -eq 1 ] && [ ! -s "$WORK/out" ]; then ok; else ng "check-version: one line on stderr"; fi

# ---------------------------------------------------------------- notes.sh

REPO=$WORK/repo
git_() {
  GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_AUTHOR_DATE=2026-01-01T00:00:00Z \
    GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
    git -C "$REPO" "$@" >/dev/null
}
commit_file() { # commit_file PATH MESSAGE
  mkdir -p "$(dirname "$REPO/$1")"
  printf '%s\n' "$2" >"$REPO/$1"
  git_ add "$1"
  git_ commit -q -m "$2"
}
merge_pr() { # merge_pr N TITLE PATH: a branch with one commit, merged with no-ff
  git_ checkout -q -b "pr$1"
  commit_file "$3" "change for $2"
  git_ checkout -q main
  git_ merge -q --no-ff -m "Merge pull request #$1: $2" "pr$1"
}
mkdir -p "$REPO"
git_ init -q -b main
commit_file README.md "initial"
merge_pr 2 "old" docs/adr/0000-old.md
git_ tag v0.0.9
merge_pr 3 "a" docs/adr/0001-x.md
commit_file direct.txt "a commit that is not a merge"
merge_pr 4 "b" docs/golem-cli/adr/0002-y.md
merge_pr 5 "not an ADR" docs/adr/notes.txt
git_ tag v0.1.0

notes() { (cd "$REPO" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 sh "$HERE/notes.sh" "$@"); }

run notes v0.0.9 v0.1.0
expect "notes: the range from the previous tag" 0 "$(cat "$HERE/testdata/notes-v0.1.0.md")"
cp "$WORK/out" "$WORK/notes.md"
run notes v0.1.0
expect "notes: the previous tag is found" 0 "$(cat "$HERE/testdata/notes-v0.1.0.md")"
if [ "$(grep '^## ' "$WORK/notes.md" | head -5 | tr '\n' ' ')" = "## Added ## Changed ## Removed ## Fixed ## Unsorted " ]; then ok; else ng "notes: the headings in order"; fi
git_ tag -d v0.0.9
run notes v0.1.0
expect "notes: from the first commit with no previous tag" 0 "$(cat "$HERE/testdata/notes-first.md")"

# ---------------------------------------------------------------- check-notes.sh

GOOD="## Added

- Something new ([#3](https://github.com/tett23/golem/pull/3), [ADR 0001](https://github.com/tett23/golem/blob/v0.1.0/docs/adr/0001-x.md))

## Fixed

- Something fixed ([#4](https://github.com/tett23/golem/pull/4))
- Something else ([#5](https://github.com/tett23/golem/pull/5))
"
check_notes() { # check_notes TEXT
  printf '%s' "$1" >"$WORK/ai.md"
  sh "$HERE/check-notes.sh" "$WORK/ai.md" "$WORK/notes.md"
}
run check_notes "$GOOD"
expect "check-notes: a good note" 0
run check_notes "$GOOD
## Unsorted

- [#6](https://github.com/tett23/golem/pull/6)
"
expect "check-notes: Unsorted is left" 1
run check_notes "$GOOD
- See #3.
"
expect "check-notes: a bare #3" 1
run check_notes "$GOOD
- See [#3](#3).
"
expect "check-notes: a link to #3" 1
run check_notes "$GOOD
- See [the ADR](../docs/adr/0001-x.md).
"
expect "check-notes: a relative link to an ADR" 1
run check_notes "$GOOD
- See [elsewhere](https://example.com/golem).
"
expect "check-notes: a link to another site" 1
run check_notes "$(printf '%s' "$GOOD" | grep -v 'pull/5')"
expect "check-notes: a pull request is missing" 1
run check_notes "$(printf '%s' "$GOOD" | sed 's/^## .*/## 追加/')"
expect "check-notes: no English heading" 1

# ---------------------------------------------------------------- licenses.sh

L=$WORK/lic
mkdir -p "$L/root/modules/golem-font/cbits/harfbuzz" "$L/root/modules/golem-font/cbits/freetype/docs" \
  "$L/root/modules/golem-font/cbits/freetype/include/freetype" "$L/root/third_party/wasmtime" \
  "$L/root/modules/golem-layout/data/hyphenation" "$L/root/dist-newstyle/src/peg-hs-0123/packages/peg-runtime" \
  "$L/ghcdoc/base-4.20.2.0" "$L/ghcdoc/ghc-9.10.3" "$L/gmp/gmp-6.3.0"
echo MIT >"$L/root/LICENSE"
echo harfbuzz >"$L/root/modules/golem-font/cbits/harfbuzz/COPYING"
echo freetype >"$L/root/modules/golem-font/cbits/freetype/LICENSE.TXT"
echo ftl >"$L/root/modules/golem-font/cbits/freetype/docs/FTL.TXT"
echo ' * Copyright (C) 1996-2026 by' >"$L/root/modules/golem-font/cbits/freetype/include/freetype/freetype.h"
echo wasmtime >"$L/root/third_party/wasmtime/LICENSE"
echo hyph >"$L/root/modules/golem-layout/data/hyphenation/LICENSE-hyph-en-us.txt"
echo peg >"$L/root/dist-newstyle/src/peg-hs-0123/packages/peg-runtime/LICENSE"
echo base >"$L/ghcdoc/base-4.20.2.0/LICENSE"
echo ghc >"$L/ghcdoc/ghc-9.10.3/LICENSE"
echo gpl >"$L/gmp/gmp-6.3.0/COPYINGv3"
echo lgpl >"$L/gmp/gmp-6.3.0/COPYING.LESSERv3"
(cd "$L/gmp" && tar -cJf gmp-6.3.0.tar.xz gmp-6.3.0)
hackage_pkg() { # hackage_pkg NAME VERSION LICENSE-FILE...
  n=$1 v=$2
  shift 2
  rm -rf "${L:?}/src/$n-$v"
  mkdir -p "$L/packages/$n/$v" "$L/src/$n-$v"
  for f in "$@"; do echo "$n" >"$L/src/$n-$v/$f"; done
  echo "name: $n" >"$L/src/$n-$v/$n.cabal"
  (cd "$L/src" && tar -czf "$L/packages/$n/$v/$n-$v.tar.gz" "$n-$v")
}
hackage_pkg foo 1.0 LICENSE
hackage_pkg bar 2.1 license.md COPYING
# the build tools, the dependencies of the tests and of Setup.hs are not
# linked into golem and have no license file here
hackage_pkg happy 2.2
hackage_pkg testonly 1.0
hackage_pkg setuponly 1.0
cat >"$L/plan.json" <<'JSON'
{"install-plan":[
 {"type":"configured","id":"golem-cli-exe","pkg-name":"golem-cli","pkg-version":"0.1.0","pkg-src":{"type":"local"},"style":"local","component-name":"exe:golem","depends":["golem-driver-lib","foo-1","base-1","rts-1"],"exe-depends":["happy-1"]},
 {"type":"configured","id":"golem-cli-test","pkg-name":"golem-cli","pkg-version":"0.1.0","pkg-src":{"type":"local"},"style":"local","component-name":"test:golem-cli-test","depends":["golem-cli-exe","testonly-1"]},
 {"type":"configured","id":"golem-driver-lib","pkg-name":"golem-driver","pkg-version":"0.1.0","pkg-src":{"type":"local"},"style":"local","component-name":"lib","depends":["bar-1","peg-1"]},
 {"type":"configured","id":"foo-1","pkg-name":"foo","pkg-version":"1.0","pkg-src":{"type":"repo-tar"},"style":"global","components":{"lib":{"depends":["base-1"],"exe-depends":[]},"setup":{"depends":["setuponly-1"]}}},
 {"type":"configured","id":"bar-1","pkg-name":"bar","pkg-version":"2.1","pkg-src":{"type":"repo-tar"},"style":"global","depends":["base-1"]},
 {"type":"configured","id":"peg-1","pkg-name":"peg-runtime","pkg-version":"0.1.0.0","pkg-src":{"type":"source-repo","source-repo":{"type":"git","location":"https://github.com/tett23/peg-hs","subdir":"packages/peg-runtime"}},"style":"global","depends":["base-1"]},
 {"type":"configured","id":"happy-1","pkg-name":"happy","pkg-version":"2.2","pkg-src":{"type":"repo-tar"},"style":"global","depends":["base-1"]},
 {"type":"configured","id":"testonly-1","pkg-name":"testonly","pkg-version":"1.0","pkg-src":{"type":"repo-tar"},"style":"global","depends":["base-1"]},
 {"type":"configured","id":"setuponly-1","pkg-name":"setuponly","pkg-version":"1.0","pkg-src":{"type":"repo-tar"},"style":"global","depends":["base-1"]},
 {"type":"pre-existing","id":"base-1","pkg-name":"base","pkg-version":"4.20.2.0","depends":["rts-1"]},
 {"type":"pre-existing","id":"rts-1","pkg-name":"rts","pkg-version":"1.0.2","depends":[]}
]}
JSON
licenses() {
  GOLEM_ROOT="$L/root" CABAL_PACKAGES="$L/packages" GHC_DOCDIR="$L/ghcdoc" GHC_VERSION=9.10.3 \
    GMP_SOURCE="$L/gmp/gmp-6.3.0.tar.xz" GMP_VERSION=6.3.0 \
    sh "$HERE/licenses.sh" "$L/plan.json" "$L/out" v0.1.0
}
run licenses
expect "licenses: all found" 0
for f in README LICENSE-golem haskell/foo-1.0/LICENSE haskell/bar-2.1/license.md haskell/bar-2.1/COPYING \
  haskell/peg-runtime-0.1.0.0/LICENSE haskell/base-4.20.2.0/LICENSE ghc/LICENSE harfbuzz/COPYING \
  freetype/LICENSE.TXT freetype/FTL.TXT wasmtime/LICENSE hyph-en-us/LICENSE-hyph-en-us.txt \
  gmp/COPYINGv3 gmp/COPYING.LESSERv3; do
  if [ -f "$L/out/$f" ]; then ok; else ng "licenses: $f is written"; fi
done
if grep -q 'copyright © 2026 The FreeType Project' "$L/out/README" && grep -q 'GNU MP 6.3.0' "$L/out/README" &&
  grep -q 'https://github.com/tett23/golem/tree/v0.1.0' "$L/out/README"; then ok; else ng "licenses: README"; fi
for d in golem-cli-0.1.0 golem-driver-0.1.0 happy-2.2 testonly-1.0 setuponly-1.0; do
  if [ -e "$L/out/haskell/$d" ]; then ng "licenses: $d is skipped"; else ok; fi
done

rm -rf "${L:?}/out"
hackage_pkg bar 2.1
run licenses
expect "licenses: a package without a license file" 1
if grep -q 'bar-2.1' "$WORK/err"; then ok; else ng "licenses: the package is named"; fi

rm -rf "${L:?}/out"
hackage_pkg bar 2.1 LICENSE
rm "$L/ghcdoc/base-4.20.2.0/LICENSE"
run licenses
expect "licenses: a GHC package without a license file" 1
if grep -q 'base-4.20.2.0' "$WORK/err"; then ok; else ng "licenses: the GHC package is named"; fi

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
