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
# expected EDITION COMMIT UNCOMMITTED: the whole file that build-info.sh writes
expected() {
  printf '%%%% scripts/manual/build-info.sh が書いたファイル。手で編集しない %%%%\n@set edition = "%s"\n@set commit = "%s"\n@set uncommitted = "%s"\n' "$1" "$2" "$3"
}
# same NAME EDITION COMMIT UNCOMMITTED: the file is the expected one
same() {
  if [ -f "$INFO" ] && [ "$(cat "$INFO")" = "$(expected "$2" "$3" "$4")" ]; then ok; else
    ng "$1"
    [ ! -f "$INFO" ] || sed 's/^/  build-info.gm: /' "$INFO"
  fi
}

git -C "$B" tag v0.1.0-rc2
HASH=$(git -C "$B" rev-parse HEAD)
run info
expect "build-info: a tagged commit" 0
same "build-info: the tag and the hash" v0.1.0-rc2 "$HASH" ""
cp "$INFO" "$WORK/info-1" 2>/dev/null || : >"$WORK/info-1"
run info
check "build-info: the same file twice" cmp -s "$INFO" "$WORK/info-1"

echo b >>"$B/a.txt"
git -C "$B" commit -q -am second
git -C "$B" tag fixture-1
HASH=$(git -C "$B" rev-parse HEAD)
run info
expect "build-info: a commit without a v tag" 0
same "build-info: the development edition" "0.1.0-rc2 の開発版" "$HASH" ""

echo c >"$B/untracked.txt"
run info
same "build-info: an untracked file is not a change" "0.1.0-rc2 の開発版" "$HASH" ""
echo c >>"$B/a.txt"
run info
same "build-info: an uncommitted change" "0.1.0-rc2 の開発版" "$HASH" "（コミットしていない変更を含む）"
info_env_dirty() {
  GOLEM_MANUAL_COMMIT=0123456789abcdef0123456789abcdef01234567 GOLEM_MANUAL_TAG=v9.9.9 \
    sh "$HERE/build-info.sh" "$B/book"
}
run info_env_dirty
expect "build-info: the environment with an uncommitted change" 0
same "build-info: the environment ignores the change" v9.9.9 0123456789abcdef0123456789abcdef01234567 ""

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
same "build-info: the values of the environment" v9.9.9 0123456789abcdef0123456789abcdef01234567 ""
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
  printf 'the license of %s\n' "$p" >"$R/$p/LICENSE"
done
echo 0.1.0 >"$R/VERSION"
FAKE=$WORK/fake-golem
# the fake golem records its folder, its arguments and whether
# common/build-info.gm was there, makes build/html/ when $FAKE_HTML is
# html and build/html/fonts/ too when it is fonts, writes $FAKE_STDERR and
# exits with $FAKE_CODE
cat >"$FAKE" <<'EOF'
#!/bin/sh
info=no
[ ! -f common/build-info.gm ] || info=yes
printf '%s %s info=%s\n' "$(basename "$PWD")" "$*" "$info" >>"$FAKE_LOG"
case "${FAKE_HTML-}" in
  html) mkdir -p build/html ;;
  fonts) mkdir -p build/html/fonts ;;
esac
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

# the license documents of the HTML (docs/adr/0082-manuals-under-cc0.md)
FAKE_STDERR='notice[G07030]: a.gm:1:1: the line is folded'
FAKE_HTML=fonts
export FAKE_HTML
run build manual
expect "build: a notice with build/html/ still fails the build" 1
check "build: LICENSE is not copied after a notice" test ! -e "$R/manual/build/html/LICENSE"
unset FAKE_STDERR FAKE_CODE

mkdir -p "$R/manual/fonts"
printf 'the license of the font A\n' >"$R/manual/fonts/LICENSE-A.txt"
printf 'the license of the font B\n' >"$R/manual/fonts/LICENSE-B.md"
printf 'not a license\n' >"$R/manual/fonts/A.otf"
run build manual
expect "build: build/html/fonts/ and the license documents" 0
check "build: build/html/LICENSE is the LICENSE of the project" \
  cmp -s "$R/manual/LICENSE" "$R/manual/build/html/LICENSE"
