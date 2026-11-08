#!/bin/sh
# Runs the commands of the Alloy models of docs/*/models/*.als and compares
# whether each has a solution with a list of the same directory
# (docs/adr/0235, docs/adr/0242):
#
#   check.sh [-f LIST] [COMMAND ...]
#
# LIST is the name of the list in the directory of each model, expected.txt
# unless given (nightly.txt for the commands of the nightly check,
# .github/workflows/models-nightly.yml). A list has one command per line,
# its name and "found" or "none", and the scope to run it at when it is not
# that of the model (a line starting with # is a comment): the scope
# replaces the number of every "for <n> but" of a copy of the model.
# With COMMANDs, only those commands of the lists run; a COMMAND that no
# list has is an error of the usage (exit code 2), and nothing runs. Each
# command runs in its own process,
#
#   java -jar <Alloy jar> exec -q -n -t text -c <command> -o - <model>
#
# as many at a time as there are processors (JOBS to change it), and a
# solution is an output with a line "---Trace---". A command whose result is
# not that of the list, a command of the list that the model does not have,
# a run of Alloy that fails, and a model without the list are written on
# stderr, and the exit code is 1. Without COMMANDs, the commands of the
# model that the list does not have are not run; they are written on stdout.
#
# TIMEOUT is the limit of the real time of one command in seconds (none if
# empty or 0). A command past it is stopped and written on stdout as a
# time-out, neither found nor none; when there is a time-out and nothing
# else is wrong, the exit code is 3.
#
# The Alloy jar is the org.alloytools.alloy.dist.jar of the release 6.2.0 of
# AlloyTools/org.alloytools.alloy on GitHub, checked by its SHA-256 and kept
# in third_party/alloy/ (ALLOY_DIR to change it). ALLOY_JAR uses another
# jar as it is, unchecked; JAVA chooses the java (default java); GOLEM_ROOT
# the root with docs/ (this repository unless set).
set -eu
usage() {
  echo "usage: check.sh [-f LIST] [COMMAND ...]" >&2
  exit 2
}
LIST=expected.txt
while [ $# -gt 0 ]; do
  case $1 in
    -f) [ $# -ge 2 ] || usage; LIST=$2; shift 2 ;;
    --) shift; break ;;
    -*) usage ;;
    *) break ;;
  esac
