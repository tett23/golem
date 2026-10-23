#!/bin/sh
# Checks a release archive on a machine other than the one that built it
# (docs/adr/0004-binary-distribution-and-release.md, the smoke job).
#
#   smoke.sh [--deps] [--offline] [--no-certs CERTFILE] [--determinism OUT] ARCHIVE VERSION
#
#   ARCHIVE            golem-<tag>-<platform>.tar.gz, with ARCHIVE.sha256 next to it
#   VERSION            what golem --version must print after "golem "
#   --deps             also check the dependencies of the executable (on the runner)
#   --offline          skip the steps that fetch fonts (to try it by hand)
#   --no-certs CERT    the system has no root certificates: golem new must
#                      fail and name SSL_CERT_FILE, then work with
#                      SSL_CERT_FILE=CERT
#   --determinism OUT  write the output of scripts/determinism.sh to OUT
#
# It runs in the release runners and in the alpine and debian:stable-slim
# containers, so it uses only POSIX sh, tar, gzip and sha256sum.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
DEPS=
NO_CERTS=
DETERMINISM=
OFFLINE=
while [ $# -gt 2 ]; do
  case "$1" in
    --deps) DEPS=1; shift ;;
    --offline) OFFLINE=1; shift ;;
    --no-certs) NO_CERTS=$2; shift 2 ;;
    --determinism) DETERMINISM=$2; shift 2 ;;
    *) echo "smoke: unknown option: $1" >&2; exit 2 ;;
  esac