check "build: fonts/LICENSE-A.txt is copied" \
  cmp -s "$R/manual/fonts/LICENSE-A.txt" "$R/manual/build/html/fonts/LICENSE-A.txt"
check "build: fonts/LICENSE-B.md is copied" \
  cmp -s "$R/manual/fonts/LICENSE-B.md" "$R/manual/build/html/fonts/LICENSE-B.md"
check "build: a font is not copied by build.sh" test ! -e "$R/manual/build/html/fonts/A.otf"

FAKE_HTML=html
run build manual
expect "build: build/html/ without fonts/" 0
check "build: build/html/LICENSE without fonts/" \
  cmp -s "$R/manual/LICENSE" "$R/manual/build/html/LICENSE"
check "build: build/html/fonts/ is not made" test ! -e "$R/manual/build/html/fonts"
unset FAKE_HTML

mv "$R/manual/LICENSE" "$WORK/LICENSE.manual"
run build manual
expect "build: a project without LICENSE" 1
err_has "build: LICENSE is named" "LICENSE"
mv "$WORK/LICENSE.manual" "$R/manual/LICENSE"
rm -rf "$R/manual/fonts" "$R/manual/build"

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

# ---------------------------------------------------------------- the licenses of the manuals

# docs/adr/0082-manuals-under-cc0.md: the deed on line 1, a blank line 2 and
# the legal code of CC0 1.0 unchanged from line 3
CC0_DEED=https://creativecommons.org/publicdomain/zero/1.0/
CC0_SHA256=a2010f343487d3f7618affe54f789f5487602331c0a8d03f49e9a7c547cf0499
# sha256 FILE: the SHA-256 of FILE in hex
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d ' ' -f 1
}
for p in manual manual-dev; do
  L=$ROOT/$p/LICENSE
  if [ -f "$L" ]; then ok; else ng "license: $p/LICENSE exists"; continue; fi
  check "license: line 1 of $p/LICENSE is the deed" test "$(sed -n 1p "$L")" = "$CC0_DEED"
  check "license: line 2 of $p/LICENSE is blank" test -z "$(sed -n 2p "$L")"
  tail -n +3 "$L" >"$WORK/legalcode"
  check "license: $p/LICENSE has the legal code of CC0 1.0 unchanged" \
    test "$(sha256 "$WORK/legalcode")" = "$CC0_SHA256"
  check "license: the colophon of $p names CC0 1.0" grep -qF 'CC0 1.0' "$ROOT/$p/back.gm"
  check "license: the colophon of $p names the OFL" \
    grep -qF 'SIL Open Font License 1.1' "$ROOT/$p/back.gm"
done

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
# a missing file is fetched by scripts/ci/fetch-url.sh (docs/adr/0243): a
# fake curl that answers another file fails at its SHA-256, and leaves
# nothing
mkdir -p "$WORK/fonts-bin"
cat >"$WORK/fonts-bin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$*" >>"$FONTS_CURL_LOG"
while [ $# -gt 0 ]; do
  case "$1" in -o) echo other >"$2"; shift ;; esac
  shift
done
FAKE
chmod +x "$WORK/fonts-bin/curl"
rm -rf "$F"
: >"$WORK/fonts-curl.log"
run env PATH="$WORK/fonts-bin:$PATH" FONTS_CURL_LOG="$WORK/fonts-curl.log" sh "$HERE/fetch-fonts.sh" "$F"
expect "fetch-fonts: a fetched file of another SHA-256 fails" 1
if [ "$(grep -c . "$WORK/fonts-curl.log")" = 1 ] && grep -qF -- "--proto =https --tlsv1.2 -fsSL --connect-timeout 30 --max-time 120 -o $F/NotoSerifJP-Regular.otf.part https://raw.githubusercontent.com/notofonts/noto-cjk/" "$WORK/fonts-curl.log"; then ok; else ng "fetch-fonts: the file is fetched once by fetch-url.sh (docs/adr/0243)"; fi
if [ -z "$(find "$F" -type f)" ]; then ok; else ng "fetch-fonts: nothing is left of a file of another SHA-256"; fi
err_has "fetch-fonts: the mismatch is named" "SHA-256 mismatch"

