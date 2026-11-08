#!/bin/sh
# Runs the commands of the Alloy models of docs/*/models/*.als and compares
# whether each has a solution with expected.txt of the same directory
# (docs/adr/0235):
#
#   check.sh
#
# expected.txt has one command per line, its name and "found" or "none"
# (a line starting with # is a comment). Each command runs in its own
# process,
#
#   java -jar <Alloy jar> exec -q -n -t text -c <command> -o - <model>
#
# as many at a time as there are processors (JOBS to change it), and a
# solution is an output with a line "---Trace---". A command whose result is
# not that of expected.txt, a command of expected.txt that the model does
# not have, a run of Alloy that fails, and a model without expected.txt are
# written on stderr, and the exit code is 1. The commands of the model that
# expected.txt does not list are not run; they are written on stdout.
#
# The Alloy jar is the org.alloytools.alloy.dist.jar of the release 6.2.0 of
# AlloyTools/org.alloytools.alloy on GitHub, checked by its SHA-256 and kept
# in third_party/alloy/ (ALLOY_DIR to change it). ALLOY_JAR uses another
# jar as it is, unchecked; JAVA chooses the java (default java); GOLEM_ROOT
# the root with docs/ (this repository unless set).
set -eu
[ $# -eq 0 ] || {
  echo "usage: check.sh" >&2
  exit 2
}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GOLEM_ROOT:-$(cd "$HERE/../.." && pwd)}
JAVA=${JAVA:-java}
ALLOY_VERSION=6.2.0
ALLOY_SHA256=6b8c1cb5bc93bedfc7c61435c4e1ab6e688a242dc702a394628d9a9801edb78d
ALLOY_URL=https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v$ALLOY_VERSION/org.alloytools.alloy.dist.jar

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi
}
if [ -z "${ALLOY_JAR-}" ]; then
  ALLOY_DIR=${ALLOY_DIR:-$ROOT/third_party/alloy}
  ALLOY_JAR=$ALLOY_DIR/alloy-$ALLOY_VERSION.jar
  if [ ! -f "$ALLOY_JAR" ] || [ "$(sha256 "$ALLOY_JAR")" != "$ALLOY_SHA256" ]; then
    mkdir -p "$ALLOY_DIR"
    curl --proto '=https' --tlsv1.2 -sSfL --retry 3 -o "$ALLOY_JAR.part" "$ALLOY_URL"
    ACTUAL=$(sha256 "$ALLOY_JAR.part")
    [ "$ACTUAL" = "$ALLOY_SHA256" ] || {
      rm -f "$ALLOY_JAR.part"
      echo "check: SHA-256 mismatch for $ALLOY_URL: $ACTUAL" >&2
      exit 1
    }
    mv "$ALLOY_JAR.part" "$ALLOY_JAR"
  fi
fi
[ -f "$ALLOY_JAR" ] || { echo "check: no such file: $ALLOY_JAR" >&2; exit 1; }
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)}

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
FAILED=0
fail() {
  echo "check: $1" >&2
  FAILED=1
}

# the jobs: one line per command, "<number> <model> <command>"
: >"$TMP/jobs"
: >"$TMP/expected"
n=0
for model in "$ROOT"/docs/*/models/*.als; do
  [ -f "$model" ] || continue
  dir=$(dirname "$model")
  rel=${model#"$ROOT"/}
  if [ ! -f "$dir/expected.txt" ]; then
    fail "$rel has no expected.txt"
    continue
  fi
  # the commands of the model: the lines "run <name>" and "check <name>"
  sed -n 's/^run[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p; s/^check[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$model" >"$TMP/commands"
  while read -r cmd want rest; do
    case "$cmd" in "" | \#*) continue ;; esac
    case "$want" in
      found | none) ;;
      *) fail "${dir#"$ROOT"/}/expected.txt: $cmd: not found nor none: $want"; continue ;;
    esac
    [ -z "$rest" ] || { fail "${dir#"$ROOT"/}/expected.txt: $cmd: more than a command and its result"; continue; }
    if ! grep -qxF "$cmd" "$TMP/commands"; then
      fail "$rel has no command $cmd of expected.txt"
      continue
    fi
    n=$((n + 1))
    printf '%s %s %s\n' "$n" "$model" "$cmd" >>"$TMP/jobs"
    printf '%s %s %s %s\n' "$n" "$rel" "$cmd" "$want" >>"$TMP/expected"
  done <"$dir/expected.txt"
  awk '{ print $1 }' "$dir/expected.txt" | grep -v '^#' | sort -u >"$TMP/listed"
  sort -u "$TMP/commands" | while IFS= read -r cmd; do
    grep -qxF "$cmd" "$TMP/listed" || echo "check: not in expected.txt, not run: $rel $cmd"
  done
done

# each command in its own java, JOBS at a time; the exit code of each in
# <number>.code
export ALLOY_JAR JAVA TMP
# shellcheck disable=SC2016
[ ! -s "$TMP/jobs" ] || xargs -P "$JOBS" -L 1 sh -c '
  "$JAVA" -jar "$ALLOY_JAR" exec -q -n -t text -c "$3" -o - "$2" >"$TMP/$1.out" 2>"$TMP/$1.err"
  echo $? >"$TMP/$1.code"' sh <"$TMP/jobs"

while read -r i rel cmd want; do
  code=$(cat "$TMP/$i.code" 2>/dev/null || echo none)
  if [ "$code" != 0 ]; then
    fail "$rel $cmd: Alloy failed (exit code $code)"
    sed 's/^/  /' "$TMP/$i.err" >&2
    continue
  fi
  if grep -qxF -- '---Trace---' "$TMP/$i.out"; then got=found; else got=none; fi
  if [ "$got" = "$want" ]; then
    echo "$rel $cmd $got"
  else
    fail "$rel $cmd: $got, but expected.txt says $want"
  fi
done <"$TMP/expected"
[ "$FAILED" -eq 0 ] || exit 1