done
[ $# -eq 2 ] || {
  echo "usage: smoke.sh [--deps] [--offline] [--no-certs CERTFILE] [--determinism OUT] ARCHIVE VERSION" >&2
  exit 2
}
ARCHIVE=$1
VERSION=$2
# the steps below run in a temporary directory, which is removed at the end
case "$DETERMINISM" in
  "" | /*) ;;
  *) DETERMINISM=$(pwd)/$DETERMINISM ;;
esac

fail() {
  printf 'smoke: %s\n' "$*" >&2
  exit 1
}
step() { printf '== %s\n' "$*"; }

# 1. the SHA-256 and the archive
step "SHA-256 of $(basename "$ARCHIVE")"
(
  cd "$(dirname "$ARCHIVE")"
  if command -v sha256sum >/dev/null 2>&1; then sha256sum -c - <"$(basename "$ARCHIVE").sha256"; else shasum -a 256 -c - <"$(basename "$ARCHIVE").sha256"; fi
) || fail "the SHA-256 of $ARCHIVE does not match"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
tar -xzf "$ARCHIVE" -C "$WORK"
NAME=$(basename "$ARCHIVE" .tar.gz)
DIR=$WORK/$NAME
for f in golem LICENSE BUILDINFO THIRD_PARTY_LICENSES/README; do
  [ -e "$DIR/$f" ] || fail "$NAME has no $f"
done
GOLEM=$DIR/golem

# 2. the version
step "golem --version"
OUT=$("$GOLEM" --version)
[ "$OUT" = "golem $VERSION" ] || fail "golem --version printed '$OUT', not 'golem $VERSION'"

# 3. the dependencies
if [ -n "$DEPS" ]; then
  step "dependencies"
  case "$(uname -s)" in
    Linux)
      file "$GOLEM" | grep -q 'statically linked' || fail "not statically linked: $(file "$GOLEM")"
      LDD=$(ldd "$GOLEM" 2>&1 || true)
      printf '%s\n' "$LDD" | grep -q 'not a dynamic executable' || fail "ldd: $LDD"
      ;;
    Darwin)
      OTHERS=$(otool -L "$GOLEM" | tail -n +2 | awk '{ print $1 }' | grep -Ev '^(/usr/lib/|/System/Library/)' || true)
      [ -z "$OTHERS" ] || fail "libraries outside the OS: $OTHERS"
      MINOS=$(otool -l "$GOLEM" | awk '/LC_BUILD_VERSION/ { b = 1 } b && $1 == "minos" { print $2; exit }')
      [ -n "$MINOS" ] || fail "no minos in LC_BUILD_VERSION"
      awk -v v="$MINOS" 'BEGIN { split(v, a, "."); exit !(a[1] < 14 || (a[1] == 14 && a[2] + 0 == 0)) }' ||
        fail "minos is $MINOS, newer than 14.0"
      codesign --verify "$GOLEM" || fail "codesign --verify failed"
      ;;
  esac
fi

cd "$WORK"

# 4. no network: golem new --no-fonts, and a build of HTML, EPUB and text.
# A project made with --no-fonts does not build until its fonts are put
# in place (style.toml names them, golem-cli ADR 0003), so the build uses
# the sample of golem-driver, which names no fonts.
# Neither writes anything else: golem new --no-fonts writes only the fonts
# to place, and a build writes no diagnostic, not even a notice
# (docs/adr/0080-release-smoke-checks-diagnostics.md).
NO_FONTS_HEAD="フォントを取得しませんでした。次のファイルを置いてください。"
# no_fonts DIR [ARG...]: golem new --no-fonts ARG... DIR; its stderr is the
# line above, then one line per file to place, "  DIR/fonts/FILE (URL)"
no_fonts() {
  dir=$1
  shift
  "$GOLEM" new --no-fonts "$@" "$dir" 2>"$WORK/new.err" || fail "golem new --no-fonts $* $dir: $(cat "$WORK/new.err")"
  [ "$(head -n 1 "$WORK/new.err")" = "$NO_FONTS_HEAD" ] &&
    [ "$(tail -n +2 "$WORK/new.err" | grep -c '')" -ge 1 ] &&
    ! tail -n +2 "$WORK/new.err" | grep -v "^  $dir/fonts/[^ ]* (https://[^ ]*)\$" >/dev/null ||
    fail "golem new --no-fonts $* $dir wrote more than the fonts to place: $(cat "$WORK/new.err")"
}
# build_clean NAME ARG...: golem build --format json ARG... in NAME; its
# stderr is the empty list of diagnostics
build_clean() {
  p=$1
  shift
  (cd "$p" && "$GOLEM" build --format json "$@") 2>"$WORK/build.err" || fail "golem build in $p: $(cat "$WORK/build.err")"
  [ "$(cat "$WORK/build.err")" = "[]" ] || fail "golem build in $p wrote diagnostics: $(cat "$WORK/build.err")"
}
step "golem new --no-fonts"
no_fonts book-ja
no_fonts book-en --language en
step "golem build (HTML, EPUB, text) without fonts"
cp -R "$ROOT/modules/golem-driver/test/fixtures/sample" sample
rm -rf sample/build
build_clean sample --target html --target epub --target text
for t in html epub text; do
  [ -n "$(ls -A "sample/build/$t" 2>/dev/null)" ] || fail "no $t output in the sample"
done

# 5. projects with fonts: HTTPS, name resolution and the certificate store
with_fonts() {
  step "golem new with fonts and golem build (four targets)"
  "$GOLEM" new book || fail "golem new book"
  "$GOLEM" new --language en book-en-fonts || fail "golem new --language en book-en-fonts"
  for p in book book-en-fonts; do
    build_clean "$p"
    for t in html epub text pdf; do
      [ -n "$(ls -A "$p/build/$t" 2>/dev/null)" ] || fail "no $t output in $p"
    done
  done
}

if [ -n "$OFFLINE" ]; then
  step "skipped: golem new with fonts (--offline)"
elif [ -n "$NO_CERTS" ]; then
  # 6. no root certificates
  step "golem new without root certificates"
  CODE=0
  "$GOLEM" new book 2>"$WORK/err" || CODE=$?
  [ "$CODE" -eq 1 ] || fail "golem new book exited with $CODE, not 1"
  grep -q SSL_CERT_FILE "$WORK/err" || fail "the error does not name SSL_CERT_FILE: $(cat "$WORK/err")"
  [ ! -e book ] || fail "golem new made book/"
  SSL_CERT_FILE=$NO_CERTS
  export SSL_CERT_FILE
  with_fonts
else
  with_fonts
fi

# 7. the outputs for the determinism check
if [ -n "$DETERMINISM" ]; then
  step "scripts/determinism.sh"
  GOLEM=$GOLEM sh "$ROOT/scripts/determinism.sh" >"$DETERMINISM"
fi
step "ok"
