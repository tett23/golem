#!/bin/sh
# Makes the release archive golem-<tag>-<platform>.tar.gz
# (docs/adr/0004-binary-distribution-and-release.md): strips the
# executable (and signs it again ad hoc on macOS), writes LICENSE,
# THIRD_PARTY_LICENSES/ and BUILDINFO, and records the SHA-256.
#
#   package.sh TAG PLATFORM BINARY OUTDIR
#
# Environment:
#   GMP_SOURCE       gmp-<version>.tar.xz (see licenses.sh)
#   GMP_VERSION      the GMP linked into the executable
#   COMMIT           the commit of the build (default: git rev-parse HEAD)
#   BUILDINFO_EXTRA  a file whose lines are added to BUILDINFO
# Run it at the root of the repository after the build.
set -eu
[ $# -eq 4 ] || {
  echo "usage: package.sh TAG PLATFORM BINARY OUTDIR" >&2
  exit 2
}
TAG=$1
PLATFORM=$2
BINARY=$3
OUTDIR=$4
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
NAME=golem-$TAG-$PLATFORM
STAGE=$OUTDIR/$NAME
COMMIT=${COMMIT:-$(git -C "$ROOT" rev-parse HEAD)}

rm -rf "${STAGE:?}" "$OUTDIR/$NAME.tar.gz"
mkdir -p "$STAGE"
cp "$BINARY" "$STAGE/golem"
chmod 755 "$STAGE/golem"
BEFORE=$(wc -c <"$STAGE/golem" | tr -d ' ')
strip "$STAGE/golem"
if [ "$(uname -s)" = Darwin ]; then
  # strip changes the bytes the signature covers
  codesign --force --sign - "$STAGE/golem"
fi
AFTER=$(wc -c <"$STAGE/golem" | tr -d ' ')
echo "golem: $BEFORE bytes before strip, $AFTER bytes after"

cp "$ROOT/LICENSE" "$STAGE/LICENSE"
sh "$HERE/licenses.sh" "$ROOT/dist-newstyle/cache/plan.json" "$STAGE/THIRD_PARTY_LICENSES" "$TAG"

if command -v "ghc-9.10.3" >/dev/null 2>&1; then GHC=ghc-9.10.3; else GHC=ghc; fi
{
  echo "commit: $COMMIT"
  echo "tag: $TAG"
  echo "platform: $PLATFORM"
  echo "ghc: $("$GHC" --numeric-version)"
  echo "cabal-install: $(cabal --numeric-version)"
  echo "runner image: ${ImageOS:-unknown} ${ImageVersion:-unknown}"
  echo "wasmtime: $(cat "$ROOT/third_party/wasmtime/VERSION")"
  echo "gmp: ${GMP_VERSION:-unknown}"
  echo "size before strip: $BEFORE"
  echo "size after strip: $AFTER"
  if [ -n "${BUILDINFO_EXTRA:-}" ]; then cat "$BUILDINFO_EXTRA"; fi
} >"$STAGE/BUILDINFO"

tar -C "$OUTDIR" -czf "$OUTDIR/$NAME.tar.gz" "$NAME"
if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$OUTDIR/$NAME.tar.gz" | cut -d' ' -f1); else SUM=$(shasum -a 256 "$OUTDIR/$NAME.tar.gz" | cut -d' ' -f1); fi
printf '%s  %s\n' "$SUM" "$NAME.tar.gz" >"$OUTDIR/$NAME.tar.gz.sha256"
printf '%s\n' "${GMP_VERSION:-unknown}" >"$OUTDIR/gmp-version-$PLATFORM.txt"
rm -rf "${STAGE:?}"
