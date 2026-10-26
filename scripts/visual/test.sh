#!/bin/sh
# Tests of the scripts of the visual regression test (docs/adr/0093). Each
# script writes into the repository it is in, so each test runs a copy of
# it in a fake root in a temporary directory. Nothing here uses the network
# nor the real golem and shem: fake commands on the front of PATH stand for
# them. The changes and scripts-macos jobs of .github/workflows/ci.yml run
# this.
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
  "$@" >"$WORK/out" 2>"$WORK/err" </dev/null || CODE=$?
}

# expect NAME CODE: checks the exit code of the last run
expect() {
  if [ "$CODE" != "$2" ]; then
    ng "$1 (exit code $CODE, expected $2)"
    return 0
  fi
  ok
}

# fake DIR NAME BODY: an executable DIR/NAME that runs the shell code BODY
fake() {
  mkdir -p "$1"
  printf '#!/bin/sh\n%s\n' "$3" >"$1/$2"
  chmod +x "$1/$2"
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# ---------------------------------------------------------------- fetch-shem.sh
# (docs/adr/0093-fetch-shem-pinned-by-version-and-sha256.md)

FS=$WORK/fetch
VERSION=$(sed -n 's/^VERSION=//p' "$HERE/fetch-shem.sh")
if [ -n "$VERSION" ]; then ok; else ng "fetch-shem: the script has a VERSION"; fi
# a fake uname answers FAKE_UNAME_S and FAKE_UNAME_M; a fake curl records its
# arguments and writes FAKE_ARCHIVE to the file of -o
fake "$FS/bin" uname 'case "$1" in -s) echo "$FAKE_UNAME_S" ;; -m) echo "$FAKE_UNAME_M" ;; *) exit 1 ;; esac'
fake "$FS/bin" curl 'printf "%s\n" "$*" >>"$CURL_LOG"
while [ $# -gt 0 ]; do
  case "$1" in -o) cp "$FAKE_ARCHIVE" "$2" || exit 22; shift ;; esac
  shift
done'
# archive NAME VERSION: a small archive like a release of shem, whose shem
# answers --version with VERSION
archive() {
  rm -rf "$FS/src"
  fake "$FS/src/shem-v$VERSION-aarch64-apple-darwin" shem "[ \"\$1\" = --version ] && echo 'shem $2'"
  printf 'license\n' >"$FS/src/shem-v$VERSION-aarch64-apple-darwin/LICENSE"
  (cd "$FS/src" && tar -czf "$FS/$1" "shem-v$VERSION-aarch64-apple-darwin")
}
archive good.tar.gz "$VERSION"
archive other.tar.gz 9.9.9
GOOD_SHA=$(sha256 "$FS/good.tar.gz")
OTHER_SHA=$(sha256 "$FS/other.tar.gz")
REAL_SHA=$(sed -n 's/.*Darwin-arm64).*SHA=\([0-9a-f]*\).*/\1/p' "$HERE/fetch-shem.sh")
if [ ${#REAL_SHA} = 64 ]; then ok; else ng "fetch-shem: the SHA-256 of the archive for Darwin-arm64 is in the script"; fi
# root DIR SHA: a fake root at DIR whose copy of the script pins SHA for
# Darwin-arm64
root() {
  mkdir -p "$1/scripts/visual"
  sed "s/$REAL_SHA/$2/" "$HERE/fetch-shem.sh" >"$1/scripts/visual/fetch-shem.sh"
}
# fetch ROOT ARCHIVE [ARG...]: runs the copy at ROOT on a Darwin-arm64 that
# downloads ARCHIVE
fetch() {
  r=$1 a=$2
  shift 2
  env PATH="$FS/bin:$PATH" FAKE_UNAME_S="${FAKE_UNAME_S:-Darwin}" FAKE_UNAME_M="${FAKE_UNAME_M:-arm64}" \
    CURL_LOG="$FS/curl.log" FAKE_ARCHIVE="$a" sh "$r/scripts/visual/fetch-shem.sh" "$@"
}

# the SHA-256 of the script: installed, with VERSION
root "$FS/r1" "$GOOD_SHA"
: >"$FS/curl.log"
run fetch "$FS/r1" "$FS/good.tar.gz"
expect "fetch-shem: an archive of the pinned SHA-256 is installed" 0
if [ -x "$FS/r1/third_party/shem/shem" ] && [ "$("$FS/r1/third_party/shem/shem" --version)" = "shem $VERSION" ]; then ok; else ng "fetch-shem: third_party/shem/shem is the shem of the archive"; fi
if [ "$(cat "$FS/r1/third_party/shem/VERSION" 2>/dev/null)" = "shem-v$VERSION-aarch64-apple-darwin.tar.gz $GOOD_SHA" ]; then ok; else ng "fetch-shem: VERSION has the name of the archive and its SHA-256"; fi
if grep -qF "https://github.com/tett23/shem/releases/download/v$VERSION/shem-v$VERSION-aarch64-apple-darwin.tar.gz" "$FS/curl.log"; then ok; else ng "fetch-shem: the archive comes from the release of tett23/shem"; fi
if grep -q -- '-fsSL --connect-timeout 30 --retry 3 ' "$FS/curl.log"; then ok; else ng "fetch-shem: curl fails on an HTTP error, gives up a stalled connection in 30 seconds and retries 3 times"; fi
if grep -q SHA256SUMS "$FS/curl.log"; then ng "fetch-shem: the SHA256SUMS of the release is not fetched"; else ok; fi

# VERSION of the script: nothing is fetched
: >"$FS/curl.log"
run fetch "$FS/r1" "$FS/good.tar.gz"
expect "fetch-shem: an installed shem of the pinned VERSION" 0
if [ ! -s "$FS/curl.log" ]; then ok; else ng "fetch-shem: curl is not called when VERSION is the one of the script"; fi
# another VERSION: fetched again
echo "shem-v0.0.0-aarch64-apple-darwin.tar.gz $GOOD_SHA" >"$FS/r1/third_party/shem/VERSION"
: >"$FS/curl.log"
run fetch "$FS/r1" "$FS/good.tar.gz"
expect "fetch-shem: an installed shem of another VERSION is replaced" 0
if [ -s "$FS/curl.log" ] && [ "$(cat "$FS/r1/third_party/shem/VERSION")" = "shem-v$VERSION-aarch64-apple-darwin.tar.gz $GOOD_SHA" ]; then ok; else ng "fetch-shem: another VERSION is fetched again"; fi

# another SHA-256: exit 1, and nothing is installed
root "$FS/r2" "$GOOD_SHA"
run fetch "$FS/r2" "$FS/other.tar.gz"
expect "fetch-shem: an archive of another SHA-256 fails" 1
if [ ! -e "$FS/r2/third_party/shem" ]; then ok; else ng "fetch-shem: nothing is left in third_party/shem after a SHA-256 mismatch"; fi

# the shem of the archive answers another version: exit 1, nothing installed
root "$FS/r3" "$OTHER_SHA"
run fetch "$FS/r3" "$FS/other.tar.gz"
expect "fetch-shem: a shem of another version fails" 1
if [ ! -e "$FS/r3/third_party/shem" ]; then ok; else ng "fetch-shem: nothing is installed from a shem of another version"; fi

# a platform without an archive: exit 1, and SHEM is named
root "$FS/r4" "$GOOD_SHA"
: >"$FS/curl.log"
FAKE_UNAME_S=Darwin FAKE_UNAME_M=x86_64 run fetch "$FS/r4" "$FS/good.tar.gz"
expect "fetch-shem: Darwin-x86_64 has no archive" 1
if grep -q 'SHEM' "$WORK/err"; then ok; else ng "fetch-shem: the error on a platform without an archive names SHEM"; fi
if [ ! -s "$FS/curl.log" ] && [ ! -e "$FS/r4/third_party/shem" ]; then ok; else ng "fetch-shem: nothing is fetched on a platform without an archive"; fi

# the three platforms of the release
for p in "Darwin arm64 aarch64-apple-darwin" "Linux x86_64 x86_64-unknown-linux-musl" "Linux aarch64 aarch64-unknown-linux-musl"; do
  set -- $p
  FAKE_UNAME_S=$1 FAKE_UNAME_M=$2 run fetch "$FS/r1" "$FS/good.tar.gz" --expected
  expect "fetch-shem: --expected on $1-$2" 0
  if grep -Eqx "shem-v$VERSION-$3\.tar\.gz [0-9a-f]{64}" "$WORK/out" && [ "$(wc -l <"$WORK/out" | tr -d ' ')" = 1 ]; then ok; else ng "fetch-shem: --expected prints the one line of the archive for $1-$2 and its SHA-256"; fi
done
if [ "$(sed -n 's/.*SHA=\([0-9a-f]*\).*/\1/p' "$HERE/fetch-shem.sh" | sort -u | wc -l | tr -d ' ')" = 3 ]; then ok; else ng "fetch-shem: three SHA-256, one per archive"; fi

run fetch "$FS/r1" "$FS/good.tar.gz" --nope
expect "fetch-shem: an unknown argument" 2

# ---------------------------------------------------------------- check.sh
# (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md)

# A fake PDF is text, one line per page. The fake shem records its
# arguments, writes one PPM per line, and fails as shem does (no file, exit
# 1, one line on stderr) on a PDF whose first line is FAIL.
CK=$WORK/check
mkdir -p "$CK/root/scripts/visual"
for s in check.sh build.sh fetch-shem.sh; do cp "$HERE/$s" "$CK/root/scripts/visual/$s"; done
fake "$CK/bin" shem 'printf "%s\n" "$*" >>"$SHEM_LOG"
case "$1" in
  --version) echo "shem $FAKE_SHEM_VERSION"; exit 0 ;;
  render) shift ;;
  *) exit 64 ;;
