#!/bin/sh
# Downloads the hlint 3.10 release for x86-64 Linux, checks its SHA-256 and
# installs it as $HOME/.local/bin/hlint, for the format job of CI
# (docs/adr/0009-ci-speed.md). hlint stays at 3.10, the version that
# README.md names.
set -eu
VERSION=3.10
# The SHA-256 of hlint-3.10-x86_64-linux.tar.gz. GitHub records no digest
# for the assets of this release, so it is taken from the archive itself.
SHA=TODO
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "hlint $VERSION is released for x86-64 Linux only, not $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac
NAME=hlint-$VERSION
DEST=$HOME/.local/lib/$NAME
BIN=$HOME/.local/bin
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

curl -sSfL -o "$TMP/$NAME.tar.gz" "https://github.com/ndmitchell/hlint/releases/download/v$VERSION/$NAME-x86_64-linux.tar.gz"
ACTUAL=$(sha256sum "$TMP/$NAME.tar.gz" | cut -d' ' -f1)
if [ "$ACTUAL" != "$SHA" ]; then echo "SHA-256 mismatch for $NAME-x86_64-linux.tar.gz: $ACTUAL" >&2; exit 1; fi
mkdir -p "$TMP/x"
tar -xzf "$TMP/$NAME.tar.gz" -C "$TMP/x"
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
