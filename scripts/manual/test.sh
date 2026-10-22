#!/bin/sh
# Tests of the scripts of the manuals (docs/adr/0022-manual-as-typesetting-sample.md,
# docs/adr/0024-manual-audiences-and-policy.md). Each test builds its input
# (a small project, a Git repository, a fake golem) in a temporary
# directory; nothing here uses the network.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
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

# expect NAME CODE: checks the exit code of the last run
expect() {
  if [ "$CODE" != "$2" ]; then
    ng "$1 (exit code $CODE, expected $2)"
    return 0
  fi
  ok
}

# err_has NAME TEXT: the stderr of the last run has TEXT
err_has() {
  if grep -qF -- "$2" "$WORK/err"; then ok; else ng "$1 (stderr has no '$2')"; fi
}

# check NAME COMMAND...: passes when COMMAND succeeds
check() {
  name=$1
  shift
  if "$@"; then ok; else ng "$name"; fi
}

# gitinit DIR: an empty Git repository on main
gitinit() {
  mkdir -p "$1"
  git -C "$1" init -q -b main . 2>/dev/null
  git -C "$1" config user.email test@example.com
  git -C "$1" config user.name test
  git -C "$1" config commit.gpgsign false
  git -C "$1" config tag.gpgsign false
}

: >"$WORK/in"

# ---------------------------------------------------------------- check-updated.sh

G=$WORK/git
gitinit "$G"
mkdir -p "$G/docs/golem-pdf" "$G/modules" "$G/manual/chapters" "$G/manual-dev/part1"
echo m >"$G/docs/markup.md"
echo s >"$G/docs/specifications.md"
echo p >"$G/docs/golem-pdf/specifications.md"
echo u >"$G/docs/manual.md"
echo c >"$G/CONTRIBUTING.md"
echo c >"$G/CONTRIBUTING.en.md"
echo g >"$G/manual/chapters/04-markup.gm"
echo g >"$G/manual-dev/part1/cli.gm"
echo h >"$G/modules/a.hs"
git -C "$G" add -A
git -C "$G" commit -q -m init
INIT=$(git -C "$G" rev-parse HEAD)

# branch NAME: a branch from the first commit of main, checked out
branch() {
  git -C "$G" checkout -q -B "$1" "$INIT"
}
# commit FILE MESSAGE: appends a line to FILE and commits it with MESSAGE
commit() {
  echo x >>"$G/$1"
  git -C "$G" add -A
  git -C "$G" commit -q -m "$2"
}
updated() { (cd "$G" && sh "$HERE/check-updated.sh" "$@"); }

branch markup-only
commit docs/markup.md "Change the markup"
run updated "$INIT" markup-only
expect "check-updated: the markup without a manual" 1
err_has "check-updated: the changed file is named" "docs/markup.md"

branch both
commit docs/markup.md "Change the markup"
commit manual/chapters/04-markup.gm "Update the manual"
run updated "$INIT" both
expect "check-updated: the markup and manual/ in two commits" 0

branch spec-dev
commit docs/specifications.md "Change the specification"
commit manual-dev/part1/cli.gm "Update the developer manual"
run updated "$INIT" spec-dev
expect "check-updated: the specification and manual-dev/" 0

branch old-way
commit docs/specifications.md "Change the specification"
commit docs/manual.md "Update the old manual"
run updated "$INIT" old-way
expect "check-updated: docs/manual.md is no longer a manual" 1

branch contributing
commit CONTRIBUTING.md "Change the contributing guide"
commit manual/chapters/04-markup.gm "Update the user manual"
run updated "$INIT" contributing
expect "check-updated: CONTRIBUTING.md with manual/ only" 1
err_has "check-updated: CONTRIBUTING.md is named" "CONTRIBUTING.md"
err_has "check-updated: manual-dev/ is named" "manual-dev/"

branch contributing-en
commit CONTRIBUTING.en.md "Change the contributing guide"
commit manual-dev/part1/cli.gm "Update the developer manual"
run updated "$INIT" contributing-en
expect "check-updated: CONTRIBUTING.en.md and manual-dev/" 0

branch contributing-trailer
commit CONTRIBUTING.md "Fix a typo

Manual: unchanged"
run updated "$INIT" contributing-trailer
expect "check-updated: CONTRIBUTING.md and the trailer" 0

branch module-spec
commit docs/golem-pdf/specifications.md "Change the specification of golem-pdf"
run updated "$INIT" module-spec
expect "check-updated: the specification of a module" 0

