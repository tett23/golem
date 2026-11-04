#!/bin/sh
# Builds the sample plugins into plugins/wasm/<name>.wasm (docs/adr/0106)
# with the toolchain of rust-toolchain.toml.
#
#   build.sh          build and copy every plugin to wasm/
#   build.sh --check  build, and fail when a wasm/*.wasm differs from the
#                     committed bytes or a plugin has no wasm/*.wasm
#
# A plugin is a directory with a Cargo.toml whose crate-type has "cdylib";
# its package name is the name of the directory. The paths of the sources
# are remapped, so the bytes do not depend on where the repository is.
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
CHECK=false
case ${1:-} in
  --check) CHECK=true ;;
  "") ;;
  *) echo "usage: build.sh [--check]" >&2; exit 2 ;;
esac
cd "$DIR"
CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}
RUSTFLAGS="--remap-path-prefix=$DIR=/golem/plugins --remap-path-prefix=$CARGO_HOME=/cargo"
export RUSTFLAGS
# the crates built for the host get ids that do not name the host (rustc-wrapper.sh)
RUSTC_WRAPPER="$DIR/rustc-wrapper.sh"
export RUSTC_WRAPPER
cargo build --release --locked --target wasm32-unknown-unknown
status=0
for toml in */Cargo.toml; do
  grep -q cdylib "$toml" || continue
  name=$(dirname "$toml")
  built=target/wasm32-unknown-unknown/release/$(printf '%s' "$name" | tr - _).wasm
  if $CHECK; then
    if ! cmp -s "$built" "wasm/$name.wasm"; then
      echo "build.sh: wasm/$name.wasm is not what the sources build; run plugins/build.sh and commit it" >&2
      status=1
    fi
  else
    cp "$built" "wasm/$name.wasm"
  fi
done
exit $status
