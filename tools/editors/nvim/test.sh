#!/bin/sh
# The tests of golem lsp and the editor grammars in a headless Neovim
# (docs/adr/0231). CI (the editors-lsp job of ci.yml) and developers run
# the same script, from anywhere in the repository.
#
#   GOLEM=<golem> NVIM=<nvim> tools/editors/nvim/test.sh
#   GOLEM=<golem> NVIM=<nvim> tools/editors/nvim/test.sh --self-test
#   GOLEM=<golem> NVIM=<nvim> tools/editors/nvim/test.sh --theme
#
# GOLEM is the executable of golem, NVIM that of Neovim (nvim by default;
# tools/editors/fetch-nvim.sh fetches the pinned one). Every test of
# tests/ runs in a Neovim of its own,
#
#   $NVIM --headless --clean -u tools/editors/nvim/init.lua
#
# on a copy of modules/golem-lsp/test/fixtures/ in a temporary directory.
# --clean reads no configuration of whoever runs it. A failed test writes
# "nvim: <name> (<invariant>): FAILED: ..." and exits 1 (:cquit 1); the
# invariant is the number of the one of docs/adr/0231 the test checks
# (I1 to I5; readme has none).
#
# The test readme runs the procedure of tools/editors/README.md for Neovim
# without nvim-treesitter: the sh block of the section "### Neovim" compiles
# the parsers with cc into a temporary site directory, and its last lua
# block is the init.lua. The README and the test run the same code.
#
# --self-test runs every test with its one marked expectation inverted
# (GOLEM_NVIM_INVERT=1), and fails unless each of them exits 1 with its
# name: a test that passes inverted checks nothing.
#
# --theme runs the test whitespace alone without --clean, with the
# configuration of NVIM_APPNAME (nvim by default) and its color scheme.
# CI checks the default color scheme only.
#
# The exit code is 1 when a test fails.
set -eu
MODE=all
case ${1:-} in
  --self-test) MODE=self ;;
  --theme) MODE=theme ;;
  "") ;;
  *)
    echo "usage: test.sh [--self-test | --theme]" >&2
    exit 2
    ;;
esac
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
: "${GOLEM:?GOLEM is the executable of golem}"
NVIM=${NVIM:-nvim}
# GOLEM_NVIM_TESTS runs some of them only
TESTS=${GOLEM_NVIM_TESTS:-"encoding columns notice whitespace completion readme"}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/golem-nvim.XXXXXX")
# without symbolic links (/var of macOS is /private/var): golem lsp takes
# the paths of the files relative to the root it is given
WORK=$(cd "$WORK" && pwd -P)
cleanup() {
  case "$WORK" in
    */golem-nvim.*) find "$WORK" -depth -delete ;;
  esac
}
trap cleanup EXIT

# the code block of the language $1 of the section "### Neovim" of the
# README: the first one with first, the last one with last
readme_block() {
  awk -v want="$1" -v which="$2" '
    /^```/ {
      if (inb) {
        inb = 0
        if (insec && lang == want) { n++; if (which == "first" && n == 1) first = buf; last = buf }
      } else { inb = 1; lang = substr($0, 4); buf = "" }
      next
    }
    inb { buf = buf $0 "\n"; next }
    # a heading outside the code blocks ends the section
    /^#+ / { insec = ($0 == "### Neovim") }
    END { printf "%s", (which == "first" ? first : last) }
  ' "$ROOT/tools/editors/README.md"
}

# runs the test $1 in $2, a new directory; $3 is 1 to invert it. The
# output of Neovim is in $2/out
run() {
  name=$1 w=$2 inv=$3
  mkdir -p "$w/state" "$w/cache"
  cp -R "$ROOT/modules/golem-lsp/test/fixtures/." "$w/"
  if [ "$name" = readme ]; then
    mkdir "$w/site"
    readme_block sh first | sed -e "s|<editors>|$ROOT/tools/editors|g" -e "s|^SITE=.*|SITE=$w/site|" >"$w/install.sh"
    readme_block lua last >"$w/site/init.lua"
    if [ ! -s "$w/install.sh" ] || [ ! -s "$w/site/init.lua" ]; then
      echo "nvim: readme: FAILED: no sh or lua block in the section Neovim of tools/editors/README.md" >"$w/out"
      return 1
    fi
    sh -eu "$w/install.sh" >"$w/out" 2>&1 || {
      echo "nvim: readme: FAILED: the sh block of tools/editors/README.md failed" >>"$w/out"
      return 1
    }
  fi
  if [ "$MODE" = theme ]; then
    set -- -c "luafile $DIR/init.lua"
  else
    set -- --clean -u "$DIR/init.lua"
  fi
  GOLEM_NVIM_TEST=$name GOLEM_NVIM_WORK=$w GOLEM_NVIM_INVERT=$inv GOLEM_NVIM_SITE=$w/site \
    XDG_STATE_HOME=$w/state XDG_CACHE_HOME=$w/cache \
    "$NVIM" --headless "$@" >>"$w/out" 2>&1 </dev/null
}

STATUS=0
case $MODE in
  all)
    for name in $TESTS; do
      if run "$name" "$WORK/$name" 0; then
        cat "$WORK/$name/out"
      else
        cat "$WORK/$name/out" >&2
        echo "nvim: $name failed" >&2
        STATUS=1
      fi
    done
    ;;
  self)
    for name in $TESTS; do
      if run "$name" "$WORK/$name" 1; then
        cat "$WORK/$name/out" >&2
        echo "nvim: self-test: $name passes with its expectation inverted" >&2
        STATUS=1
      else
        code=$?
        if [ "$code" -eq 1 ] && grep -Eq "^nvim: $name( \(I[0-9]+\))?: FAILED" "$WORK/$name/out"; then
          echo "nvim: self-test: $name fails with its expectation inverted"
        else
          cat "$WORK/$name/out" >&2
          echo "nvim: self-test: $name exited $code, not 1 with its name" >&2
          STATUS=1
        fi
      fi
    done
    ;;
  theme)
    if run whitespace "$WORK/whitespace" 0; then
      cat "$WORK/whitespace/out"
    else
      cat "$WORK/whitespace/out" >&2
      STATUS=1
    fi
    ;;
esac
exit "$STATUS"
