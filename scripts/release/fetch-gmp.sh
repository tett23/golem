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
  for url in "https://gmplib.org/download/gmp/$NAME" \
    "https://ftpmirror.gnu.org/gmp/$NAME" \
    "https://ftp.gnu.org/gnu/gmp/$NAME"; do
    if curl -sSfL --connect-timeout 20 --retry 2 -o "$DIR/$NAME.part" "$url"; then
      mv "$DIR/$NAME.part" "$DIR/$NAME"
      break
    fi
    echo "fetch-gmp: could not download $url" >&2
  done
  [ -f "$DIR/$NAME" ] || {
    rm -f "$DIR/$NAME.part"
    echo "fetch-gmp: no source of $NAME answered" >&2
    exit 1
  }
fi
if command -v sha256sum >/dev/null 2>&1; then ACTUAL=$(sha256sum "$DIR/$NAME" | cut -d' ' -f1); else ACTUAL=$(shasum -a 256 "$DIR/$NAME" | cut -d' ' -f1); fi
if [ "$ACTUAL" != "$SHA" ]; then
  rm -f "$DIR/$NAME"
  echo "fetch-gmp: SHA-256 mismatch for $NAME: $ACTUAL" >&2
  exit 1
fi
