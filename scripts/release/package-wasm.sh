#!/bin/sh
# Makes the release archive golem-<tag>-wasm32-wasi.tar.gz of golem.wasm
# (docs/adr/0199): golem.wasm, LICENSE, THIRD_PARTY_LICENSES/ (licenses.sh
# --wasm) and README (the exports and the frames, scripts/wasm/README),
# made with --sort=name --mtime=@0 as the other archives of the release,
# and records its SHA-256 and the version of GMP.
#
#   package-wasm.sh TAG WASM PLAN_JSON OUTDIR
#
# PLAN_JSON is the plan of cabal.project.wasm (dist-wasm/cache/plan.json).
# Environment, passed to licenses.sh: GHC_VERSION and GHC_DOCDIR (of the
# wasm GHC), GMP_SOURCE, GMP_VERSION, SOURCE_REPOS (dist-wasm/src). TAR
# chooses the tar (default tar), which must take the options of GNU tar.
# Run it at the root of the repository after the build.
set -eu
[ $# -eq 4 ] || {
  echo "usage: package-wasm.sh TAG WASM PLAN_JSON OUTDIR" >&2
  exit 2
}
TAG=$1
WASM=$2
PLAN=$3
OUTDIR=$4
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
NAME=golem-$TAG-wasm32-wasi
STAGE=$OUTDIR/$NAME
[ -f "$WASM" ] || {
  echo "package-wasm: no such file: $WASM" >&2
  exit 1
}
# the magic number and the version 1 of the binary format of WebAssembly
[ "$(od -An -tx1 -N8 "$WASM" | tr -d ' \n')" = 0061736d01000000 ] || {
  echo "package-wasm: $WASM is not a WebAssembly module" >&2
  exit 1
}

rm -rf "${STAGE:?}" "$OUTDIR/$NAME.tar.gz"
mkdir -p "$STAGE"
cp "$WASM" "$STAGE/golem.wasm"
chmod 644 "$STAGE/golem.wasm"
cp "$ROOT/LICENSE" "$STAGE/LICENSE"
cp "$ROOT/scripts/wasm/README" "$STAGE/README"
SOURCE_REPOS=${SOURCE_REPOS:-$ROOT/dist-wasm/src} sh "$HERE/licenses.sh" --wasm "$PLAN" "$STAGE/THIRD_PARTY_LICENSES" "$TAG"

${TAR:-tar} --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -C "$OUTDIR" -cf "$OUTDIR/$NAME.tar" "$NAME"
gzip -n -f "$OUTDIR/$NAME.tar"
if command -v sha256sum >/dev/null 2>&1; then SUM=$(sha256sum "$OUTDIR/$NAME.tar.gz" | cut -d' ' -f1); else SUM=$(shasum -a 256 "$OUTDIR/$NAME.tar.gz" | cut -d' ' -f1); fi
printf '%s  %s\n' "$SUM" "$NAME.tar.gz" >"$OUTDIR/$NAME.tar.gz.sha256"
printf '%s\n' "${GMP_VERSION:-unknown}" >"$OUTDIR/gmp-version-wasm32-wasi.txt"
echo "golem.wasm: $(wc -c <"$STAGE/golem.wasm" | tr -d ' ') bytes; $NAME.tar.gz: $(wc -c <"$OUTDIR/$NAME.tar.gz" | tr -d ' ') bytes"
rm -rf "${STAGE:?}"