# ---------------------------------------------------------------- outline-prepare.sh

# prep NAME: the source $WORK/fig.svg through outline-prepare.sh, into $WORK/out
prep() { sh "$HERE/outline-prepare.sh" <"$WORK/fig.svg"; }
# figure STYLE TEXT...: a source with the rules STYLE (one per line) and
# the lines TEXT
figure() {
  style=$1
  shift
  {
    echo '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">'
    echo '  <!-- 図（説明）。 -->'
    echo '  <style>'
    echo '    @font-face { font-family: "Fig Sans"; src: url("../../fonts/NotoSansJP-Regular.otf"); }'
    printf '%s\n' "$style"
    echo '  </style>'
    printf '%s\n' "$@"
    echo '</svg>'
  } >"$WORK/fig.svg"
}
# text_is NAME CONTENT: the text element of the last run is CONTENT inside
# the tspan of golem-outline with no attribute but its class
H='<tspan class="golem-halt">'
text_is() {
  want="<text x=\"1\" y=\"2\"><tspan class=\"golem-outline\">$2</tspan></text>"
  if grep -qF -- "$want" "$WORK/out"; then ok; else ng "$1 (no '$want')"; fi
}
out_has() { if grep -qF -- "$2" "$WORK/out"; then ok; else ng "$1 (stdout has no '$2')"; fi; }
out_lacks() { if grep -qF -- "$2" "$WORK/out"; then ng "$1 (stdout has '$2')"; else ok; fi; }

