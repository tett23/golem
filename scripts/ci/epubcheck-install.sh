#!/bin/sh
# Installs epubcheck from the zip of its release on GitHub (w3c/epubcheck),
# and runs it with the Java the runner already has, JAVA_HOME_17_X64
# (docs/adr/0062-epubcheck-from-release-with-cache.md). The build job runs
# it in the background with scripts/ci/bg.sh.
#
#   epubcheck-install.sh VERSION SHA256
#
# The zip is kept in EPUBCHECK_HOME/zip, which the build job caches by the
# version and the SHA-256: a zip there is not fetched again. Fetched or
# cached, a zip whose SHA-256 is not SHA256 fails, and nothing is installed.
# The jar is extracted to EPUBCHECK_HOME/epubcheck-VERSION, and
# EPUBCHECK_HOME/bin/epubcheck runs it. EPUBCHECK_HOME is
# $RUNNER_TEMP/epubcheck by default.
set -eu
[ $# -eq 2 ] || { echo "usage: epubcheck-install.sh VERSION SHA256" >&2; exit 2; }
VERSION=$1 SHA256=$2
HOME_DIR=${EPUBCHECK_HOME:-${RUNNER_TEMP:-/tmp}/epubcheck}
JAVA=${JAVA_HOME_17_X64:?JAVA_HOME_17_X64 is not set}/bin/java
NAME=epubcheck-$VERSION
ZIP=$HOME_DIR/zip/$NAME.zip
[ -x "$JAVA" ] || { echo "epubcheck-install.sh: no Java at $JAVA" >&2; exit 1; }

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

mkdir -p "$HOME_DIR/zip"
if [ -f "$ZIP" ]; then
  echo "epubcheck-install.sh: $ZIP from the cache"
  GOT=$(sha256 "$ZIP")
  if [ "$GOT" != "$SHA256" ]; then
    echo "epubcheck-install.sh: the SHA-256 of the cached $ZIP is $GOT, not $SHA256" >&2
    exit 1
  fi
else
  URL=https://github.com/w3c/epubcheck/releases/download/v$VERSION/$NAME.zip
  rm -f "$ZIP.tmp"
  curl -fsSL --connect-timeout 30 --retry 3 -o "$ZIP.tmp" "$URL"
  GOT=$(sha256 "$ZIP.tmp")
  if [ "$GOT" != "$SHA256" ]; then
    rm -f "$ZIP.tmp"
    echo "epubcheck-install.sh: the SHA-256 of $URL is $GOT, not $SHA256" >&2
    exit 1
  fi
  mv "$ZIP.tmp" "$ZIP"
fi

rm -rf "${HOME_DIR:?}/$NAME" "$HOME_DIR/unzip"
unzip -q "$ZIP" -d "$HOME_DIR/unzip"
[ -f "$HOME_DIR/unzip/$NAME/epubcheck.jar" ] || {
  echo "epubcheck-install.sh: $ZIP has no $NAME/epubcheck.jar" >&2
  exit 1
}
mv "$HOME_DIR/unzip/$NAME" "$HOME_DIR/$NAME"
rmdir "$HOME_DIR/unzip"
mkdir -p "$HOME_DIR/bin"
printf '#!/bin/sh\nexec "%s" -jar "%s" "$@"\n' "$JAVA" "$HOME_DIR/$NAME/epubcheck.jar" >"$HOME_DIR/bin/epubcheck.tmp"
chmod +x "$HOME_DIR/bin/epubcheck.tmp"
mv "$HOME_DIR/bin/epubcheck.tmp" "$HOME_DIR/bin/epubcheck"
"$HOME_DIR/bin/epubcheck" --version