esac
while [ $# -gt 2 ]; do shift; done
if [ "$(head -n 1 "$1")" = FAIL ]; then
  echo "shem: $1: page 1: offset 120: unsupported operator TJ" >&2
  exit 1
fi
mkdir -p "$2"
n=0
while IFS= read -r line; do
  n=$((n + 1))
  printf "P6\n1 1\n255\n%s\n" "$line" >"$2/$(printf "page-%04d.ppm" "$n")"
done <"$1"'
INPUTS=$(sh "$HERE/build.sh" --list 2>/dev/null)
if [ "$(printf '%s\n' "$INPUTS" | wc -l | tr -d ' ')" = 17 ]; then ok; else ng "build: --list has the 17 inputs"; fi
# pdfs DIR: a fake PDF of three pages for every input
pdfs() {
  rm -rf "$1"
  mkdir -p "$1"
  for i in $INPUTS; do printf '%s 1\n%s 2\n%s 3\n' "$i" "$i" "$i" >"$1/$i.pdf"; done
}
check() {
  env SHEM="$CK/bin/shem" SHEM_LOG="$CK/shem.log" FAKE_SHEM_VERSION="${FAKE_SHEM_VERSION:-$VERSION}" sh "$CK/root/scripts/visual/check.sh" "$@"
}
REFS=$CK/root/scripts/visual/pages
# refs_sum: the names and contents of the references, to see that they stay
refs_sum() { (cd "$REFS" 2>/dev/null && find . -type f | LC_ALL=C sort | xargs cat 2>/dev/null; find . -type f | LC_ALL=C sort); }

pdfs "$CK/p"
: >"$CK/shem.log"
run check --accept "$CK/p"
expect "check: --accept writes the references" 0
if [ "$(find "$REFS" -type f -name '*.txt' | wc -l | tr -d ' ')" = 17 ]; then ok; else ng "check: --accept writes one reference per input"; fi
if [ "$(wc -l <"$REFS/tempest.txt" | tr -d ' ')" = 3 ] && grep -Eqx '[0-9a-f]{64}  page-0001' "$REFS/tempest.txt"; then ok; else ng "check: a reference has a line <SHA-256>  page-<n> per page"; fi
run check "$CK/p"
expect "check: the pages are those of the references" 0
if [ ! -s "$WORK/out" ]; then ok; else ng "check: nothing on stdout when the pages match"; fi
if grep -q '^render ' "$CK/shem.log" && ! grep -q -- '--jobs' "$CK/shem.log"; then ok; else ng "check: shem renders without --jobs"; fi
if [ "$(grep -c '^render --dpi 72 --format ppm ' "$CK/shem.log")" = 34 ]; then ok; else ng "check: shem renders each PDF once at 72 dpi to PPM, one PDF a call"; fi
if [ "$(grep '^render ' "$CK/shem.log" | awk '{ print NF }' | sort -u)" = 7 ]; then ok; else ng "check: one PDF to one directory a call"; fi
if grep -q 'check: rendering manual-dev' "$WORK/err"; then ok; else ng "check: the name of each input goes to stderr"; fi

# one page changed
printf 'tempest 1\ntempest two\ntempest 3\n' >"$CK/p/tempest.pdf"
run check "$CK/p"
expect "check: a changed page fails" 1
if [ "$(cat "$WORK/out")" = "changed tempest page-0002" ]; then ok; else ng "check: changed <input> <page> and nothing else"; fi
# a page more, a page less
printf 'tempest 1\ntempest 2\ntempest 3\ntempest 4\n' >"$CK/p/tempest.pdf"
run check "$CK/p"
expect "check: an added page fails" 1
if [ "$(cat "$WORK/out")" = "added tempest page-0004" ]; then ok; else ng "check: added <input> <page>"; fi
printf 'tempest 1\ntempest 2\n' >"$CK/p/tempest.pdf"
run check "$CK/p"
expect "check: a removed page fails" 1
if [ "$(cat "$WORK/out")" = "removed tempest page-0003" ]; then ok; else ng "check: removed <input> <page>"; fi
pdfs "$CK/p"
# a reference missing, a reference without an input
mv "$REFS/tempest.txt" "$CK/tempest.txt"
run check "$CK/p"
expect "check: an input without a reference fails" 1
if [ "$(cat "$WORK/out")" = "unlisted tempest" ]; then ok; else ng "check: unlisted <input>"; fi
mv "$CK/tempest.txt" "$REFS/tempest.txt"
cp "$REFS/tempest.txt" "$REFS/gone.txt"
run check "$CK/p"
expect "check: a reference without an input fails" 1
if [ "$(cat "$WORK/out")" = "stale gone" ]; then ok; else ng "check: stale <reference>"; fi
rm "$REFS/gone.txt"
# shem fails
printf 'FAIL\n' >"$CK/p/sample.pdf"
run check "$CK/p"
expect "check: a PDF shem cannot read fails" 1
if [ "$(sed -n 1p "$WORK/out")" = "unreadable sample" ] &&
  sed -n 2p "$WORK/out" | grep -q '^shem: .*sample\.pdf: page 1: offset 120: unsupported operator TJ$' &&
  [ "$(wc -l <"$WORK/out" | tr -d ' ')" = 2 ]; then ok; else ng "check: unreadable <input> and the line of shem on stderr"; fi
pdfs "$CK/p"
# a PDF missing
rm "$CK/p/figures.pdf"
run check "$CK/p"
expect "check: a missing PDF fails" 1
if [ "$(cat "$WORK/out")" = "missing figures" ]; then ok; else ng "check: missing <input>"; fi
pdfs "$CK/p"

# --accept rewrites the references, removes the stale ones, and sorts the
# lines by the page with LC_ALL=C
i=1
: >"$CK/p/tempest.pdf"
while [ $i -le 12 ]; do printf 'tempest %s\n' "$i" >>"$CK/p/tempest.pdf"; i=$((i + 1)); done
cp "$REFS/tempest.txt" "$REFS/gone.txt"
run check --accept "$CK/p"
expect "check: --accept after a change" 0
if [ ! -e "$REFS/gone.txt" ]; then ok; else ng "check: --accept removes a stale reference"; fi
if [ "$(wc -l <"$REFS/tempest.txt" | tr -d ' ')" = 12 ] && [ "$(LC_ALL=C sort -k 2,2 "$REFS/tempest.txt")" = "$(cat "$REFS/tempest.txt")" ] &&
  [ "$(sed -n '10s/.*  //p' "$REFS/tempest.txt")" = page-0010 ]; then ok; else ng "check: the lines of a reference are in the order of the pages"; fi
run check "$CK/p"
expect "check: check passes after --accept" 0

# --accept refuses, and changes no reference, when an input is missing, has
# no page or is unreadable
BEFORE=$(refs_sum)
rm "$CK/p/figures.pdf"
run check --accept "$CK/p"
expect "check: --accept with a missing PDF fails" 1
if [ "$(refs_sum)" = "$BEFORE" ]; then ok; else ng "check: --accept with a missing PDF changes no reference"; fi
pdfs "$CK/p"
: >"$CK/p/sample.pdf"
run check --accept "$CK/p"
expect "check: --accept with a PDF of no page fails" 1
if [ "$(refs_sum)" = "$BEFORE" ]; then ok; else ng "check: --accept with a PDF of no page changes no reference"; fi
printf 'FAIL\n' >"$CK/p/sample.pdf"
run check --accept "$CK/p"
expect "check: --accept with an unreadable PDF fails" 1
if [ "$(refs_sum)" = "$BEFORE" ]; then ok; else ng "check: --accept with an unreadable PDF changes no reference"; fi
pdfs "$CK/p"

# a shem of another version: nothing is compared (docs/adr/0093)
: >"$CK/shem.log"
FAKE_SHEM_VERSION=9.9.9 run check "$CK/p"
expect "check: a SHEM of another version fails" 1
if ! grep -q '^render' "$CK/shem.log"; then ok; else ng "check: nothing is rendered with a shem of another version"; fi
# no SHEM and no third_party/shem
run env -u SHEM sh "$CK/root/scripts/visual/check.sh" "$CK/p"
expect "check: without shem" 1
if grep -q 'fetch-shem.sh' "$WORK/err"; then ok; else ng "check: without shem, the error names fetch-shem.sh"; fi
run check "$CK/no-such"
expect "check: no directory of PDFs" 2

# ---------------------------------------------------------------- build.sh
# (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md)

# A fake root with the projects, the fonts and the scripts that build.sh
# uses; the fake golem records where it runs, its arguments, whether the
# style has the bleed, and the build-info.gm of a manual, and writes one PDF
BR=$WORK/vb
FX=$BR/modules/golem-driver/test/fixtures
mkdir -p "$BR/scripts/visual" "$BR/scripts/manual" "$BR/scripts/fixtures" "$BR/scripts/determinism" "$BR/modules/golem-font/test/fonts"
cp "$HERE/build.sh" "$BR/scripts/visual/build.sh"
for s in build.sh build-info.sh fetch-fonts.sh; do cp "$HERE/../manual/$s" "$BR/scripts/manual/$s"; done
cp "$HERE/../fixtures/copy-fonts.sh" "$BR/scripts/fixtures/copy-fonts.sh"
printf '[page]\nsize = "B6"\n' >"$BR/scripts/determinism/pdf-style.toml"
: >"$BR/modules/golem-font/test/fonts/SourceSansPro-Regular.otf"
for p in sample figures kanikosen tempest; do mkdir -p "$FX/$p"; : >"$FX/$p/manifest.toml"; done
printf '[page]\nsize = "B6"\n\n[page.grid]\nlines = 16\n' >"$FX/kanikosen/style.toml"
mkdir -p "$FX/kanikosen/fonts" "$FX/tempest/fonts" "$FX/sample/build"
: >"$FX/kanikosen/fonts/NotoSerifJP-Regular.otf"
: >"$FX/kanikosen/fonts/LICENSE-NotoSerifJP.txt"
: >"$FX/tempest/fonts/SourceSerifVariable-Roman.ttf"
: >"$FX/tempest/fonts/LICENSE-SourceSerif.txt"
for book in elements-of-style frogs haru-to-shura ichiaku-no-suna koya-hijiri merry-wives nightmare-abbey snark taira-no-masakado ushiyama-hotel; do
  mkdir -p "$FX/pd/$book"
  : >"$FX/pd/$book/manifest.toml"
done
for m in manual manual-dev; do
  mkdir -p "$BR/$m/build"
  : >"$BR/$m/manifest.toml"
  : >"$BR/$m/LICENSE"
done
fake "$BR/bin" golem 'here=$(basename "$(pwd)")
printf "%s %s\n" "$here" "$*" >>"$GOLEM_LOG"
if [ -f style.toml ] && grep -qx "bleed = \"3mm\"" style.toml; then printf "%s bleed\n" "$here" >>"$GOLEM_LOG"; fi
if [ -f common/build-info.gm ]; then sed "s/^/$here info /" common/build-info.gm >>"$GOLEM_LOG"; fi
[ "$here" != "$FAKE_GOLEM_FAIL" ] || { echo "error in $here" >&2; exit 1; }
mkdir -p build/pdf
printf "%s\n" "$here" >build/pdf/book.pdf'
visual_build() {
  env GOLEM="$BR/bin/golem" GOLEM_LOG="$BR/golem.log" GOLEM_MANUAL_SKIP_FONTS=1 FAKE_GOLEM_FAIL="${FAKE_GOLEM_FAIL-}" sh "$BR/scripts/visual/build.sh" "$@"
}
find "$BR" -type d -name build | LC_ALL=C sort >"$BR/builds-before"
: >"$BR/golem.log"
run visual_build "$BR/out"
expect "build: every input builds" 0
for i in $INPUTS; do
  [ -f "$BR/out/$i.pdf" ] || ng "build: $i.pdf is written"
done
if [ "$(find "$BR/out" -type f | wc -l | tr -d ' ')" = 17 ]; then ok; else ng "build: one PDF per input, and no other file"; fi
if [ "$(cat "$BR/out/pd-frogs.pdf")" = pd-frogs ]; then ok; else ng "build: the PDF of an input is the one built from its project"; fi
if grep -qx 'kanikosen-marks-japanese build --target pdf --marks japanese' "$BR/golem.log" && grep -qx 'kanikosen-marks-japanese bleed' "$BR/golem.log"; then ok; else ng "build: the crop marks are built with --marks japanese and a bleed of 3mm"; fi
if grep -qx 'kanikosen build --target pdf' "$BR/golem.log" && ! grep -qx 'kanikosen bleed' "$BR/golem.log"; then ok; else ng "build: kanikosen itself has no marks and no bleed"; fi
if [ "$(grep -c '^kanikosen-marks-japanese build\|^kanikosen build' "$BR/golem.log")" = 2 ] && ! grep -q 'western' "$BR/golem.log"; then ok; else ng "build: no western crop marks"; fi
for m in manual manual-dev; do
  if grep -qx "$m info @set commit = \"0000000000000000000000000000000000000000\"" "$BR/golem.log" &&
    grep -qx "$m info @set edition = \"v0.0.0-visual\"" "$BR/golem.log"; then ok; else ng "build: $m is built with the fixed commit and tag"; fi
done
if [ "$(find "$BR" -type d -name build | LC_ALL=C sort)" = "$(cat "$BR/builds-before")" ] &&
  [ -z "$(find "$BR/modules" "$BR/manual" "$BR/manual-dev" -path '*/build/*' -type f)" ]; then ok; else ng "build: nothing is written to a build/ of the repository"; fi
if [ ! -e "$BR/manual/common/build-info.gm" ]; then ok; else ng "build: the build-info.gm of the repository is not written"; fi
if [ -f "$FX/pd/frogs/fonts/SourceSerifVariable-Roman.ttf" ]; then ok; else ng "build: the fonts of the ten books are copied with copy-fonts.sh"; fi
FAKE_GOLEM_FAIL=tempest run visual_build "$BR/out2"
expect "build: an input that does not build fails" 1
if grep -q 'error in tempest' "$WORK/err"; then ok; else ng "build: the output of golem of a failed input goes to stderr"; fi
FAKE_GOLEM_FAIL=manual-dev run visual_build "$BR/out3"
expect "build: a manual that does not build fails" 1
run visual_build
expect "build: no output directory" 2

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