done
case "$LIST" in "" | */* | .*) usage ;; esac
for c in "$@"; do
  case "$c" in "" | [!A-Za-z_]* | *[!A-Za-z0-9_]*) usage ;; esac
done
TIMEOUT=${TIMEOUT:-0}
case "$TIMEOUT" in "" | *[!0-9]*) usage ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=${GOLEM_ROOT:-$(cd "$HERE/../.." && pwd)}
JAVA=${JAVA:-java}
ALLOY_VERSION=6.2.0
ALLOY_SHA256=6b8c1cb5bc93bedfc7c61435c4e1ab6e688a242dc702a394628d9a9801edb78d
ALLOY_URL=https://github.com/AlloyTools/org.alloytools.alloy/releases/download/v$ALLOY_VERSION/org.alloytools.alloy.dist.jar

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
: >"$TMP/seen"
: >"$TMP/notrun"
n=0
for model in "$ROOT"/docs/*/models/*.als; do
  [ -f "$model" ] || continue
  dir=$(dirname "$model")
  rel=${model#"$ROOT"/}
  if [ ! -f "$dir/$LIST" ]; then
    fail "$rel has no $LIST"
    continue
  fi
  # the commands of the model: the lines "run <name>" and "check <name>"
  sed -n 's/^run[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p; s/^check[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$model" >"$TMP/commands"
  while read -r cmd want scope rest; do
    case "$cmd" in "" | \#*) continue ;; esac
    if [ $# -gt 0 ]; then
      case " $* " in *" $cmd "*) echo "$cmd" >>"$TMP/seen" ;; *) continue ;; esac
    fi
    case "$want" in
      found | none) ;;
      *) fail "${dir#"$ROOT"/}/$LIST: $cmd: not found nor none: $want"; continue ;;
    esac
    [ -z "$rest" ] || { fail "${dir#"$ROOT"/}/$LIST: $cmd: more than a command, its result and its scope"; continue; }
    # a scope: the model with "for <scope> but" in place of "for <n> but"
    run=$model
    if [ -n "$scope" ]; then
      case "$scope" in
        [1-9] | [1-9][0-9]) ;;
        *) fail "${dir#"$ROOT"/}/$LIST: $cmd: not a scope: $scope"; continue ;;
      esac
    fi
    if ! grep -qxF "$cmd" "$TMP/commands"; then
      fail "$rel has no command $cmd of $LIST"
      continue
    fi
    n=$((n + 1))
    if [ -n "$scope" ]; then
      run=$TMP/$n.als
      if ! grep -q ' for [0-9][0-9]* but ' "$model"; then
        fail "$rel has no \"for <n> but\" for the scope $scope of $cmd"
        continue
      fi
      sed "s/ for [0-9][0-9]* but / for $scope but /" "$model" >"$run"
    fi
    printf '%s %s %s\n' "$n" "$run" "$cmd" >>"$TMP/jobs"
    printf '%s %s %s %s\n' "$n" "$rel" "$cmd" "$want" >>"$TMP/expected"
  done <"$dir/$LIST"
  [ $# -eq 0 ] || continue
  awk '{ print $1 }' "$dir/$LIST" | grep -v '^#' | sort -u >"$TMP/listed"
  sort -u "$TMP/commands" | while IFS= read -r cmd; do
    grep -qxF "$cmd" "$TMP/listed" || echo "check: not in $LIST, not run: $rel $cmd"
  done >>"$TMP/notrun"
done
# a COMMAND that no list has: nothing runs
for c in "$@"; do
  grep -qxF "$c" "$TMP/seen" || {
    echo "check: $c is in no $LIST" >&2
    exit 2
  }
done
cat "$TMP/notrun"

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

# each command in its own java, JOBS at a time; the exit code of each in
# <number>.code, and <number>.timeout when it was stopped past TIMEOUT. The
# watcher looks once a second; it stops the java with TERM, and with KILL
# ten seconds later
export ALLOY_JAR JAVA TMP TIMEOUT
# shellcheck disable=SC2016
[ ! -s "$TMP/jobs" ] || xargs -P "$JOBS" -L 1 sh -c '
  "$JAVA" -jar "$ALLOY_JAR" exec -q -n -t text -c "$3" -o - "$2" >"$TMP/$1.out" 2>"$TMP/$1.err" &
  pid=$!
  w=
  if [ "$TIMEOUT" -gt 0 ]; then
    (
      s=0
      while [ "$s" -lt "$TIMEOUT" ] && kill -0 "$pid" 2>/dev/null; do sleep 1; s=$((s + 1)); done
      if kill -0 "$pid" 2>/dev/null; then
        : >"$TMP/$1.timeout"
        kill "$pid" 2>/dev/null
        s=0
        while [ "$s" -lt 10 ] && kill -0 "$pid" 2>/dev/null; do sleep 1; s=$((s + 1)); done
        kill -9 "$pid" 2>/dev/null
      fi
    ) </dev/null >/dev/null 2>&1 &
    w=$!
  fi
  code=0
  wait "$pid" || code=$?
  [ -z "$w" ] || wait "$w" || :
  echo "$code" >"$TMP/$1.code"' sh <"$TMP/jobs"

TIMEDOUT=0
while read -r i rel cmd want; do
  if [ -f "$TMP/$i.timeout" ]; then
    echo "check: time-out after $TIMEOUT s, not decided: $rel $cmd"
    TIMEDOUT=1
    continue
  fi
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
    fail "$rel $cmd: $got, but $LIST says $want"
  fi
done <"$TMP/expected"
[ "$FAILED" -eq 0 ] || exit 1
[ "$TIMEDOUT" -eq 0 ] || exit 3
