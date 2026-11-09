#!/bin/sh
# The tests of the editor grammars of .gm and .emet
# (docs/adr/0170-emet-editor-support.md). CI (the editors job of ci.yml) and
# developers run the same script, from anywhere in the repository.
#
#   tools/editors/test.sh
#
# 1. The executable of tree-sitter-cli is the one of the pinned release
#    (tree-sitter-cli.sha256; the npm package checks no hash).
# 2. The committed src/ of each tree-sitter grammar is what grammar.js
#    generates.
# 3. tree-sitter test: the syntax trees of test/corpus/ and the highlights
#    of test/highlight/ of each grammar.
# 4. vscode-tmgrammar-test: the scopes written under the lines of the
#    shared samples test/sample.gm and test/sample.emet.
# 5. node --test test/: on the same samples, the TextMate grammar and the
#    tree-sitter grammar give each element the same class.
# 6. Every .gm and .emet of modules/golem-driver/test/fixtures/, manual/
#    and manual-dev/ parses with tree-sitter without an ERROR or a MISSING
#    node. The .emet of manual/examples/emet/ are left out: they are the
#    mistakes the user manual shows, and golem-driver tests that each gives
#    its diagnostic (ManualEmetSpec).
#
# The first run installs the pinned packages (npm ci in tools/editors).
# tree-sitter needs a C compiler (cc) for the tests and the parses.
# The exit code is 1 when a check fails.
set -eu
ROOT=$(git rev-parse --show-toplevel)
cd "$ROOT/tools/editors"
TS=node_modules/tree-sitter-cli/tree-sitter
if [ ! -x "$TS" ] || [ ! -x node_modules/.bin/vscode-tmgrammar-test ]; then
  npm ci --no-fund --no-audit
fi

STATUS=0
fail() {
  echo "editors: $*" >&2
  STATUS=1
}

# ---- 1. the executable of tree-sitter
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) PLATFORM=linux-x64 ;;
  Darwin-arm64) PLATFORM=macos-arm64 ;;
  *)
    echo "editors: no pinned SHA-256 of tree-sitter for $(uname -s)-$(uname -m) in tree-sitter-cli.sha256" >&2
    exit 1
    ;;
esac
if command -v sha256sum >/dev/null 2>&1; then
  SUM=$(sha256sum "$TS" | cut -d' ' -f1)
else
  SUM=$(shasum -a 256 "$TS" | cut -d' ' -f1)
fi
WANT=$(awk -v p="$PLATFORM" '$2 == p { print $1 }' tree-sitter-cli.sha256)
if [ "$SUM" != "$WANT" ]; then
  echo "editors: $TS is not the pinned tree-sitter for $PLATFORM: $SUM, not $WANT" >&2
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/golem-editors.XXXXXX")
cleanup() {
  case "$WORK" in
    */golem-editors.*) find "$WORK" -depth -delete ;;
  esac
}
trap cleanup EXIT
mkdir "$WORK/parsers"
# tree-sitter warns without a directory of parsers; -p names each grammar
printf '{"parser-directories": ["%s"]}\n' "$WORK/parsers" >"$WORK/config.json"
TS="$PWD/$TS"

for g in tree-sitter-golem tree-sitter-emet; do
  # ---- 2. the generated parser is up to date
  mkdir "$WORK/$g"
  cp "$g/grammar.js" "$g/tree-sitter.json" "$WORK/$g/"
  if (cd "$WORK/$g" && "$TS" generate >/dev/null); then
    cp "$g/src/scanner.c" "$WORK/$g/src/scanner.c"
    diff -r "$g/src" "$WORK/$g/src" >/dev/null ||
      fail "$g/src is not what grammar.js generates: run tree-sitter generate in tools/editors/$g"
  else
    fail "$g: tree-sitter generate failed"
  fi

  # ---- 3. the corpus and the highlights
  "$TS" test --config-path "$WORK/config.json" -p "$g" || fail "$g: tree-sitter test failed"
done

# ---- 4. the TextMate grammars
node_modules/.bin/vscode-tmgrammar-test -g textmate/golem.tmLanguage.json test/sample.gm ||
  fail "textmate: test/sample.gm failed"
node_modules/.bin/vscode-tmgrammar-test -g textmate/emet.tmLanguage.json test/sample.emet ||
  fail "textmate: test/sample.emet failed"

# ---- 5. the same classes in both grammars
node --test test/ || fail "the classes of the two grammars differ"

# ---- 6. the sources that Golem parses parse with tree-sitter
cd "$ROOT"
git ls-files -- 'modules/golem-driver/test/fixtures/*.gm' 'manual/*.gm' 'manual-dev/*.gm' >"$WORK/gm"
git ls-files -- 'modules/golem-driver/test/fixtures/*.emet' 'manual/*.emet' 'manual-dev/*.emet' |
  grep -v '^manual/examples/emet/' >"$WORK/emet"
for lang in gm emet; do
  case $lang in
    gm) g=tree-sitter-golem ;;
    emet) g=tree-sitter-emet ;;
  esac
  if [ ! -s "$WORK/$lang" ]; then
    fail "no .$lang to parse"
    continue
  fi
  n=$(wc -l <"$WORK/$lang" | tr -d ' ')
  if "$TS" parse -q --config-path "$WORK/config.json" -p "tools/editors/$g" --paths "$WORK/$lang"; then
    echo "editors: $n .$lang files parse without errors"
  else
    fail "$g: the files above have syntax errors"
  fi
done
exit "$STATUS"