branch trailer
commit docs/specifications.md "List a v2 item

Manual: unchanged"
commit modules/a.hs "Change the code"
run updated "$INIT" trailer
expect "check-updated: the trailer Manual: unchanged" 0

branch not-trailer
commit docs/specifications.md "List a v2 item

Manual: unchanged

but this is not the end of the message."
run updated "$INIT" not-trailer
expect "check-updated: Manual: unchanged in the body" 1

branch code
commit modules/a.hs "Change the code"
run updated "$INIT" code
expect "check-updated: modules/ only" 0

branch late
commit modules/a.hs "Change the code"
git -C "$G" checkout -q main
commit docs/markup.md "Change the markup on main"
run updated main late
expect "check-updated: a change of main after the branch point" 0

# ---------------------------------------------------------------- .githooks/pre-push

ZERO=0000000000000000000000000000000000000000
git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"
prepush() { (cd "$G" && sh "$ROOT/.githooks/pre-push" origin https://example.com/r.git); }
SHA=$(git -C "$G" rev-parse markup-only)
printf 'refs/heads/markup-only %s refs/heads/markup-only %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a branch without the manual" 1
SHA=$(git -C "$G" rev-parse both)
printf 'refs/heads/both %s refs/heads/both %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a branch with the manual" 0
SHA=$(git -C "$G" rev-parse markup-only)
printf 'refs/heads/markup-only %s refs/heads/main %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a push to main" 0
printf '(delete) %s refs/heads/markup-only %s\n' "$ZERO" "$SHA" >"$WORK/in"
run prepush
expect "pre-push: the deletion of a branch" 0
: >"$WORK/in"

# ---------------------------------------------------------------- build-info.sh

B=$WORK/info
gitinit "$B"
mkdir -p "$B/book/common"
echo 0.1.0-rc2 >"$B/VERSION"
echo a >"$B/a.txt"
git -C "$B" add -A
git -C "$B" commit -q -m init
info() { sh "$HERE/build-info.sh" "$B/book"; }
INFO=$B/book/common/build-info.gm
# expected EDITION COMMIT: the whole file that build-info.sh writes
expected() {
  printf '%%%% scripts/manual/build-info.sh が書いたファイル。手で編集しない %%%%\n@set edition = "%s"\n@set commit = "%s"\n' "$1" "$2"
}
# same NAME EDITION COMMIT: the file is the expected one
same() {
  if [ -f "$INFO" ] && [ "$(cat "$INFO")" = "$(expected "$2" "$3")" ]; then ok; else
    ng "$1"
    [ ! -f "$INFO" ] || sed 's/^/  build-info.gm: /' "$INFO"
  fi
}

git -C "$B" tag v0.1.0-rc2
HASH=$(git -C "$B" rev-parse HEAD)
run info
expect "build-info: a tagged commit" 0
same "build-info: the tag and the hash" v0.1.0-rc2 "$HASH"
cp "$INFO" "$WORK/info-1" 2>/dev/null || : >"$WORK/info-1"
run info
check "build-info: the same file twice" cmp -s "$INFO" "$WORK/info-1"

echo b >>"$B/a.txt"
git -C "$B" commit -q -am second
git -C "$B" tag fixture-1
HASH=$(git -C "$B" rev-parse HEAD)
run info
expect "build-info: a commit without a v tag" 0
same "build-info: the development edition" "0.1.0-rc2 の開発版" "$HASH"

echo c >"$B/untracked.txt"
run info
same "build-info: an untracked file is not a change" "0.1.0-rc2 の開発版" "$HASH"
echo c >>"$B/a.txt"
run info
same "build-info: an uncommitted change" "0.1.0-rc2 の開発版" "${HASH}（コミットしていない変更を含む）"

O=$WORK/outside
mkdir -p "$O/book/common"
echo 0.1.0-rc2 >"$O/VERSION"
info_env() {
  GIT_CEILING_DIRECTORIES=$WORK GOLEM_MANUAL_COMMIT=0123456789abcdef0123456789abcdef01234567 \
    GOLEM_MANUAL_TAG=v9.9.9 sh "$HERE/build-info.sh" "$O/book"
}
run info_env
expect "build-info: the environment outside a repository" 0
INFO=$O/book/common/build-info.gm
same "build-info: the values of the environment" v9.9.9 0123456789abcdef0123456789abcdef01234567
rm -f "$INFO"
info_none() { GIT_CEILING_DIRECTORIES=$WORK sh "$HERE/build-info.sh" "$O/book"; }
run info_none
expect "build-info: no repository and no environment" 1
check "build-info: no file is written" test ! -e "$INFO"

# ---------------------------------------------------------------- build.sh

R=$WORK/root
for p in manual manual-dev; do
  mkdir -p "$R/$p/common"
  printf 'chapters = ["a.gm"]\n\n[metadata]\ntitle = "t"\n' >"$R/$p/manifest.toml"
done
echo 0.1.0 >"$R/VERSION"
FAKE=$WORK/fake-golem
# the fake golem records its folder, its arguments and whether
# common/build-info.gm was there, writes $FAKE_STDERR and exits with
# $FAKE_CODE
cat >"$FAKE" <<'EOF'
#!/bin/sh
info=no
[ ! -f common/build-info.gm ] || info=yes
printf '%s %s info=%s\n' "$(basename "$PWD")" "$*" "$info" >>"$FAKE_LOG"
[ -z "${FAKE_STDERR-}" ] || printf '%s\n' "$FAKE_STDERR" >&2
exit "${FAKE_CODE:-0}"
EOF
chmod +x "$FAKE"
LOG=$WORK/fake.log
build() {
  rm -f "$LOG" "$R/manual/common/build-info.gm" "$R/manual-dev/common/build-info.gm"
  GOLEM=$FAKE FAKE_LOG=$LOG GOLEM_MANUAL_ROOT=$R GOLEM_MANUAL_SKIP_FONTS=1 \
    GIT_CEILING_DIRECTORIES=$WORK \
    GOLEM_MANUAL_COMMIT=0123456789abcdef0123456789abcdef01234567 \
    sh "$HERE/build.sh" "$@"
}
logged() { [ -f "$LOG" ] && [ "$(cat "$LOG")" = "$1" ]; }

run build
expect "build: a golem that writes nothing" 0
check "build: both manuals with pdf and html, after build-info.sh" logged "manual build --target pdf --target html info=yes
manual-dev build --target pdf --target html info=yes"
check "build: never --no-notices" sh -c '[ -f "$1" ] && ! grep -q -- --no-notices "$1"' sh "$LOG"

run build manual-dev
expect "build: manual-dev only" 0
check "build: only manual-dev is built" logged "manual-dev build --target pdf --target html info=yes"

FAKE_STDERR='notice[G07030]: a.gm:1:1: the line is folded'
FAKE_CODE=0
export FAKE_STDERR FAKE_CODE
run build manual
expect "build: a notice fails the build" 1
err_has "build: the notice is shown" "notice[G07030]"
FAKE_STDERR='warning[G02005]: a.gm:1:1: unused'
run build manual
expect "build: a warning fails the build" 1
unset FAKE_STDERR FAKE_CODE

printf '\n[diagnostics]\nsilence-notices = ["G07030"]\n' >>"$R/manual-dev/manifest.toml"
run build manual-dev
expect "build: silence-notices fails the build" 1
check "build: golem is not run with silence-notices" test ! -e "$LOG"
err_has "build: silence-notices is named" "silence-notices"

run build docs
expect "build: an unknown project" 2

# ---------------------------------------------------------------- manual/manifest.toml

# the files of the chapters of manual/, in order
chapters() {
  awk '/^chapters *= *\[/ { on = 1; next } on && /^\]/ { exit } on' "$ROOT/manual/manifest.toml" |
    sed -n 's/^ *"\([^"]*\)".*/\1/p'
}
FIRST=$(chapters | sed -n 1p)
SECOND=$(chapters | sed -n 2p)
check "manifest: the first file is はじめに, without a number" \
  sh -c 'grep -qx "# はじめに" "$1" && grep -qx "@nonumber" "$1" && ! grep -q "^@toc" "$1"' sh "$ROOT/manual/$FIRST"
check "manifest: the second file has the table of contents" grep -q '^@toc' "$ROOT/manual/$SECOND"

# ---------------------------------------------------------------- fetch-fonts.sh

F=$WORK/fonts
fetch() { sh "$HERE/fetch-fonts.sh" "$F"; }
for font in NotoSerifJP-Regular.otf SourceCodePro-Regular.otf NotoSansJP-Regular.otf; do
  rm -rf "$F"
  mkdir -p "$F"
  echo broken >"$F/$font"
  run fetch
  expect "fetch-fonts: $font whose SHA-256 does not match" 1
  if [ ! -e "$F/$font" ]; then ok; else ng "fetch-fonts: $font is removed"; fi
  err_has "fetch-fonts: $font is named" "$font"
done

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
