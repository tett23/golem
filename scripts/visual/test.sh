#!/bin/sh
# Tests of the scripts of the visual regression test (docs/adr/0093). Each
# script writes into the repository it is in, so each test runs a copy of
# it in a fake root in a temporary directory. Nothing here uses the network
# nor the real golem and shem: fake commands on the front of PATH stand for
# them. The scripts-linux and scripts-macos jobs of .github/workflows/ci.yml run
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

# fixture NAME CMD...: runs a command that builds the input of the tests.
# A failure stops the tests with its output (docs/adr/0077)
fixture() {
  name=$1
  shift
  "$@" >"$WORK/fixture.log" 2>&1
  fixture_code=$?
  if [ "$fixture_code" != 0 ]; then
    printf 'FIXTURE FAILED: %s\n' "$name"
    sed 's/^/  /' "$WORK/fixture.log"
    exit 1
  fi
}

# git_repo DIR: a new repository at DIR on the branch main, which commits as
# ci, without signing whatever the configuration of the user
git_repo() {
  mkdir -p "$1" &&
    git -C "$1" init -q -b main &&
    git -C "$1" config user.email ci@example.com &&
    git -C "$1" config user.name ci &&
    git -C "$1" config commit.gpgsign false
}

# git_repo_report: the fake root of report.sh as a repository of three
# commits, C0, C1 and C2, with the references of the PDFs of $RP/P0
git_repo_report() {
  git_repo "$RP/root" &&
    env SHEM="$RP/bin/shem" SHEM_LOG="$RP/shem.log" FAKE_SHEM_VERSION="$VERSION" sh "$RP/root/scripts/visual/check.sh" --accept "$RP/P0" &&
    git -C "$RP/root" add -A && git -C "$RP/root" commit -q -m c0 && C0=$(git -C "$RP/root" rev-parse HEAD) &&
    echo 1 >"$RP/root/f" && git -C "$RP/root" add f && git -C "$RP/root" commit -q -m c1 && C1=$(git -C "$RP/root" rev-parse HEAD) &&
    echo 2 >"$RP/root/f" && git -C "$RP/root" add f && git -C "$RP/root" commit -q -m c2 && C2=$(git -C "$RP/root" rev-parse HEAD)
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
if [ "$(printf '%s\n' "$INPUTS" | wc -l | tr -d ' ')" = 20 ]; then ok; else ng "build: --list has the 20 inputs"; fi
for i in complex-vertical complex-horizontal; do
  if printf '%s\n' "$INPUTS" | grep -qx "$i"; then ok; else ng "build: --list has $i (docs/adr/0175)"; fi
done
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
if [ "$(find "$REFS" -type f -name '*.txt' | wc -l | tr -d ' ')" = 20 ]; then ok; else ng "check: --accept writes one reference per input"; fi
if [ "$(wc -l <"$REFS/tempest.txt" | tr -d ' ')" = 3 ] && grep -Eqx '[0-9a-f]{64}  page-0001' "$REFS/tempest.txt"; then ok; else ng "check: a reference has a line <SHA-256>  page-<n> per page"; fi
run check "$CK/p"
expect "check: the pages are those of the references" 0
if [ ! -s "$WORK/out" ]; then ok; else ng "check: nothing on stdout when the pages match"; fi
if grep -q '^render ' "$CK/shem.log" && [ "$(grep -c '^render --dpi 72 --format ppm --jobs 1 ' "$CK/shem.log")" = "$(grep -c '^render ' "$CK/shem.log")" ]; then ok; else ng "check: shem renders with --jobs 1 (docs/adr/0168)"; fi
if [ "$(grep -c '^render --dpi 72 --format ppm ' "$CK/shem.log")" = 40 ]; then ok; else ng "check: shem renders each PDF once at 72 dpi to PPM, one PDF a call"; fi
if [ "$(grep '^render ' "$CK/shem.log" | awk '{ print NF }' | sort -u)" = 9 ]; then ok; else ng "check: one PDF to one directory a call"; fi
missed=
for i in $INPUTS; do
  [ "$(grep -cx "check: rendering $i" "$WORK/err")" = 1 ] || missed="$missed $i"
done
if [ -z "$missed" ]; then ok; else ng "check: the name of each input goes to stderr once ($missed)"; fi

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

# The PDFs are rendered at the same time, at most as many as getconf says
# processors, the largest first (docs/adr/0168). A slow fake shem waits
# longer for the inputs that come first in the list, so that they end
# last; it counts the shems that run with a directory each in RUNNING
fake "$CK/slow" getconf '[ "$1" = _NPROCESSORS_ONLN ] && echo "$FAKE_NPROC"'
fake "$CK/slow" shem 'case "$1" in --version) exec "$REAL_SHEM" "$@" ;; esac
for a in "$@"; do pdf=$out; out=$a; done
name=$(basename "$pdf" .pdf)
mkdir "$RUNNING/$name"
ls "$RUNNING" | wc -l | tr -d " " >>"$CONCURRENT"
case "$name" in sample | figures | kanikosen) s=0.6 ;; tempest | pd-frogs) s=0.4 ;; *) s=0.1 ;; esac
sleep "$s"
rmdir "$RUNNING/$name"
exec "$REAL_SHEM" "$@"'
slow_check() {
  rm -rf "$CK/running"
  mkdir -p "$CK/running"
  : >"$CK/concurrent"
  : >"$CK/shem.log"
  env PATH="$CK/slow:$PATH" SHEM="$CK/slow/shem" REAL_SHEM="$CK/bin/shem" SHEM_LOG="$CK/shem.log" FAKE_SHEM_VERSION="$VERSION" \
    RUNNING="$CK/running" CONCURRENT="$CK/concurrent" FAKE_NPROC="$1" sh "$CK/root/scripts/visual/check.sh" "$2"
}
# FAKE_SHEM_VERSION=9.9.9 before the function run above stays set in some
# shells (the sh of macOS): clear it
FAKE_SHEM_VERSION=
pdfs "$CK/p"
fixture "check: the references of the slow shem" check --accept "$CK/p"
run slow_check 3 "$CK/p"
expect "check: the PDFs render at the same time" 0
MAX=$(sort -n "$CK/concurrent" | tail -1)
if [ -n "$MAX" ] && [ "$MAX" -ge 2 ]; then ok; else ng "check: two PDFs or more render at the same time (at most ${MAX:-0})"; fi
if [ -n "$MAX" ] && [ "$MAX" -le 3 ]; then ok; else ng "check: no more PDFs at the same time than getconf _NPROCESSORS_ONLN says (${MAX:-0})"; fi
# two changed pages, a missing PDF and an unreadable one: the same lines in
# the same order as when the PDFs were rendered one by one, whatever order
# they end in
printf 'tempest 1\ntempest two\ntempest 3\n' >"$CK/p/tempest.pdf"
printf 'manual one\nmanual 2\nmanual 3\n' >"$CK/p/manual.pdf"
rm "$CK/p/figures.pdf"
printf 'FAIL\n' >"$CK/p/pd-snark.pdf"
P=$(cd "$CK/p" && pwd)
EXPECTED="missing figures
changed tempest page-0002
unreadable pd-snark
shem: $P/pd-snark.pdf: page 1: offset 120: unsupported operator TJ
changed manual page-0001"
run slow_check 3 "$CK/p"
expect "check: differences found at the same time fail" 1
if [ "$(cat "$WORK/out")" = "$EXPECTED" ]; then ok; else ng "check: the lines are in the order of the inputs"; fi
run slow_check 1 "$CK/p"
if [ "$(cat "$WORK/out")" = "$EXPECTED" ]; then ok; else ng "check: the same lines with one processor"; fi
# with one processor, the shems run one at a time, the largest PDF first and
# PDFs of the same size by name
pdfs "$CK/p"
# the PDFs of three lines are the largest by the length of the name of the
# input; pd-elements-of-style and pd-taira-no-masakado have the same size
: >"$CK/p/pd-snark.pdf"
: >"$CK/p/tempest.pdf"
i=1
while [ $i -le 30 ]; do
  printf 'pd-snark %s\n' "$i" >>"$CK/p/pd-snark.pdf"
  [ $i -gt 20 ] || printf 'tempest %s\n' "$i" >>"$CK/p/tempest.pdf"
  i=$((i + 1))
