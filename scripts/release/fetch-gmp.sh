#!/bin/sh
# Downloads the source of the GMP that golem links, checks its SHA-256 and
# puts it in DIR as gmp-<version>.tar.xz (docs/adr/0004). The archive goes
# into the GitHub release (LGPL-3.0), and licenses.sh takes the license
# texts from it.
#
#   fetch-gmp.sh VERSION DIR
#
# gmplib.org often refuses connections from CI runners, so the GNU mirrors
# are tried after it. The SHA-256 is checked whichever served the file.
# scripts/ci/fetch-url.sh fetches it, with retries, into GOLEM_DOWNLOADS
# (third_party/downloads by default), which CI caches; an archive there of
# the SHA-256 is not fetched again (docs/adr/0243).
#
# Add a line to the table below for a new version of GMP.
set -eu
[ $# -eq 2 ] || {
  echo "usage: fetch-gmp.sh VERSION DIR" >&2
  exit 2
}
VERSION=$1
DIR=$2
case "$VERSION" in
  6.3.0) SHA=a3c2b80201b89e68616f4ad30bc66aee4927c3ce50e33929ca819d5c43538898 ;;
  *)
    echo "fetch-gmp: the SHA-256 of gmp-$VERSION.tar.xz is not pinned; add it to scripts/release/fetch-gmp.sh" >&2
    exit 1
    ;;
esac
NAME=gmp-$VERSION.tar.xz
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ARCHIVE=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/$NAME
sh "$ROOT/scripts/ci/fetch-url.sh" "$ARCHIVE" "$SHA" \
  "https://gmplib.org/download/gmp/$NAME" \
  "https://ftpmirror.gnu.org/gmp/$NAME" \
  "https://ftp.gnu.org/gnu/gmp/$NAME" || {
  echo "fetch-gmp: no source of $NAME answered with its SHA-256" >&2
  exit 1
}
mkdir -p "$DIR"
cp "$ARCHIVE" "$DIR/$NAME.part"
mv "$DIR/$NAME.part" "$DIR/$NAME"
