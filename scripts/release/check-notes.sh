#!/bin/sh
# Checks the release notes the AI wrote (docs/adr/0004-binary-distribution-and-release.md).
#
#   check-notes.sh NOTES LIST
#
# NOTES is the AI's output and LIST is the output of notes.sh. The notes
# pass when they have an English heading, no "## Unsorted", only absolute
# links that start with https://github.com/tett23/golem/, and a link to
# every pull request that LIST names. A failure is one line on stderr and
# the exit code is 1.
set -eu
REPO_URL=https://github.com/tett23/golem

fail() {
  printf 'check-notes: %s\n' "$*" >&2
  exit 1
}

[ $# -eq 2 ] || {
  echo "usage: check-notes.sh NOTES LIST" >&2
  exit 2
}
NOTES=$1
LIST=$2
[ -f "$NOTES" ] || fail "no such file: $NOTES"
[ -f "$LIST" ] || fail "no such file: $LIST"

grep -Eq '^##? [A-Z][A-Za-z ]*$' "$NOTES" || fail "no English heading"
if grep -Eq '^#+ *Unsorted' "$NOTES"; then fail "the Unsorted section is left"; fi

# Remove every [text](https://github.com/tett23/golem/...) and look at what is left.
REST=$(sed -E 's#\[[^]]*\]\(https://github\.com/tett23/golem/[^) ]*\)##g' "$NOTES")
if printf '%s\n' "$REST" | grep -Eq '\]\('; then
  fail "a link that does not start with $REPO_URL/: $(printf '%s\n' "$REST" | grep -E '\]\(' | head -1)"
fi
if printf '%s\n' "$REST" | grep -Eq '^ *\[[^]]+\]: *[^ ]'; then
  if printf '%s\n' "$REST" | grep -E '^ *\[[^]]+\]: *[^ ]' | grep -Evq "^ *\[[^]]+\]: *$REPO_URL/"; then
    fail "a reference link that does not start with $REPO_URL/"
  fi
fi
if printf '%s\n' "$REST" | grep -Eq '(^|[^A-Za-z0-9/&])#[0-9]+'; then
  fail "a relative reference to a pull request: $(printf '%s\n' "$REST" | grep -E '(^|[^A-Za-z0-9/&])#[0-9]+' | head -1)"
fi

for n in $(grep -Eo "$REPO_URL/pull/[0-9]+" "$LIST" | sed 's#.*/##' | sort -un); do
  grep -Eq "$REPO_URL/pull/$n([^0-9]|\$)" "$NOTES" || fail "pull request #$n is missing"
done