done
run slow_check 1 "$CK/p"
MAX=$(sort -n "$CK/concurrent" | tail -1)
if [ "$MAX" = 1 ]; then ok; else ng "check: one PDF at a time with one processor (at most ${MAX:-0})"; fi
ORDER=$(sed -n 's#^render .*/\([^/]*\)\.pdf .*#\1#p' "$CK/shem.log" | head -n 4 | tr '\n' ' ')
if [ "$ORDER" = "pd-snark tempest kanikosen-marks-japanese pd-elements-of-style " ]; then ok; else ng "check: the largest PDF first, then by name ($ORDER)"; fi
pdfs "$CK/p"

# ---------------------------------------------------------------- wait-pdfs.sh
# (docs/adr/0099, docs/adr/0165)

# The fake gh records its arguments. For the artifacts, it prints 1 from
# the FAKE_ARTIFACT_AT-th call on (0 before; never when it is empty); for
# the jobs, it makes the jobs of the attempt from FAKE_JOBS, the lines of a
# name and a status separated by a tab, and applies the --jq of the call to
# them with jq, as gh does: so the match of the names is tested whether
# wait-pdfs.sh makes it in jq or in the shell. It fails from
# the 21st question for the artifact, so that a wait-pdfs.sh that never
# stops fails instead.
WT=$WORK/wait
fake "$WT/bin" gh 'printf "%s\n" "$*" >>"$GH_LOG"
case "$*" in
  *"/artifacts?name="*)
    n=$(grep -c "/artifacts?name=" "$GH_LOG")
    [ "$n" -le 20 ] || { echo "fake gh: asked for the artifact more than 20 times" >&2; exit 65; }
    if [ -n "$FAKE_ARTIFACT_AT" ] && [ "$n" -ge "$FAKE_ARTIFACT_AT" ]; then echo 1; else echo 0; fi ;;
  *"/jobs"*)
    while [ "$1" != --jq ]; do shift; done
    if [ -n "$FAKE_JOBS" ]; then printf "%s\n" "$FAKE_JOBS"; fi |
      jq -R "split(\"\t\") | {name: .[0], status: .[1]}" | jq -s "{jobs: .}" | jq -r "$2" ;;
  *) exit 64 ;;
