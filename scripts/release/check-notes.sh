#!/bin/sh
# Checks the release notes the AI wrote (docs/adr/0004-binary-distribution-and-release.md,
# docs/adr/0044-release-workflow-hardening.md).
#
#   check-notes.sh NOTES LIST
#
# NOTES is the AI's output and LIST is the output of notes.sh. The notes
# pass when they have an English heading, no "## Unsorted", no bare
# "#123", a link to every pull request that LIST names, and every link
# starts with a prefix of allowed-links.txt. The links are those of
# [text](URL), reference links, bare URLs of any scheme, <URL> autolinks,
# www. autolinks and <a> tags; an http:// link fails even when the list
# names it. A target may start on the line after "](" or "<a", and a
# target with "&" or a backslash fails, since Markdown decodes character
# references and escapes in it. A failure is one line on stderr and the
# exit code is 1.
#
# Environment: ALLOWED_LINKS (the allow list, allowed-links.txt next to
# this script by default; for the tests).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO_URL=https://github.com/tett23/golem
ALLOWED=${ALLOWED_LINKS:-$HERE/allowed-links.txt}

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
[ -s "$ALLOWED" ] || fail "no allow list: $ALLOWED"
if grep -Evq '^https://[^ ]+/$' "$ALLOWED"; then
  fail "a line of $ALLOWED is not https://.../: $(grep -Ev '^https://[^ ]+/$' "$ALLOWED" | head -1)"
fi

grep -Eq '^##? [A-Z][A-Za-z ]*$' "$NOTES" || fail "no English heading"
if grep -Eq '^#+ *Unsorted' "$NOTES"; then fail "the Unsorted section is left"; fi

TMP=$(mktemp)
JOINED=$(mktemp)
trap 'rm -f "$TMP" "$JOINED"' EXIT
# the notes on one line: Markdown lets the target of [text]( and the
# attributes of an HTML tag start on the next line
tr '\n' ' ' <"$NOTES" >"$JOINED"

# the targets of the links, one per line
first_word() { sed -E 's/^[[:space:]]*//; s/[[:space:]].*//; s/^<//; s/>$//'; }
{
  grep -Eo '\]\([^)]*\)' "$JOINED" | sed -E 's/^\]\(//; s/\)$//' | first_word || true
  grep -E '^ {0,3}\[[^]]+\]:' "$NOTES" | sed -E 's/^ *\[[^]]*\]://' | first_word || true
  grep -Eo '<[A-Za-z][A-Za-z0-9+.-]*:[^ <>]*>' "$NOTES" | sed -E 's/^<//; s/>$//' || true
  grep -Eo "[A-Za-z][A-Za-z0-9+.-]*://[^][)( <>\"'\`]*" "$NOTES" || true
} >"$TMP"

# every <a> tag has an href, and the href is a target
grep -Eoi '<a([[:space:]][^>]*)?>' "$JOINED" | while IFS= read -r tag; do
  href=$(printf '%s\n' "$tag" | sed -En "s/.*[Hh][Rr][Ee][Ff][[:space:]]*=[[:space:]]*[\"']?([^\"' >]*).*/\\1/p")
  [ -n "$href" ] || fail "an HTML link with no href: $tag"
  printf '%s\n' "$href" >>"$TMP"
done || exit 1

if grep -Eq '(^|[^A-Za-z0-9./:-])www\.' "$NOTES"; then
  fail "a www. autolink: $(grep -E '(^|[^A-Za-z0-9./:-])www\.' "$NOTES" | head -1)"
fi

while IFS= read -r url; do
  case $url in
    http://* | HTTP://*) fail "an http link: $url" ;;
    *..* | *%2[Ee]*) fail "a link with a dot segment: $url" ;;
    # Markdown decodes character references and backslash escapes in a
    # target, so &#46; and \. can write a dot segment
    *\&* | *\\*) fail "a link with a character reference or a backslash: $url" ;;
  esac
  allowed=false
  while IFS= read -r prefix; do
    case $url in "$prefix"*) allowed=true ;; esac
  done <"$ALLOWED"
  [ "$allowed" = true ] || fail "a link that is not in allowed-links.txt: $url"
done <"$TMP"

if grep -Eq '(^|[^A-Za-z0-9/&])#[0-9]+' "$NOTES"; then
  REST=$(sed -E 's#\[[^]]*\]\([^)]*\)##g' "$NOTES")
  if printf '%s\n' "$REST" | grep -Eq '(^|[^A-Za-z0-9/&])#[0-9]+'; then
    fail "a relative reference to a pull request: $(printf '%s\n' "$REST" | grep -E '(^|[^A-Za-z0-9/&])#[0-9]+' | head -1)"
  fi
fi

for n in $(grep -Eo "$REPO_URL/pull/[0-9]+" "$LIST" | sed 's#.*/##' | sort -un); do
  grep -Eq "$REPO_URL/pull/$n([^0-9]|\$)" "$NOTES" || fail "pull request #$n is missing"
done
