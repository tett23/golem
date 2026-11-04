#!/bin/sh
# Checks that BINARY is linked with the wasmtime of scripts/fetch-wasmtime.sh
# (docs/adr/0156-wasmtime-49-0-5.md). libwasmtime.a holds one line
# "version: X.Y.Z", which strip keeps; the binary must have exactly one such
# line, and its value must be the version of fetch-wasmtime.sh.
#
#   check-wasmtime-linked.sh BINARY
set -eu
if [ $# -ne 1 ]; then echo "usage: check-wasmtime-linked.sh BINARY" >&2; exit 2; fi
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=$(sh "$HERE/fetch-wasmtime.sh" --expected | cut -d' ' -f1)
# wasmtime-v<version>-<platform>-c-api
EXPECTED=$(printf '%s\n' "$NAME" | sed -n 's/^wasmtime-v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)-.*-c-api$/\1/p')
if [ -z "$EXPECTED" ]; then echo "check-wasmtime-linked: no version in $NAME" >&2; exit 2; fi
FOUND=$(strings -a "$1" | grep -E '^version: [0-9]+\.[0-9]+\.[0-9]+$' || true)
if [ "$FOUND" = "version: $EXPECTED" ]; then exit 0; fi
{
  echo "check-wasmtime-linked: $1 is not linked with wasmtime $EXPECTED alone"
  echo "expected: version: $EXPECTED"
  if [ -z "$FOUND" ]; then echo "found: no line"; else printf '%s\n' "$FOUND" | sed 's/^/found: /'; fi
} >&2
exit 1
