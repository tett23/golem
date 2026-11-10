#!/bin/sh
# Checks the WebContent left by timed-out Safari builds (docs/adr/0309 I1, I5).
# Only the dedicated GitHub-hosted macOS safari job may enumerate WebContent.
set -eu

if [ "${GITHUB_ACTIONS:-}" != true ] || [ "${GITHUB_JOB:-}" != safari ] ||
  [ "${RUNNER_ENVIRONMENT:-}" != github-hosted ] || [ "${RUNNER_OS:-}" != macOS ]; then
  echo 'browser-leftovers: requires the dedicated GitHub-hosted Safari job' >&2
  exit 2
fi

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
WORK=$(mktemp -d)
cleanup() {
  result=$?
  if [ "$result" -ne 0 ]; then
    for file in ok.log ok.err hang.log hang.err before after new; do
      if [ -f "$WORK/$file" ]; then
        printf '%s\n' "browser-leftovers: $file" >&2
        cat "$WORK/$file" >&2
      fi
    done
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

webcontent() {
  ps -A -ww -o pid= -o comm= >"$WORK/processes"
  awk '$2 ~ /(^|\/)com\.apple\.WebKit\.WebContent$/ { print $1 }' "$WORK/processes" | sort
}

assert_exits() {
  want=$1
  file=$2
  count=$(awk -v value="$want" '$1 == "exit" && $2 == value { n++ } END { print n+0 }' "$file")
  total=$(awk '$1 == "exit" { n++ } END { print n+0 }' "$file")
  if [ "$count" != 14 ] || [ "$total" != 14 ]; then
    printf 'browser-leftovers: I%s: expected 14 exit %s, got %s of %s\n' \
      "$(if [ "$want" = timeout ]; then echo 1; else echo 5; fi)" "$want" "$count" "$total" >&2
    return 1
  fi
}

# The module returns from _initialize but has no hs_init.
printf '\000\141\163\155\001\000\000\000\001\004\001\140\000\000\003\002\001\000\005\003\001\000\001\007\030\002\006\155\145\155\157\162\171\002\000\013\137\151\156\151\164\151\141\154\151\172\145\000\000\012\004\001\002\000\013' >"$WORK/ok.wasm"

# The module loops forever in _initialize.
printf '\000\141\163\155\001\000\000\000\001\004\001\140\000\000\003\002\001\000\005\003\001\000\001\007\030\002\006\155\145\155\157\162\171\002\000\013\137\151\156\151\164\151\141\154\151\172\145\000\000\012\011\001\007\000\003\100\014\000\013\013' >"$WORK/hang.wasm"

webcontent >"$WORK/before"
COMPARE_TIMEOUT=20 sh "$ROOT/scripts/wasm/compare.sh" --browser safari "$WORK/ok.wasm" >"$WORK/ok.log" 2>"$WORK/ok.err"
assert_exits 3 "$WORK/ok.log"
printf 'I5: 14 immediate failures exited 3\n'

COMPARE_TIMEOUT=20 sh "$ROOT/scripts/wasm/compare.sh" --browser safari "$WORK/hang.wasm" >"$WORK/hang.log" 2>"$WORK/hang.err"
assert_exits timeout "$WORK/hang.log"
sleep 35
webcontent >"$WORK/after"
comm -13 "$WORK/before" "$WORK/after" >"$WORK/new"
printf 'I1: WebContent before (%s):\n' "$(wc -l <"$WORK/before" | tr -d ' ')"
cat "$WORK/before"
printf 'I1: WebContent after (%s):\n' "$(wc -l <"$WORK/after" | tr -d ' ')"
cat "$WORK/after"
printf 'I1: new WebContent PIDs:\n'
cat "$WORK/new"
left=$(wc -l <"$WORK/new" | tr -d ' ')
printf 'I1: 14 timeouts, %s new WebContent processes after 35 seconds\n' "$left"
if [ "$left" -ge 14 ]; then
  echo 'browser-leftovers: I1: too many WebContent processes remain' >&2
  exit 1
fi
