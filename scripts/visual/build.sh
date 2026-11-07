#!/bin/sh
# Typesets the inputs of the visual regression test to PDF
# (docs/adr/0094-visual-regression-page-hashes-at-72-dpi.md).
#
#   build.sh OUT     writes OUT/<input>.pdf for every input
#   build.sh --list  prints the names of the inputs, one per line
#
# The list of the inputs is written here only; check.sh and run.sh read it
# with --list. Each project is copied to a temporary directory and built
# there, so that nothing is written to the build/ of the repository. The
# fonts of the ten public-domain books are copied into the repository with
# scripts/fixtures/copy-fonts.sh, and those of the manuals are fetched into
# manual/fonts and manual-dev/fonts by scripts/manual/fetch-fonts.sh, as
# for the other scripts (GOLEM_MANUAL_SKIP_FONTS=1 skips it, for the
# tests). The manuals are built with a fixed commit and tag, so that their
# colophon does not change with every commit.
#
# GOLEM chooses the golem to run, as in scripts/determinism.sh. The inputs
# are built at the same time, at most as many as there are processors
# (getconf _NPROCESSORS_ONLN); the two manuals are one of them
# (docs/adr/0163). An input that does not build fails the script with exit
# code 1 and the output of golem on stderr, once every other input has
# ended.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
FIX=$ROOT/modules/golem-driver/test/fixtures
PD_BOOKS="elements-of-style frogs haru-to-shura ichiaku-no-suna koya-hijiri merry-wives nightmare-abbey snark taira-no-masakado ushiyama-hotel"
list() {
  printf '%s\n' sample figures complex-vertical complex-horizontal kanikosen kanikosen-marks-japanese tempest languages
  for book in $PD_BOOKS; do printf 'pd-%s\n' "$book"; done
  printf '%s\n' manual manual-dev
}
case "${1-}" in
  --list) list; exit 0 ;;
  "" | -*) echo "usage: build.sh OUT | build.sh --list" >&2; exit 2 ;;
esac
[ $# -eq 1 ] || { echo "usage: build.sh OUT | build.sh --list" >&2; exit 2; }
mkdir -p "$1"
OUT=$(cd "$1" && pwd)
GOLEM=${GOLEM:-golem}
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT

# pdf NAME DIR [ARG...]: builds the PDF of DIR with the ARGs and copies it
# to OUT/NAME.pdf; the output of golem and the failure go to stderr
pdf() {
  name=$1 dir=$2
  shift 2
  rm -rf "$dir/build"
  if ! (cd "$dir" && "$GOLEM" build --target pdf "$@") 2>&1; then
    echo "build: golem build of $name failed"
    return 1
  fi
  one "$name" "$dir"
}

# one NAME DIR: copies the one PDF in DIR/build/pdf to OUT/NAME.pdf
one() {
  find "$2/build/pdf" -type f -name '*.pdf' >"$WORK/pdfs-$1" 2>/dev/null || true
  if [ "$(wc -l <"$WORK/pdfs-$1" | tr -d ' ')" != 1 ]; then
    echo "build: $1 did not write exactly one PDF"
    return 1
  fi
  cp "$(cat "$WORK/pdfs-$1")" "$OUT/$1.pdf"
}

# The jobs: job NAME CMD... runs CMD in the background once fewer than JOBS
# jobs run, with its output in WORK/job-NAME.log and its exit code in
# WORK/job-NAME.code; finish waits for every job and fails with the output
# of each failed one, in the order the jobs were started
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
case $JOBS in '' | *[!0-9]* | 0) JOBS=1 ;; esac
PIDS=
NAMES=
job() {
  jname=$1
  shift
  while :; do
    running=0
    for pid in $PIDS; do
      if kill -0 "$pid" 2>/dev/null; then running=$((running + 1)); fi
    done
    [ "$running" -ge "$JOBS" ] || break
    sleep 0.1
  done
  (
    code=0
    "$@" >"$WORK/job-$jname.log" 2>&1 </dev/null || code=$?
    echo "$code" >"$WORK/job-$jname.code"
  ) &
  PIDS="$PIDS $!"
  NAMES="$NAMES $jname"
}
finish() {
  # shellcheck disable=SC2086
  wait $PIDS
  failed=0
  for jname in $NAMES; do
    if [ "$(cat "$WORK/job-$jname.code" 2>/dev/null)" != 0 ]; then
      cat "$WORK/job-$jname.log" >&2
      failed=1
    fi
  done
  [ "$failed" = 0 ] || exit 1
}

