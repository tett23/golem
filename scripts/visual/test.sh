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

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
