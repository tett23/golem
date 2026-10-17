#!/bin/sh
# Runs a command in the background of a CI job, and waits for it in a later
# step (docs/adr/0037-ci-build-job-speedup.md). The build job installs qpdf
# and epubcheck this way while cabal builds.
#
#   bg.sh start NAME COMMAND [ARGUMENTS...]
#   bg.sh wait NAME
#
# start returns at once. The command reads no standard input; its standard
# output and standard error go to BG_DIR/NAME.log, and its exit code to
# BG_DIR/NAME.code when it finishes. wait waits for NAME.code, prints the
# log and exits with the code of the command; it does not limit the time
# itself (the step that calls it has timeout-minutes, and the command can
# be run under timeout). BG_DIR is $RUNNER_TEMP/bg by default.
set -eu
DIR=${BG_DIR:-${RUNNER_TEMP:-/tmp}/bg}
usage() {
  echo "usage: bg.sh start NAME COMMAND [ARGUMENTS...] | bg.sh wait NAME" >&2
  exit 2
}
[ $# -ge 2 ] || usage
ACTION=$1 NAME=$2
shift 2
case "$NAME" in '' | */* | .*) usage ;; esac
case "$ACTION" in
  start)
    [ $# -ge 1 ] || usage
    mkdir -p "$DIR"
    rm -f "$DIR/$NAME.code"
    : >"$DIR/$NAME.log"
    (
      CODE=0
      "$@" <"/dev/null" >"$DIR/$NAME.log" 2>&1 || CODE=$?
      echo "$CODE" >"$DIR/$NAME.code.tmp"
      mv "$DIR/$NAME.code.tmp" "$DIR/$NAME.code"
    ) </dev/null >/dev/null 2>&1 &
    ;;
  wait)
    [ $# -eq 0 ] || usage
    if [ ! -f "$DIR/$NAME.log" ]; then
      echo "bg.sh: $NAME was not started" >&2
      exit 2
    fi
    while [ ! -f "$DIR/$NAME.code" ]; do sleep 1; done
    cat "$DIR/$NAME.log"
    exit "$(cat "$DIR/$NAME.code")"
    ;;
  *) usage ;;
esac