esac'
wait_pdfs() {
  : >"$WT/gh.log"
  env PATH="$WT/bin:$PATH" GH_LOG="$WT/gh.log" WAIT_INTERVAL=0 sh "$HERE/wait-pdfs.sh" "$@"
}
TAB=$(printf '\t')
# joblist NAME STATUS ...: the lines of FAKE_JOBS
joblist() {
  while [ $# -gt 1 ]; do printf '%s\t%s\n' "$1" "$2"; shift 2; done
}
OUT='build (ubuntu-24.04, outputs)'
FAKE_ARTIFACT_AT=3 FAKE_JOBS="$OUT${TAB}in_progress" run wait_pdfs 123 2 "$OUT"
expect "wait-pdfs: waits until visual-pdfs is uploaded" 0
if [ "$(grep -c '^api repos/{owner}/{repo}/actions/runs/123/artifacts?name=visual-pdfs ' "$WT/gh.log")" = 3 ]; then ok; else ng "wait-pdfs: asks for the artifact of the run until it is there"; fi
if grep -q '^api --paginate repos/{owner}/{repo}/actions/runs/123/attempts/2/jobs ' "$WT/gh.log"; then ok; else ng "wait-pdfs: asks for the jobs of the attempt"; fi
FAKE_ARTIFACT_AT=1 FAKE_JOBS="$OUT${TAB}completed" run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: an uploaded artifact is enough, whatever the job" 0
FAKE_ARTIFACT_AT='' FAKE_JOBS="$OUT${TAB}completed" run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: the job completed without the artifact fails" 1
if grep -q "completed without uploading visual-pdfs" "$WORK/err"; then ok; else ng "wait-pdfs: says that the job completed without visual-pdfs"; fi
FAKE_ARTIFACT_AT='' FAKE_JOBS='' run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: no such job fails" 1
if grep -q "has no job '$OUT'" "$WORK/err"; then ok; else ng "wait-pdfs: names the missing job"; fi
run wait_pdfs 123 1
expect "wait-pdfs: usage" 2
# another artifact of the job: the job wasm waits for wasm-native-list (docs/adr/0199)
FAKE_ARTIFACT_AT=2 FAKE_JOBS="$OUT${TAB}in_progress" run wait_pdfs 123 1 "$OUT" wasm-native-list
expect "wait-pdfs: waits until the artifact given is uploaded" 0
if [ "$(grep -c '^api repos/{owner}/{repo}/actions/runs/123/artifacts?name=wasm-native-list ' "$WT/gh.log")" = 2 ] && ! grep -q visual-pdfs "$WT/gh.log"; then ok; else ng "wait-pdfs: asks for the artifact given, not visual-pdfs"; fi
FAKE_ARTIFACT_AT='' FAKE_JOBS="$OUT${TAB}completed" run wait_pdfs 123 1 "$OUT" wasm-native-list
expect "wait-pdfs: the job completed without the artifact given fails" 1
if grep -q "completed without uploading wasm-native-list" "$WORK/err"; then ok; else ng "wait-pdfs: names the artifact given"; fi
run wait_pdfs 123 1 "$OUT" a b
expect "wait-pdfs: usage with five arguments" 2

# The jobs of release.yml, as the run 41918079466 named them: ci.yml is
# called by the job ci, so its jobs are named "ci / ..." (docs/adr/0165).
release_jobs() {
  joblist version completed 'ci / changes' completed 'ci / scripts-linux' completed \
    notes completed 'build (aarch64-linux, ubuntu-24.04-arm)' completed \
    'build (x86_64-linux, ubuntu-24.04)' completed 'build (aarch64-macos, macos-15)' completed \
    'ci / plugins' completed 'ci / visual' in_progress \
    'ci / build (ubuntu-24.04-arm, tests-driver)' in_progress \
    'ci / build (ubuntu-24.04-arm, outputs)' "$2" \
    'ci / build (ubuntu-24.04, outputs)' "$1" \
    'ci / build (ubuntu-24.04, tests-rest)' in_progress \
    'ci / ci' queued determinism queued release queued
}
FAKE_ARTIFACT_AT='' FAKE_JOBS=$(release_jobs completed in_progress) run wait_pdfs 41918079466 1 "$OUT"
expect "wait-pdfs: a called job completed without the artifact fails" 1
if grep -q "'ci / $OUT' completed without uploading visual-pdfs" "$WORK/err"; then ok; else ng "wait-pdfs: finds the job under the prefix of the caller"; fi
FAKE_ARTIFACT_AT=2 FAKE_JOBS=$(release_jobs in_progress completed) run wait_pdfs 41918079466 1 "$OUT"
expect "wait-pdfs: waits for a called job until visual-pdfs is uploaded" 0
FAKE_ARTIFACT_AT='' FAKE_JOBS=$(joblist "a / b / $OUT" completed) run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: a job under nested callers fails without the artifact" 1
if grep -q "'a / b / $OUT' completed without uploading" "$WORK/err"; then ok; else ng "wait-pdfs: finds the job under nested callers"; fi
FAKE_ARTIFACT_AT='' FAKE_JOBS=$(joblist "x$OUT" completed "$OUT / x" completed) run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: a name that only contains JOB is not the job" 1
if grep -q "has no job '$OUT'" "$WORK/err"; then ok; else ng "wait-pdfs: matches the whole name or the part after ' / '"; fi
FAKE_ARTIFACT_AT='' FAKE_JOBS=$(joblist "$OUT" in_progress "ci / $OUT" in_progress) run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: two matching jobs fail" 1
if grep -qx "  $OUT" "$WORK/err" && grep -qx "  ci / $OUT" "$WORK/err"; then ok; else ng "wait-pdfs: names every matching job"; fi
FAKE_ARTIFACT_AT='' FAKE_JOBS=$(joblist 'ci / build (ubuntu-24.04-arm, outputs)' completed) run wait_pdfs 123 1 "$OUT"
expect "wait-pdfs: the aarch64 outputs is not the job" 1
if grep -q "has no job '$OUT'" "$WORK/err"; then ok; else ng "wait-pdfs: does not take the aarch64 outputs for the job"; fi

# ---------------------------------------------------------------- report.sh
# (docs/adr/0096-before-and-after-images-of-changed-pages.md)

# The fake shem of report.sh: render writes one file per line of the PDF,
# for the pages of --pages only (comma-separated numbers), with the format
# in its content; diff writes "differ: <name>: $FAKE_PIXELS pixels in 1 2
# 3 4" for every file of the second directory that differs from the one of
# the same name in the first, and exits with FAKE_DIFF_CODE (1 by default).
# The fake gh answers run list with the file runs/<commit> and run download
# with the directory artifacts/<run>, and records its arguments.
RP=$WORK/report
mkdir -p "$RP/root/scripts/visual"
for s in check.sh build.sh fetch-shem.sh report.sh; do cp "$HERE/$s" "$RP/root/scripts/visual/$s"; done
fake "$RP/bin" shem 'printf "%s\n" "$*" >>"$SHEM_LOG"
case "$1" in
  --version) echo "shem $FAKE_SHEM_VERSION"; exit 0 ;;
  render)
    shift
    fmt=ppm pages=
    while [ $# -gt 2 ]; do
      case "$1" in --format) fmt=$2; shift ;; --pages) pages=$2; shift ;; --dpi) shift ;; esac
      shift
    done
    mkdir -p "$2"
    n=0
    while IFS= read -r line; do
      n=$((n + 1))
      if [ -n "$pages" ]; then case ",$pages," in *",$n,"*) ;; *) continue ;; esac; fi
      printf "%s %s\n" "$fmt" "$line" >"$2/$(printf "page-%04d" "$n").$fmt"
    done <"$1"
    exit 0 ;;
  diff)
    shift
    while [ $# -gt 3 ]; do shift; done
    [ "${FAKE_DIFF_CODE:-1}" != 2 ] || { echo "shem: $1: cannot read" >&2; exit 2; }
    mkdir -p "$3"
    for f in "$2"/*; do
      name=${f##*/}
      [ -f "$1/$name" ] || continue
      cmp -s "$1/$name" "$f" && continue
      echo "differ: $name: ${FAKE_PIXELS:-1234} pixels in 1 2 3 4"
      cp "$f" "$3/$name"
    done
    exit "${FAKE_DIFF_CODE:-1}" ;;