T='    text { font-family: "Fig Sans"; }'
SA='    text { text-spacing-trim: space-all; }'
HR='    tspan.halt { font-feature-settings: "halt"; }'
# the text of the sources goes to Inkscape as it is, with the tspans of
# halt that the sources have (docs/adr/0239 section 3)
H='<tspan class="halt">'
for case in \
  'a halt kept as it is|（G02014'"$H"'）</tspan>。|（G02014'"$H"'）</tspan>。' \
  'two halts|あ'"$H"'）</tspan>'"$H"'」</tspan>。|あ'"$H"'）</tspan>'"$H"'」</tspan>。' \
  'no halt is added|「行分割」（階層 1）|「行分割」（階層 1）' \
  'no punctuation|golem build の PDF|golem build の PDF'; do
  name=${case%%|*}
  rest=${case#*|}
  figure "$T
$SA
$HR" "  <text x=\"1\" y=\"2\">${rest%%|*}</text>"
  run prep
  expect "outline-prepare: $name: exit code" 0
  text_is "outline-prepare: $name" "${rest#*|}"
done

figure "$T" '  <rect x="0"/><text x="1" y="2">あ<tspan class="halt">）</tspan>。</text><text x="1" y="2">い」<tspan class="halt">「</tspan></text>'
run prep
text_is "outline-prepare: the first of two text elements on a line" "あ${H}）</tspan>。"
text_is "outline-prepare: the second of two text elements on a line" "い」${H}「</tspan>"
out_has "outline-prepare: the other elements are kept" '<rect x="0"/>'
out_has "outline-prepare: comments are kept as they are" '<!-- 図（説明）。 -->'
out_lacks "outline-prepare: @font-face is removed" '@font-face'

figure "$T
$SA
$HR
    .c { text-anchor: middle; dominant-baseline: central; }
    .a, text.b { dominant-baseline: central }
    .v { writing-mode: tb; text-anchor: middle; }
    .h { fill: #333; }" '  <text class="c" x="1" y="2">あ</text>'
run prep
expect "outline-prepare: rules: exit code" 0
out_has "outline-prepare: the rules begin" '    /* golem-outline: begin */'
out_has "ADR0239-I6: the tspans of halt are not shifted" '    tspan.halt { baseline-shift: 0; }'
out_lacks "ADR0239-I6: text-spacing-trim is removed" 'text-spacing-trim'
out_has "ADR0239-I6: the rule of halt of the source is kept" "$HR"
out_lacks "ADR0239-I6: no rule of golem-halt" 'golem-halt'
out_has "outline-prepare: central is lowered" '    .c > tspan.golem-outline { baseline-shift: -0.056em; }'
out_has "outline-prepare: each selector of a list (1)" '    .a > tspan.golem-outline { baseline-shift: -0.056em; }'
out_has "outline-prepare: each selector of a list (2)" '    text.b > tspan.golem-outline { baseline-shift: -0.056em; }'
out_has "outline-prepare: vertical text is not lowered" '    .v > tspan.golem-outline { baseline-shift: 0; }'
out_lacks "outline-prepare: vertical text has no rule of vhal" 'vhal'
out_has "outline-prepare: the rules end" '    /* golem-outline: end */'
out_lacks "outline-prepare: other rules add nothing" '.h >'
if [ "$(sed -n '/golem-outline: end/{n;p;}' "$WORK/out")" = '  </style>' ]; then ok; else ng "outline-prepare: the rules are the last of the style sheet"; fi
if [ "$(grep -n 'vertical text is not lowered\|\.v > tspan' "$WORK/out" | cut -d: -f1)" -gt "$(grep -n '\.c > tspan' "$WORK/out" | cut -d: -f1)" ]; then ok; else ng "outline-prepare: the rules of vertical text follow those of central"; fi
out_has "outline-prepare: a text of a class is wrapped" '<text class="c" x="1" y="2"><tspan class="golem-outline">あ</tspan></text>'

figure "$T" '  <text x="1" y="2" dominant-baseline="central">あ</text>' \
  '  <text x="1" y="3" style="dominant-baseline: central">い</text>' \
  '  <text x="1" y="4" style="writing-mode: tb" dominant-baseline="central">う）</text>'
run prep
out_has "outline-prepare: the attribute central is lowered" '<text x="1" y="2" dominant-baseline="central"><tspan class="golem-outline" baseline-shift="-0.056em">あ</tspan></text>'
out_has "outline-prepare: central in style is lowered" '<text x="1" y="3" style="dominant-baseline: central"><tspan class="golem-outline" baseline-shift="-0.056em">い</tspan></text>'
out_has "outline-prepare: vertical text of its own is not lowered" '<text x="1" y="4" style="writing-mode: tb" dominant-baseline="central"><tspan class="golem-outline">う）</tspan></text>'

# a halt in vertical text: Inkscape does not place vhal as Chromium does,
# so it stops (ADR0239-I7)
for v in 'class="v"' 'class="x v"' 'style="writing-mode: tb"' 'writing-mode="tb"'; do
  figure "$T
    .v { writing-mode: tb; }" "  <text $v x=\"1\" y=\"2\">あ<tspan class=\"halt\">）</tspan>。</text>"
  run prep
  expect "ADR0239-I7: outline-prepare: a halt in vertical text ($v): exit code" 1
  err_has "ADR0239-I7: outline-prepare: a halt in vertical text ($v): the message" 'line 8: a tspan of halt in vertical text'
done
figure "$T
    .v { writing-mode: tb; }" '  <text class="v" x="1" y="2">あ）い。</text>'
run prep
expect "outline-prepare: vertical text without a halt: exit code" 0
figure "$T
    #v { writing-mode: tb; }" '  <text x="1" y="2">あ</text>'
run prep
expect "outline-prepare: a selector of vertical text it does not read: exit code" 1
err_has "outline-prepare: a selector of vertical text it does not read: the message" '#v'

for case in \
  'markup inside a text element|  <text x="1" y="2">あ<tspan>い</tspan></text>|has markup inside' \
  'ADR0239-I7: a tspan of another class|  <text x="1" y="2">あ<tspan class="b">）</tspan>。</text>|has markup inside' \
  'ADR0239-I7: a halt around two characters|  <text x="1" y="2">あ<tspan class="halt">）。</tspan></text>|one fullwidth punctuation mark' \
  'a text-spacing-trim it does not read|    text { fill: #000; text-spacing-trim: space-all; }|text-spacing-trim' \
  'a text element over two lines|  <text x="1" y="2">あ|is not on one line' \
  'a rule over two lines|    .c {|one line'; do
  name=${case%%|*}
  rest=${case#*|}
  if [ "$name" = 'a rule over two lines' ]; then
    figure "$T
    .c {
      dominant-baseline: central; }" '  <text x="1" y="2">あ</text>'
  elif [ "$name" = 'a text-spacing-trim it does not read' ]; then
    figure "${rest%%|*}" '  <text x="1" y="2">あ</text>'
  else
    figure "$T" "${rest%%|*}" '</text>'
  fi
  run prep
  expect "outline-prepare: $name: exit code" 1
  err_has "outline-prepare: $name: the message" "${rest#*|}"
done
{
  echo '<svg xmlns="http://www.w3.org/2000/svg">'
  echo '  <style>text { fill: #000; }</style>'
  echo '  <style>.c { fill: #000; }</style>'
  echo '</svg>'
} >"$WORK/fig.svg"
run prep
expect "outline-prepare: two style elements: exit code" 1
err_has "outline-prepare: two style elements: the message" "one style element"

# --strip removes the rules from what Inkscape wrote
printf '%s\n' '<svg>' '  <style' '     id="style1">' '    text { fill: #222; }' \
  '    /* golem-outline: begin */' '    tspan.halt { baseline-shift: 0; }' \
  '    /* golem-outline: end */' '  </style>' '</svg>' >"$WORK/in"
run sh "$HERE/outline-prepare.sh" --strip
expect "outline-prepare --strip: exit code" 0
check "outline-prepare --strip: the rules are removed" test "$(cat "$WORK/out")" = "$(printf '%s\n' '<svg>' '  <style' '     id="style1">' '    text { fill: #222; }' '  </style>' '</svg>')"
: >"$WORK/in"

# the same source, the same bytes (ADR0239-I8)
figure "$T
$SA
$HR
    .c { text-anchor: middle; dominant-baseline: central; }" '  <text class="c" x="1" y="2">あ<tspan class="halt">）</tspan>。</text>'
prep >"$WORK/prep1"
prep >"$WORK/prep2"
check "ADR0239-I8: outline-prepare makes the same bytes twice" cmp -s "$WORK/prep1" "$WORK/prep2"

# ---------------------------------------------------------------- check-figures.sh

# the punctuation of the sources (docs/adr/0239 section 3): CF/images/src
# holds one source and CF/images its outline, whose comment names the
# SHA-256 of the source, so that only the punctuation can fail
CF=$WORK/cf
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d ' ' -f 1; else shasum -a 256 "$1" | cut -d ' ' -f 1; fi; }
# source STYLE TEXT...: CF with the source of figure STYLE TEXT...
source_is() {
  figure "$@"
  rm -rf "$CF"
  mkdir -p "$CF/images/src"
  cp "$WORK/fig.svg" "$CF/images/src/x.svg"
  printf '<!-- Made by scripts/manual/outline-figures.sh from images/src/x.svg (sha256 %s) with test. -->\n<svg/>\n' "$(sha256 "$CF/images/src/x.svg")" >"$CF/images/x.svg"
}
cf() { sh "$HERE/check-figures.sh" "$CF"; }
# horizontal text: NAME|TEXT|EXIT|MESSAGE (MESSAGE is checked when EXIT is 1)
for case in \
  'ADR0239-I4: latin only|golem build の PDF|0|' \
  'ADR0239-I4: one mark|（G02014）|0|' \
  'ADR0239-I4: an empty text element||0|' \
  'ADR0239-I4: P P with the first in halt|（G02014'"$H"'）</tspan>。|0|' \
  'ADR0239-I4: P P without halt|（G02014）。|1|line 9: ） needs a tspan of halt' \
  'ADR0239-I4: P O with the second in halt|「行分割」'"$H"'（</tspan>階層 1）|0|' \
  'ADR0239-I4: P O with the first in halt|「行分割'"$H"'」</tspan>（階層 1）|1|line 9: 」 has a tspan of halt that it does not need' \
  'ADR0241-F3: C S with nothing in halt|作る）　乱数|1|line 9: ） needs a tspan of halt' \
  'ADR0241-F3: C S with the first in halt|作る'"$H"'）</tspan>　乱数|0|' \
  'ADR0241-F3: C O O with the second in halt|あ」'"$H"'（</tspan>「い|1|line 9: 「 needs a tspan of halt' \
  'ADR0241-F3: C O O with the second and the third in halt|あ」'"$H"'（</tspan>'"$H"'「</tspan>い|0|' \
  'ADR0239-I4: P P P with the first two in halt|あ'"$H"'）</tspan>'"$H"'」</tspan>。|0|' \
  'ADR0239-I4: P P P with the first in halt|あ'"$H"'）</tspan>」。|1|」 needs a tspan of halt' \
  'ADR0239-I4: O P|あ（）|0|' \
  'ADR0241-F3: S O with nothing in halt|あ　（い）|1|line 9: （ needs a tspan of halt' \
  'ADR0241-F3: S O with the second in halt|あ　'"$H"'（</tspan>い）|0|' \
  'ADR0239-I4: a halt on a lone mark|'"$H"'（</tspan>G02014）|1|has a tspan of halt that it does not need' \
  'ADR0241-F1: O S|（　あ|0|' \
  'ADR0241-F1: S F|あ　。|0|' \
  'ADR0241-F3: C M with nothing in halt|あ）・い|1|line 9: ） needs a tspan of halt' \
  'ADR0241-F2: C M with the first in halt|あ'"$H"'）</tspan>・い|0|' \
  'ADR0241-F3: O O with the second in halt|（'"$H"'「</tspan>あ」|0|' \
  'ADR0241-F3: O O with nothing in halt|（「あ」|1|line 9: 「 needs a tspan of halt' \
  'ADR0241-F2: M C with the middle dot in halt|あ'"$H"'・</tspan>）|1|line 9: ・ has a tspan of halt that it does not need' \
  'ADR0241-F5: 」〚 is not punctuation|あ」〚い〛|0|'; do
  name=${case%%|*}
  rest=${case#*|}
  text=${rest%%|*}
  rest=${rest#*|}
  want=${rest%%|*}
  msg=${rest#*|}
  source_is "$T
$SA
$HR" "  <text x=\"1\" y=\"2\">$text</text>"
  run cf
  expect "$name: exit code" "$want"
  if [ "$want" = 1 ]; then err_has "$name: the message" "$msg"; fi
done

# vertical text with adjacent marks stops (ADR0239-I7)
source_is "$T
$SA
    .v { writing-mode: tb; }" '  <text class="v" x="1" y="2">あ」（い</text>'
run cf
expect "ADR0239-I7: vertical 」（: exit code" 1
err_has "ADR0239-I7: vertical 」（: the message" 'line 9: vertical text with punctuation next to another (」（)'
source_is "$T
$SA
    .v { writing-mode: tb; }" '  <text class="v" x="1" y="2">あ）い。</text>'
run cf
expect "ADR0239-I7: vertical text without adjacent marks: exit code" 0

# markup other than halt (ADR0239-I7)
source_is "$T
$SA" '  <text x="1" y="2">あ<tspan class="b">）</tspan>。</text>'
run cf
expect "ADR0239-I7: a tspan of another class: exit code" 1
err_has "ADR0239-I7: a tspan of another class: the message" 'line 8: a text element has markup inside'

# the rules of the style sheet (ADR0239-I5)
source_is "$T" '  <text x="1" y="2">あ</text>'
run cf
expect "ADR0239-I5: a source without space-all: exit code" 1
err_has "ADR0239-I5: a source without space-all: the message" 'text { text-spacing-trim: space-all; }'
source_is "$T
$SA" '  <text x="1" y="2">（G02014'"$H"'）</tspan>。</text>'
run cf
expect "ADR0239-I5: a halt without the rule of halt: exit code" 1
err_has "ADR0239-I5: a halt without the rule of halt: the message" 'tspan.halt { font-feature-settings: "halt"; }'

# every pair of the six classes, and the boundaries of three marks, with
# each way of halt (ADR0241-F1, F2, F3; docs/adr/0204, docs/adr/0241): one
# way passes, or none when the procedure stops on the pair; the way that
# passes leaves the optimum aki between each two marks, which the test
# reads from the table itself; no way with a middle dot in halt passes
AKI=$ROOT/modules/golem-layout/test/golden/default-aki-set.tsv
# f1 A B HA HB: whether A B, with HA (HB) 1 when A (B) is in halt, leave
# the optimum aki of the table between them (LC_ALL=C: the awk of macOS
# compares strings by the collation of the locale, where 「 is 」)
f1() {
  LC_ALL=C awk -F '\t' -v a="$1" -v b="$2" -v ha="$3" -v hb="$4" '
    function num(s,   p) { if (split(s, p, "/") == 1) return s + 0; return p[1] / p[2] }
    $1 == "char" && $2 == a { ca = $3; aa = num($5) }
    $1 == "char" && $2 == b { cb = $3; bb = num($4) }
    $1 == "aki" { opt[$2, $3] = num($5) }
    END { s = (ha ? 0 : aa) + (hb ? 0 : bb) - opt[ca, cb]; exit (s < 1e-9 && s > -1e-9) ? 0 : 1 }' "$AKI"
}
middot() { [ "$(LC_ALL=C awk -F '\t' -v c="$1" '$1 == "char" && $2 == c { print $3 }' "$AKI")" = middle-dot ]; }
bit() { echo $((($1 >> ($2 - 1)) & 1)); }
# ways NAME MARKS...: runs check-figures on あMARKSい with each way of halt;
# PASSED is the number of ways that pass and WAY the last of them
ways() {
  wname=$1
  shift
  n=$#
  mask=0
  PASSED=0
  WAY=
  while [ "$mask" -lt $((1 << n)) ]; do
    text=
    i=1
    for m in "$@"; do
      if [ "$(bit "$mask" "$i")" = 1 ]; then text="$text$H$m</tspan>"; else text="$text$m"; fi
      i=$((i + 1))
    done
    source_is "$T
$SA
$HR" "  <text x=\"1\" y=\"2\">あ${text}い</text>"
    run cf
    if [ "$CODE" = 0 ]; then
      PASSED=$((PASSED + 1))
      WAY=$mask
      i=1
      prev=
      for m in "$@"; do
        if [ "$(bit "$mask" "$i")" = 1 ] && middot "$m"; then ng "ADR0241-F2: $wname: a middle dot in halt passes ($text)"; else ok; fi
        if [ -n "$prev" ]; then
          if f1 "$prev" "$m" "$(bit "$mask" $((i - 1)))" "$(bit "$mask" "$i")"; then ok; else ng "ADR0241-F1: $wname: $text passes without the optimum aki of $prev$m"; fi
        fi
        prev=$m
        i=$((i + 1))
      done
    fi
    mask=$((mask + 1))
  done
}
SP=$(printf '\343\200\200')
for a in 「 」 ・ 。 、 "$SP"; do
  for b in 「 」 ・ 。 、 "$SP"; do
    # the procedure sets the pair when one of the ways with one mark or
    # none in halt, and no middle dot in halt, leaves the optimum aki
    want=0
    for w in '0 0' '1 0' '0 1'; do
      set -- $w
      if { [ "$1" = 0 ] || ! middot "$a"; } && { [ "$2" = 0 ] || ! middot "$b"; } && f1 "$a" "$b" "$1" "$2"; then want=1; fi
    done
    ways "$a$b" "$a" "$b"
    if [ "$PASSED" = "$want" ]; then ok; else ng "ADR0241-F3: $a$b: $PASSED ways of halt pass, expected $want"; fi
  done
done
# NAME|MARKS|WAY: the one way that passes (bit 1 is the first mark)
for case in \
  '」（「|」 （ 「|6' \
  '（（（|（ （ （|6' \
  '）」。|） 」 。|3'; do
  name=${case%%|*}
  rest=${case#*|}
  # shellcheck disable=SC2086
  ways "$name" ${rest%%|*}
  if [ "$PASSED" = 1 ] && [ "$WAY" = "${rest#*|}" ]; then ok; else ng "ADR0241-F3: $name: $PASSED ways pass, the last $WAY, expected the one ${rest#*|}"; fi
done

# the table of another set (GOLEM_AKI_TABLE): a pair that halt does not
# set as the table says stops, as does a table that is missing or has a
# line that it does not read (ADR0241-F6)
# fixture NAME AWK: the table with AWK applied to its lines
fixture() { awk -F '\t' -v OFS='\t' "$2" "$AKI" >"$WORK/$1.tsv"; }
fixture cc '$1 == "aki" && $2 == "closing" && $3 == "closing" { $5 = "1/4"; $6 = "1/4" } { print }'
fixture co '$1 == "aki" && $2 == "closing" && $3 == "opening" { $5 = "3/2"; $6 = "3/2" } { print }'
fixture mc '$1 == "aki" && $2 == "middle-dot" && $3 == "closing" { $5 = "0"; $6 = "0" } { print }'
for case in \
  'cc|））|the space to trim is 1/4 em' \
  'co|」（|the space to trim is -1/2 em' \
  'mc|・）|the space to trim is 1/4 em'; do
  t=${case%%|*}
  rest=${case#*|}
  source_is "$T
$SA" "  <text x=\"1\" y=\"2\">あ${rest%%|*}い</text>"
  CODE=0
  GOLEM_AKI_TABLE=$WORK/$t.tsv sh "$HERE/check-figures.sh" "$CF" >"$WORK/out" 2>"$WORK/err" || CODE=$?
  expect "ADR0241-F6: the table $t and ${rest%%|*}: exit code" 1
  err_has "ADR0241-F6: the table $t and ${rest%%|*}: the message" "line 8: a pair of punctuation that a tspan of halt does not set as the body text (${rest%%|*}): ${rest#*|}"
done
source_is "$T
$SA" '  <text x="1" y="2">あい</text>'
CODE=0
GOLEM_AKI_TABLE=$WORK/none.tsv sh "$HERE/check-figures.sh" "$CF" >"$WORK/out" 2>"$WORK/err" || CODE=$?
expect "ADR0241-F6: no table: exit code" 1
err_has "ADR0241-F6: no table: the message" "$WORK/none.tsv: no such file"
cp "$AKI" "$WORK/five.tsv"
printf 'aki\tclosing\tclosing\t0\t0\n' >>"$WORK/five.tsv"
CODE=0
GOLEM_AKI_TABLE=$WORK/five.tsv sh "$HERE/check-figures.sh" "$CF" >"$WORK/out" 2>"$WORK/err" || CODE=$?
expect "ADR0241-F6: an aki row of five columns: exit code" 1
err_has "ADR0241-F6: an aki row of five columns: the line" "$WORK/five.tsv: line $(wc -l <"$WORK/five.tsv" | tr -d ' '): a line that it does not read"

# the same table and source, the same exit code and messages (ADR0241-F7)
source_is "$T
$SA" '  <text x="1" y="2">あ）。（「い</text>'
run cf
cp "$WORK/err" "$WORK/err1"
code1=$CODE
run cf
check "ADR0241-F7: the same exit code twice" test "$code1" = "$CODE" -a "$CODE" = 1
check "ADR0241-F7: the same messages twice" cmp -s "$WORK/err1" "$WORK/err"

# the sources of the repository pass
run sh "$HERE/check-figures.sh"
expect "check-figures: the sources of the manuals" 0

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
