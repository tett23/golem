#!/bin/sh
# Downloads the source of the GMP that golem links, checks its SHA-256 and
# puts it in DIR as gmp-<version>.tar.xz (docs/adr/0004). The archive goes
# into the GitHub release (LGPL-3.0), and licenses.sh takes the license
# texts from it.
#
#   fetch-gmp.sh VERSION DIR
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
mkdir -p "$DIR"
if [ ! -f "$DIR/$NAME" ]; then
  curl -sSfL -o "$DIR/$NAME.part" "https://gmplib.org/download/gmp/$NAME"
  mv "$DIR/$NAME.part" "$DIR/$NAME"
fi
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$DIR/$NAME" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$DIR/$NAME" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA" ]; then
  rm -f "$DIR/$NAME"
  echo "fetch-gmp: SHA-256 mismatch for $NAME: $ACTUAL" >&2
  exit 1
fi
