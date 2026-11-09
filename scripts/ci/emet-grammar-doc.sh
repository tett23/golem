#!/bin/sh
# Checks that the grammar reference of Emet names the same rules as the
# grammar that Golem parses with: every rule of
# modules/golem-emet/grammar/Emet.hpeg (a line "Name <-" or "Name<p> <-")
# has its definition in docs/golem-emet/grammar.md (a line "Name ::=",
# "Name<p> ::=", "Name(nl) ::=" or "Name<w>(nl) ::="), once, and the
# document defines no rule that the grammar does not have. The bodies of
# the rules are not compared.
#
# A rule that is missing from either file, or that the document defines
# twice, goes to stderr, and the exit code is 1.
#
# GOLEM_ROOT sets the root of the repository (the tests use it).
set -u
LC_ALL=C
export LC_ALL
ROOT=${GOLEM_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}
GRAMMAR=$ROOT/modules/golem-emet/grammar/Emet.hpeg
DOC=$ROOT/docs/golem-emet/grammar.md

for f in "$GRAMMAR" "$DOC"; do
  [ -f "$f" ] || { echo "emet-grammar-doc: no ${f#"$ROOT"/}" >&2; exit 1; }
done
WORK=$(mktemp -d) || exit 2
trap 'rm -rf "${WORK:?}"' EXIT

sed -n -E 's/^([A-Z][A-Za-z0-9]*)(<[^>]*>)?[ ]*<-.*/\1/p' "$GRAMMAR" | sort -u >"$WORK/grammar"
sed -n -E 's/^([A-Z][A-Za-z0-9]*)(<[^>]*>)?(\([^)]*\))?[ ]+::=.*/\1/p' "$DOC" | sort >"$WORK/doc.all"
uniq "$WORK/doc.all" >"$WORK/doc"
uniq -d "$WORK/doc.all" >"$WORK/twice"

[ -s "$WORK/grammar" ] || { echo "emet-grammar-doc: no rule in Emet.hpeg" >&2; exit 1; }
comm -23 "$WORK/grammar" "$WORK/doc" >"$WORK/undocumented"
comm -13 "$WORK/grammar" "$WORK/doc" >"$WORK/unknown"

STATUS=0
report() {
  if [ -s "$1" ]; then
    echo "emet-grammar-doc: $2:" >&2
    sed 's/^/  /' "$1" >&2
    STATUS=1
  fi
}
report "$WORK/undocumented" "rules of Emet.hpeg that grammar.md does not define"
report "$WORK/unknown" "rules that grammar.md defines and Emet.hpeg does not have"
report "$WORK/twice" "rules that grammar.md defines twice"
[ "$STATUS" -ne 0 ] || echo "emet-grammar-doc: $(wc -l <"$WORK/grammar" | tr -d ' ') rules, each defined once in grammar.md"
exit "$STATUS"