# copy NAME SRC: a copy of the project SRC at WORK/NAME, without its build/
copy() {
  cp -R "$2" "$WORK/$1"
  rm -rf "$WORK/$1/build"
}

# fonts DIR: Noto Serif JP of the kanikosen fixture and Source Sans Pro of
# golem-font as DIR/fonts/ja.otf and DIR/fonts/latin.otf, as in
# scripts/determinism.sh and OutputGoldenSpec
fonts() {
  mkdir -p "$1/fonts"
  cp "$FIX/kanikosen/fonts/NotoSerifJP-Regular.otf" "$1/fonts/ja.otf"
  cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$1/fonts/latin.otf"
}

sh "$ROOT/scripts/fixtures/copy-fonts.sh"

# the copies of the projects, made one after another before the builds
copy sample "$FIX/sample"
fonts "$WORK/sample"
cp "$ROOT/scripts/determinism/pdf-style.toml" "$WORK/sample/style.toml"

copy figures "$FIX/figures"
fonts "$WORK/figures"

# the two books that combine the features (docs/adr/0175)
for book in complex-vertical complex-horizontal; do
  copy "$book" "$FIX/$book"
  fonts "$WORK/$book"
done

copy kanikosen "$FIX/kanikosen"

# the Japanese crop marks with a bleed of 3 mm: the Separation colour of the
# marks and a MediaBox with the bleed
copy kanikosen-marks-japanese "$FIX/kanikosen"
awk '{ print } $0 == "[page]" { print "bleed = \"3mm\"" }' "$FIX/kanikosen/style.toml" >"$WORK/kanikosen-marks-japanese/style.toml"
if ! grep -qx 'bleed = "3mm"' "$WORK/kanikosen-marks-japanese/style.toml"; then
  echo "build: the style.toml of kanikosen has no [page] for the bleed" >&2
  exit 1
fi

copy tempest "$FIX/tempest"

# the characters of both scripts in and out of language spans (docs/adr/0187)
copy languages "$FIX/languages"
fonts "$WORK/languages"

for book in $PD_BOOKS; do
  copy "pd-$book" "$FIX/pd/$book"
done

# the manuals, with their fonts fetched (or checked) in the repository once
mkdir -p "$WORK/manuals"
for manual in manual manual-dev; do
  [ "${GOLEM_MANUAL_SKIP_FONTS-}" = 1 ] || sh "$ROOT/scripts/manual/fetch-fonts.sh" "$ROOT/$manual/fonts"
  cp -R "$ROOT/$manual" "$WORK/manuals/$manual"
  rm -rf "$WORK/manuals/$manual/build"
done

# manuals: the two manuals, built with a fixed commit and tag
manuals() {
  if ! GOLEM=$GOLEM GOLEM_MANUAL_ROOT=$WORK/manuals \
    GOLEM_MANUAL_COMMIT=0000000000000000000000000000000000000000 GOLEM_MANUAL_TAG=v0.0.0-visual \
    sh "$ROOT/scripts/manual/build.sh" manual manual-dev 2>&1; then
    echo "build: the manuals did not build"
    return 1
  fi
  for manual in manual manual-dev; do
    one "$manual" "$WORK/manuals/$manual" || return 1
  done
}

# the manuals first: they take the longest
job manuals manuals
job sample pdf sample "$WORK/sample"
job figures pdf figures "$WORK/figures"
job complex-vertical pdf complex-vertical "$WORK/complex-vertical"
job complex-horizontal pdf complex-horizontal "$WORK/complex-horizontal"
job kanikosen pdf kanikosen "$WORK/kanikosen"
job kanikosen-marks-japanese pdf kanikosen-marks-japanese "$WORK/kanikosen-marks-japanese" --marks japanese
job tempest pdf tempest "$WORK/tempest"
job languages pdf languages "$WORK/languages"
for book in $PD_BOOKS; do
  job "pd-$book" pdf "pd-$book" "$WORK/pd-$book"
done
finish
