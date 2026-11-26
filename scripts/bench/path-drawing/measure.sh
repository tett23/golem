#!/bin/sh
# Measures the time of the benchmark of the drawing of paths (root ADR
# 0439): builds golem of the current commit with
# `cabal build exe:golem --disable-tests`, then builds the PDF of the book
# in this folder five times, each after removing build/, and prints the
# wall-clock time of each run and, on the last line, their median in
# milliseconds. The method is that of docs/adr/0181.
#
# The book needs a Japanese font at fonts/ja.otf, which is not committed;
# the script copies Noto Serif JP of the fixture 『蟹工船』 there when it is
# missing, as scripts/fixtures/copy-fonts.sh does for the fixtures.
#
# Usage: scripts/bench/path-drawing/measure.sh
set -eu
BOOK=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$BOOK/../../.." && pwd)
FONTS=$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts

cd "$ROOT"
cabal build -v0 exe:golem --disable-tests
GOLEM=$(cabal list-bin -v0 exe:golem --disable-tests)

if [ ! -f "$BOOK/fonts/ja.otf" ]; then
  mkdir -p "$BOOK/fonts"
  cp "$FONTS/NotoSerifJP-Regular.otf" "$BOOK/fonts/ja.otf"
  cp "$FONTS/LICENSE-NotoSerifJP.txt" "$BOOK/fonts/"
fi

# The time since the epoch in milliseconds.
now() { perl -MTime::HiRes=time -e 'printf "%d\n", time * 1000'; }

cd "$BOOK"
TIMES=
for i in 1 2 3 4 5; do
  rm -rf build
  start=$(now)
  "$GOLEM" build --target pdf >/dev/null
  end=$(now)
  ms=$((end - start))
  printf 'run %s: %s ms\n' "$i" "$ms"
  TIMES="$TIMES $ms"
done
rm -rf build

# The median of the five: the third of them in order.
printf '%s\n' $TIMES | sort -n | sed -n 3p
