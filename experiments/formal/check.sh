#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
for area in Parser Position Length Pagination Shape; do
  experiments/formal/compile.sh -iexperiments/formal -imodules/golem-layout/test experiments/formal/"$area".hs
done
