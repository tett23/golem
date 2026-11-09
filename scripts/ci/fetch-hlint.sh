#!/bin/sh
# Downloads the hlint 3.10 release for x86-64 Linux, checks its SHA-256 and
# installs it as $HOME/.local/bin/hlint, for the format job of CI
# (docs/adr/0009-ci-speed.md). hlint stays at 3.10, the version that
# README.md names. scripts/ci/fetch-url.sh fetches the archive, with
# retries, into GOLEM_DOWNLOADS (third_party/downloads by default), which
# the format job caches; an archive there of the SHA-256 below is not
# fetched again (docs/adr/0243).
set -eu
VERSION=3.10
# The SHA-256 of hlint-3.10-x86_64-linux.tar.gz. GitHub records no digest
# for the assets of this release, so it is taken from the archive itself.
SHA=ccabc8802a58154699a3583b8dddc5ea2e6d65753a62c45c0e80088ebb16b42b
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "hlint $VERSION is released for x86-64 Linux only, not $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
NAME=hlint-$VERSION
DEST=$HOME/.local/lib/$NAME
BIN=$HOME/.local/bin
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ARCHIVE=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/$NAME-x86_64-linux.tar.gz
sh "$ROOT/scripts/ci/fetch-url.sh" "$ARCHIVE" "$SHA" "https://github.com/ndmitchell/hlint/releases/download/v$VERSION/$NAME-x86_64-linux.tar.gz"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
mkdir -p "$TMP/x"
tar -xzf "$ARCHIVE" -C "$TMP/x"
rm -rf "${DEST:?}"
mkdir -p "$(dirname "$DEST")" "$BIN"
cp -R "$TMP/x/$NAME" "$DEST"
# hlint reads its default hints from data/hlint.yaml of the release
if [ -f "$DEST/data/hlint.yaml" ]; then
  printf '#!/bin/sh\nexec "%s/hlint" --datadir="%s/data" "$@"\n' "$DEST" "$DEST" >"$BIN/hlint"
  chmod +x "$BIN/hlint"
else
  ln -sf "$DEST/hlint" "$BIN/hlint"
fi
"$BIN/hlint" --version