esac
exit 64'
fake "$RP/bin" gh 'printf "%s\n" "$*" >>"$GH_LOG"
case "$1 $2" in
  "run list")
    while [ $# -gt 0 ]; do [ "$1" = --commit ] && c=$2; shift; done
    [ -f "$FAKE_GH/runs/$c" ] && cat "$FAKE_GH/runs/$c"
    exit 0 ;;
  "run download")
    run=$3
    while [ $# -gt 0 ]; do [ "$1" = -D ] && d=$2; shift; done
    [ -d "$FAKE_GH/artifacts/$run" ] || { echo "no artifact" >&2; exit 1; }
    mkdir -p "$d"
    cp "$FAKE_GH/artifacts/$run"/* "$d/"
    exit 0 ;;
esac
exit 1'
FAKE_GH=$RP/gh
# the repository: three commits C0, C1 and C2 with the references of the
# PDFs P0 (three pages each)
pdfs "$RP/P0"
fixture "report: the repository" git_repo_report
rp_check() { env PATH="$RP/bin:$PATH" SHEM="$RP/bin/shem" SHEM_LOG="$RP/shem.log" FAKE_SHEM_VERSION="$VERSION" sh "$RP/root/scripts/visual/check.sh" "$@"; }
report() {
  env PATH="$RP/bin:$PATH" SHEM="$RP/bin/shem" SHEM_LOG="$RP/shem.log" GH_LOG="$RP/gh.log" FAKE_GH="$FAKE_GH" FAKE_SHEM_VERSION="$VERSION" \
    GITHUB_REPOSITORY=tett23/golem FAKE_DIFF_CODE="${FAKE_DIFF_CODE:-1}" sh "$RP/root/scripts/visual/report.sh" "$@"
}
# scenario NAME: the current PDFs P1, P0 with tempest page 2 changed, and
# the output of check.sh on them in $RP/check.txt; a fresh OUT and logs
scenario() {
  rm -rf "$RP/P1" "$RP/out" "$FAKE_GH"
  cp -R "$RP/P0" "$RP/P1"
  printf 'tempest 1\ntempest two\ntempest 3\n' >"$RP/P1/tempest.pdf"
  mkdir -p "$FAKE_GH/runs" "$FAKE_GH/artifacts"
  : >"$RP/gh.log"
  rp_check "$RP/P1" >"$RP/check.txt" 2>/dev/null || true
  : >"$RP/shem.log"
}
# artifact COMMIT RUN DIR: the run RUN of COMMIT has the PDFs of DIR
artifact() {
  printf '%s\n' "$2" >>"$FAKE_GH/runs/$1"
  mkdir -p "$FAKE_GH/artifacts/$2"
  cp "$3"/*.pdf "$FAKE_GH/artifacts/$2/"
}

# the base has the artifact
scenario
if [ "$(cat "$RP/check.txt")" = "changed tempest page-0002" ]; then ok; else ng "report: the output of check.sh for the scenario"; fi
artifact "$C2" 11 "$RP/P0"
run report "$RP/check.txt" "$RP/P1" "$RP/out" "$C2"
expect "report: the base has the artifact" 0
if grep -q "^run list --repo tett23/golem --workflow ci.yml --commit $C2 --event push" "$RP/gh.log" && grep -q '^run download 11 .*-n visual-pdfs' "$RP/gh.log"; then ok; else ng "report: the artifact of the run of the base is downloaded"; fi
if [ "$(cat "$RP/out/before/tempest/page-0002.png" 2>/dev/null)" = "png tempest 2" ] && [ "$(cat "$RP/out/after/tempest/page-0002.png" 2>/dev/null)" = "png tempest two" ] &&
  [ -f "$RP/out/diff/tempest/page-0002.png" ]; then ok; else ng "report: the images before, after and of the difference"; fi
if grep -qxF '| tempest | page-0002 | `changed` | 1234 | 1 2 3 4 |' "$RP/out/summary.md"; then ok; else ng "report: the count and the box of shem diff are in the summary"; fi
if grep -q -- '--dpi 150 --format png' "$RP/shem.log" && grep -q '^diff --format ppm ' "$RP/shem.log"; then ok; else ng "report: the counts at 72 dpi in PPM, the images at 150 dpi in PNG"; fi
# pages/ is what check.sh --accept writes for the same PDFs
rm -rf "$RP/accept"
mkdir -p "$RP/accept/scripts/visual"
cp "$HERE/check.sh" "$HERE/build.sh" "$HERE/fetch-shem.sh" "$RP/accept/scripts/visual/"
env SHEM="$RP/bin/shem" SHEM_LOG="$RP/shem.log" FAKE_SHEM_VERSION="$VERSION" sh "$RP/accept/scripts/visual/check.sh" --accept "$RP/P1" >/dev/null 2>&1
rm -rf "$RP/lists"
run rp_check --lists "$RP/lists" "$RP/P1"
expect "check: --lists compares as check does" 1
if [ "$(cat "$WORK/out")" = "changed tempest page-0002" ]; then ok; else ng "check: --lists prints the differences"; fi
if [ -d "$RP/lists" ] && diff -r "$RP/accept/scripts/visual/pages" "$RP/lists" >/dev/null; then ok; else ng "check: --lists writes what check.sh --accept writes"; fi
if [ "$(git -C "$RP/root" status --porcelain)" = "" ]; then ok; else ng "check: --lists does not change the references of the repository"; fi
rm -rf "$RP/lists"
: >"$RP/P1/sample.pdf"
run rp_check --lists "$RP/lists" "$RP/P1"
if [ ! -e "$RP/lists" ]; then ok; else ng "check: --lists writes nothing when --accept would refuse"; fi
if grep -q 'pages/ はない' "$RP/out/summary.md"; then ok; else ng "report: the summary says that pages/ is missing"; fi

# the base has none; its parent neither; the one before has
scenario
artifact "$C0" 12 "$RP/P0"
run report "$RP/check.txt" "$RP/P1" "$RP/out" "$C2"
expect "report: an ancestor has the artifact" 0
if grep -q '^run download 12 ' "$RP/gh.log" && grep -q "^run list .*--commit $C1 " "$RP/gh.log"; then ok; else ng "report: the artifact of the second ancestor is downloaded"; fi
if grep -qxF '| tempest | page-0002 | `changed` | 1234 | 1 2 3 4 |' "$RP/out/summary.md"; then ok; else ng "report: the page of the ancestor with the pixels of the base is the page before"; fi

# no artifact in the 20 ancestors
scenario
run report "$RP/check.txt" "$RP/P1" "$RP/out" "$C2"
expect "report: no artifact" 0
if grep -q '前の画像なし' "$RP/out/summary.md" && grep -qxF '| tempest | page-0002 | `changed` | 前の画像なし |  |' "$RP/out/summary.md"; then ok; else ng "report: 前の画像なし without an artifact"; fi
if [ "$(grep -c '^run list ' "$RP/gh.log")" = 3 ]; then ok; else ng "report: the ancestors are looked at up to the root, at most 20"; fi
if [ -f "$RP/out/after/tempest/page-0002.png" ] && [ ! -e "$RP/out/before" ]; then ok; else ng "report: the image after without one before"; fi

# the page of the artifact is not the page of the base
scenario
cp -R "$RP/P0" "$RP/Pother"
printf 'tempest 1\ntempest zwei\ntempest 3\n' >"$RP/Pother/tempest.pdf"
artifact "$C2" 13 "$RP/Pother"
run report "$RP/check.txt" "$RP/P1" "$RP/out" "$C2"
expect "report: an artifact whose page is not that of the base" 0
if ! grep -q '^diff ' "$RP/shem.log" && [ ! -e "$RP/out/before/tempest/page-0002.png" ]; then ok; else ng "report: a page whose SHA-256 is not that of the base is not used"; fi
if grep -qxF '| tempest | page-0002 | `changed` | 前の画像なし |  |' "$RP/out/summary.md"; then ok; else ng "report: 前の画像なし for a page that is not that of the base"; fi
rm -rf "$RP/Pother"

# shem diff cannot read the images
scenario
artifact "$C2" 11 "$RP/P0"
FAKE_DIFF_CODE=2 run report "$RP/check.txt" "$RP/P1" "$RP/out" "$C2"
expect "report: shem diff fails" 0
if grep -q '^| tempest | page-0002 | `changed` | エラー：shem: .*cannot read |' "$RP/out/summary.md"; then ok; else ng "report: the error of shem diff is in the cell of the page"; fi

# no base (release.yml): gh is not called
scenario
run report "$RP/check.txt" "$RP/P1" "$RP/out"
expect "report: no base" 0
if [ ! -s "$RP/gh.log" ]; then ok; else ng "report: gh is not called without a base"; fi

# 101 changed pages: 100 images
scenario
i=1
: >"$RP/P1/tempest.pdf"
while [ $i -le 101 ]; do printf 'tempest new %s\n' "$i" >>"$RP/P1/tempest.pdf"; i=$((i + 1)); done
rp_check "$RP/P1" >"$RP/check.txt" 2>/dev/null || true
run report "$RP/check.txt" "$RP/P1" "$RP/out"
expect "report: 101 changed pages" 0
if [ "$(find "$RP/out/after" -type f | wc -l | tr -d ' ')" = 100 ]; then ok; else ng "report: the images of the first 100 pages only"; fi
if grep -q '残りの 1 ページ' "$RP/out/summary.md"; then ok; else ng "report: the number of the pages without images is in the summary"; fi
if grep -qxF '| tempest | page-0101 | `added` |  |  |' "$RP/out/summary.md"; then ok; else ng "report: every page is in the table up to 500"; fi

# 501 changed pages: one row per input
scenario
i=1
: >"$RP/P1/tempest.pdf"
while [ $i -le 501 ]; do printf 'tempest new %s\n' "$i" >>"$RP/P1/tempest.pdf"; i=$((i + 1)); done
rp_check "$RP/P1" >"$RP/check.txt" 2>/dev/null || true
run report "$RP/check.txt" "$RP/P1" "$RP/out"
expect "report: 501 changed pages" 0
if grep -qxF '| 入力 | 変わったページ | 違う画素の数の最大 |' "$RP/out/summary.md" && grep -qxF '| tempest | 501 | 前の画像なし |' "$RP/out/summary.md" &&
  ! grep -q '^| tempest | page-' "$RP/out/summary.md"; then ok; else ng "report: over 500 pages, one row per input"; fi

# an unreadable input comes first; unlisted and stale have their table
printf '%s\n' 'unreadable sample' 'shem: x: page 1: unsupported operator TJ' 'changed tempest page-0002' 'unlisted pd-frogs' 'stale gone' >"$RP/check2.txt"
scenario
run report "$RP/check2.txt" "$RP/P1" "$RP/out"
expect "report: unreadable, unlisted and stale" 0
FIRST_TABLE=$(grep -n '^| ' "$RP/out/summary.md" | head -1 | cut -d: -f1)
if [ -n "$FIRST_TABLE" ] && [ "$(sed -n "${FIRST_TABLE}p" "$RP/out/summary.md")" = "| 入力 | shem のエラー |" ] &&
  grep -qxF '| sample | shem: x: page 1: unsupported operator TJ |' "$RP/out/summary.md"; then ok; else ng "report: the unreadable inputs come first"; fi
if grep -qxF '| pd-frogs | `unlisted` |' "$RP/out/summary.md" && grep -qxF '| gone | `stale` |' "$RP/out/summary.md"; then ok; else ng "report: unlisted and stale"; fi
run report "$RP/check.txt" "$RP/no-such" "$RP/out"
expect "report: no directory of PDFs" 2

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
for p in sample figures kanikosen tempest complex-vertical complex-horizontal languages; do mkdir -p "$FX/$p"; : >"$FX/$p/manifest.toml"; done
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
if [ -f fonts/ja.otf ] && [ -f fonts/latin.otf ]; then printf "%s fonts\n" "$here" >>"$GOLEM_LOG"; fi
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
if [ "$(find "$BR/out" -type f | wc -l | tr -d ' ')" = 20 ]; then ok; else ng "build: one PDF per input, and no other file"; fi
if [ "$(cat "$BR/out/pd-frogs.pdf")" = pd-frogs ]; then ok; else ng "build: the PDF of an input is the one built from its project"; fi
# the two books of docs/adr/0175 are built with the fonts copied in as
# fonts/ja.otf and fonts/latin.otf, which the repository does not have
# and so is the fixture of the languages (docs/adr/0187)
for i in complex-vertical complex-horizontal languages; do
  if grep -qx "$i build --target pdf" "$BR/golem.log" && grep -qx "$i fonts" "$BR/golem.log"; then ok; else ng "build: $i is built with fonts/ja.otf and fonts/latin.otf"; fi
  if [ ! -e "$FX/$i/fonts" ]; then ok; else ng "build: the fonts of $i are not copied into the repository"; fi
done
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

# The inputs are built at the same time, at most as many as getconf says
# processors; the manuals are one of them (docs/adr/0163). A slow fake
# golem waits longer for the inputs that start first, so that an input
# built later ends sooner and one PDF could be taken for another; it
# counts the golems that run with a directory each in RUNNING, and writes
# a line when it ends. A fake getconf says 3 processors
fake "$BR/slow" getconf '[ "$1" = _NPROCESSORS_ONLN ] && echo 3'
fake "$BR/slow" golem 'here=$(basename "$(pwd)")
mkdir "$RUNNING/$here"
ls "$RUNNING" | wc -l | tr -d " " >>"$CONCURRENT"
case "$here" in sample | figures | manual) s=0.6 ;; kanikosen*) s=0.4 ;; *) s=0.2 ;; esac
sleep "$s"
rmdir "$RUNNING/$here"
[ "$here" != "$FAKE_GOLEM_FAIL" ] || { echo "error in $here" >&2; exit 1; }
mkdir -p build/pdf
printf "%s\n" "$here" >build/pdf/book.pdf
echo "$here" >>"$ENDED"'
slow_build() {
  rm -rf "$BR/running"
  mkdir -p "$BR/running"
  : >"$BR/concurrent"
  : >"$BR/ended"
  env PATH="$BR/slow:$PATH" GOLEM="$BR/slow/golem" RUNNING="$BR/running" CONCURRENT="$BR/concurrent" ENDED="$BR/ended" \
    GOLEM_MANUAL_SKIP_FONTS=1 FAKE_GOLEM_FAIL="${FAKE_GOLEM_FAIL-}" sh "$BR/scripts/visual/build.sh" "$@"
}
# FAKE_GOLEM_FAIL=... before a function stays set in some shells (the sh
# of macOS): clear it
FAKE_GOLEM_FAIL=
run slow_build "$BR/out4"
expect "build: the inputs build at the same time" 0
wrong=
for i in $INPUTS; do
  [ "$(cat "$BR/out4/$i.pdf" 2>/dev/null)" = "$i" ] || wrong="$wrong $i"
done
if [ -z "$wrong" ]; then ok; else ng "build: built at the same time, each PDF is that of its input ($wrong)"; fi
MAX=$(sort -n "$BR/concurrent" | tail -1)
if [ -n "$MAX" ] && [ "$MAX" -ge 2 ]; then ok; else ng "build: two inputs or more are built at the same time (at most ${MAX:-0})"; fi
if [ -n "$MAX" ] && [ "$MAX" -le 3 ]; then ok; else ng "build: no more inputs at the same time than getconf _NPROCESSORS_ONLN says (${MAX:-0})"; fi
# a failed input: its output on stderr, exit 1, after every other golem ended
FAKE_GOLEM_FAIL=sample run slow_build "$BR/out5"
ENDED_AT_EXIT=$(wc -l <"$BR/ended" | tr -d ' ')
if [ "$CODE" = 1 ] && grep -qx 'error in sample' "$WORK/err" && [ "$ENDED_AT_EXIT" = 19 ]; then ok; else
  ng "build: a failed input fails the run after the other inputs end (exit $CODE, $ENDED_AT_EXIT ended)"
fi

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
