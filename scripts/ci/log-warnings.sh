#!/bin/sh
# The warnings of the logs of CI that the list of allowed warnings does not
# allow (docs/adr/0245 section 5).
#
#   log-warnings.sh ALLOWED LOG ...
#
# A line of a LOG, without the time GitHub Actions writes before it
# (`2026-11-09T00:00:00.0000000Z `), is a warning when it
#   starts with ##[warning]
#   is of the form FILE.hs:LINE:COLUMN: warning: (GHC; .c, .cc, .cpp and .h
#     for the C compilers)
#   starts with awk: warning, gawk: warning, sed: warning, grep: warning,
#     find: warning or ld: warning
#   starts with Warning: [ (cabal)
#   has DeprecationWarning or ExperimentalWarning in it
#   starts with npm warn, in any case.
# Only the head of the line is matched, never a word inside it, so that the
# diagnostics of golem (FILE:LINE:COLUMN: warning[G03010]: ...) and the
# names of the tests are not warnings.
#
# ALLOWED has a line for each warning allowed, of three fields separated by
# a tab: an extended regular expression, matched with grep -E against the
# line without its time; why golem cannot fix it, in Japanese; and the URL
# of the upstream (an issue, a release note, a source). A line that starts
# with # is a comment, and an empty line is skipped.
#
# Each warning that no regular expression of ALLOWED matches is written to
# stdout as LOG:LINE: TEXT, in the order of the logs and of their lines; the
# exit code is 1 when one is written, else 0. An ALLOWED whose line has not
# three fields, or whose regular expression grep -E does not take, is exit
# code 2, and so is a missing file or a usage error.
set -eu
usage() { echo "usage: log-warnings.sh ALLOWED LOG ..." >&2; exit 2; }
[ $# -ge 2 ] || usage
ALLOWED=$1
shift
[ -f "$ALLOWED" ] || { echo "log-warnings.sh: no such file: $ALLOWED" >&2; exit 2; }
for log in "$@"; do
  [ -f "$log" ] || { echo "log-warnings.sh: no such file: $log" >&2; exit 2; }
done
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
TAB=$(printf '\t')

# the regular expressions, one a line; a line of the list that is not of
# three fields is written as its number
if ! awk -F "$TAB" '
  /^#/ || /^[ \t]*$/ { next }
  NF != 3 || $1 == "" || $2 == "" || $3 == "" { print "log-warnings.sh: " FILENAME ":" FNR ": not three fields separated by a tab" > "/dev/stderr"; bad = 1; next }
  { print $1 }
  END { exit bad }
' "$ALLOWED" >"$WORK/patterns"; then
  exit 2
fi
while IFS= read -r re; do
  code=0
  printf '' | grep -E -e "$re" >/dev/null 2>"$WORK/grep-err" || code=$?
  if [ "$code" -gt 1 ]; then
    echo "log-warnings.sh: $ALLOWED: grep -E does not take the regular expression: $re" >&2
    cat "$WORK/grep-err" >&2
    exit 2
  fi
done <"$WORK/patterns"

# the warnings of every log: where they are, and their text, line by line
: >"$WORK/where"
: >"$WORK/text"
for log in "$@"; do
  awk -v name="$log" -v where="$WORK/where" -v text="$WORK/text" '
    {
      line = $0
      sub(/\r$/, "", line)
      sub(/^\357\273\277/, "", line)
      sub(/^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9](\.[0-9]+)?Z /, "", line)
      if (line ~ /^##\[warning\]/ ||
          line ~ /^[^ :]+\.(hs|c|cc|cpp|h):[0-9]+:[0-9]+: warning:/ ||
          line ~ /^(awk|gawk|sed|grep|find|ld): warning/ ||
          line ~ /^Warning: \[/ ||
          index(line, "DeprecationWarning") > 0 || index(line, "ExperimentalWarning") > 0 ||
          tolower(substr(line, 1, 8)) == "npm warn") {
        print name ":" FNR ": " line >> where
        print line >> text
      }
    }
  ' "$log"
done

# the warnings no pattern allows, by their numbers in the list of warnings;
# with no pattern, every warning (grep -f of an empty file is not the same
# in every grep)
if [ -s "$WORK/patterns" ]; then
  grep -n -v -E -f "$WORK/patterns" "$WORK/text" | cut -d: -f1 >"$WORK/numbers" || :
else
  awk '{ print NR }' "$WORK/text" >"$WORK/numbers"
fi
if [ ! -s "$WORK/numbers" ]; then exit 0; fi
awk 'NR == FNR { keep[$1] = 1; next } FNR in keep' "$WORK/numbers" "$WORK/where"
exit 1
