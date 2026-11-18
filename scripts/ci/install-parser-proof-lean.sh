#!/bin/sh
set -eu
archive="$RUNNER_TEMP/lean.tar.zst"
sh scripts/ci/fetch-url.sh "$archive" 6d7e1c6f951009b7f277df996c196c9747c0b6b80b30b74e61acc894577a3106 https://github.com/leanprover/lean4/releases/download/v4.7.0/lean-4.7.0-linux.tar.zst
tar --zstd -xf "$archive" -C "$RUNNER_TEMP"
echo "LEAN=$RUNNER_TEMP/lean-4.7.0-linux/bin/lean" >> "$GITHUB_ENV"
