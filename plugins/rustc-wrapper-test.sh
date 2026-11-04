#!/bin/sh
# Tests of rustc-wrapper.sh (docs/adr/0106, docs/adr/0138): a fake rustc
# writes its arguments one per line, and each case compares them with the
# arguments rustc-wrapper.sh should pass.
#
#   sh rustc-wrapper-test.sh
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/rustc" <<'FAKE'
#!/bin/sh
for a do printf '%s\n' "$a"; done
FAKE
chmod +x "$WORK/rustc"
export CARGO_PKG_NAME=pkg CARGO_PKG_VERSION=1.2.3
failures=0

# check <name> <expected arguments, one per line> -- <arguments of cargo>
check() {
  name=$1
  expected=$2
  shift 3
  actual=$(sh "$DIR/rustc-wrapper.sh" "$WORK/rustc" "$@")
  if [ "$actual" = "$expected" ]; then
    echo "ok: $name"
  else
    echo "FAIL: $name" >&2
    printf 'expected:\n%s\nactual:\n%s\n' "$expected" "$actual" >&2
    failures=$((failures + 1))
  fi
}

check "a crate for the host" \
"--crate-name
x
-C
metadata=pkg-1.2.3-host
-C
extra-filename=-abc" -- \
  --crate-name x -C metadata=abc -C extra-filename=-abc

check "a crate for the target" \
"-C
metadata=pkg-1.2.3-target
--target
wasm32-unknown-unknown" -- \
  -C metadata=abc --target wasm32-unknown-unknown

check "the features in the order of the arguments" \
"--cfg
feature=\"b\"
-C
metadata=pkg-1.2.3-host,feature=\"b\",feature=\"a\"
--cfg
feature=\"a\"" -- \
  --cfg 'feature="b"' -C metadata=abc --cfg 'feature="a"'

check "the other arguments, with spaces, as they are" \
"src/lib.rs
--remap-path-prefix=/a b=/golem
-C
metadata=pkg-1.2.3-host
an argument  with spaces
--edition=2021" -- \
  src/lib.rs '--remap-path-prefix=/a b=/golem' -C metadata=abc 'an argument  with spaces' --edition=2021

if [ "$failures" -ne 0 ]; then
  echo "rustc-wrapper-test.sh: $failures case(s) failed" >&2
  exit 1
fi
