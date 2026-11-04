#!/bin/sh
# The rustc wrapper of build.sh (docs/adr/0106): cargo runs it as
# `rustc-wrapper.sh <rustc> <arguments>`.
#
# Cargo gives each crate a -C metadata hashed with, among others, the
# output of `rustc -vV`, which names the host. The ids of the crates then
# differ from host to host, and so does the order of the items a derive
# macro writes into a crate: a plugin that depends on derives (sou-ruby)
# had other bytes on Linux than on macOS. This replaces the value of
# -C metadata with the name and the version of the package, its features
# and whether it is built for the host or for the target, none of which
# depends on the host. The file names of the crates are left as cargo
# makes them.
set -eu
rustc=$1
shift
kind=host
features=
for a do
  case $a in
    --target) kind=target ;;
    feature=*) features="$features,$a" ;;
  esac
done
for a do
  shift
  case $a in
    metadata=*) a="metadata=${CARGO_PKG_NAME:-}-${CARGO_PKG_VERSION:-}-$kind$features" ;;
  esac
  set -- "$@" "$a"
done
exec "$rustc" "$@"
