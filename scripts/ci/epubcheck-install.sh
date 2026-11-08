#!/bin/sh
# Installs epubcheck from the zip of its release on GitHub (w3c/epubcheck),
# and runs it with the Java the runner already has, JAVA_HOME_17_X64
# (docs/adr/0062-epubcheck-from-release-with-cache.md). The build job runs
# it in the background with scripts/ci/bg.sh.
#
#   epubcheck-install.sh VERSION SHA256
#
# The zip is kept in EPUBCHECK_HOME/zip, which the build job caches by the
# version and the SHA-256: a zip there of the SHA-256 SHA256 is not fetched
# again. scripts/ci/fetch-url.sh fetches it, with retries, when it is not
# there or has another SHA-256 (docs/adr/0243); a fetched zip whose SHA-256
# is not SHA256 fails, and nothing is installed.
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

[ ! -f "$ZIP" ] || echo "epubcheck-install.sh: $ZIP from the cache"
sh "$(dirname "$0")/fetch-url.sh" "$ZIP" "$SHA256" "https://github.com/w3c/epubcheck/releases/download/v$VERSION/$NAME.zip"

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
