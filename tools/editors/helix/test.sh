#!/bin/sh
# The test of the procedure of tools/editors/README.md for Helix
# (docs/adr/0231). CI (the editors job of ci.yml) and developers run the
# same script, from anywhere in the repository.
#
#   tools/editors/helix/test.sh
#
# Helix comes from its GitHub release into third_party/helix, pinned by its
# version and the SHA-256 of each archive, as tools/editors/fetch-nvim.sh
# does for Neovim. third_party/helix/VERSION holds the name of the archive
# and its SHA-256; when they are those of this script, nothing is fetched.
# The archive is kept in GOLEM_DOWNLOADS (third_party/downloads by
# default), which CI caches; scripts/ci/fetch-url.sh fetches it, with
# retries, only when the archive there is not of the SHA-256 below
# (docs/adr/0243).
# The archives are pinned for x86-64 Linux and arm64 macOS; another
# platform fails.
#
# In a temporary HOME, with HELIX_RUNTIME at the runtime/ of the archive:
#
# 1. the sh block of the section "### Helix" of the README runs, with
#    <editors> replaced by this directory;
# 2. its toml block is ~/.config/helix/languages.toml, after a line
#    use-grammars = { only = ["golem", "emet"] }: without it,
#    hx --grammar build builds every grammar of Helix too, whose sources
#    only hx --grammar fetch would fetch from their repositories;
# 3. hx --grammar build succeeds, and makes golem.so and emet.so;
# 4. hx --health golem and hx --health emet find the parser and the
#    highlight queries.
#
# hx --grammar build needs a C compiler (cc). The exit code is 1 when a
# check fails.
set -eu
[ $# -eq 0 ] || { echo "usage: helix/test.sh" >&2; exit 2; }
VERSION=25.07.1
DIR=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$DIR/../../.." && pwd)
EDITORS=$ROOT/tools/editors
case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) NAME=helix-$VERSION-x86_64-linux; SHA=3f08e63ecd388fff657ad39722f88bb03dcf326f1f2da2700d99e1dc40ab2e8b ;;
  Darwin-arm64) NAME=helix-$VERSION-aarch64-macos; SHA=00b1651b4fdbbe0a2ae981c8e76b858bd26a7c33f5b3583f3b6bb9137d54f1ff ;;
  *)
    echo "helix: no pinned archive of Helix $VERSION for $(uname -s)-$(uname -m)" >&2
    exit 1
    ;;
esac

WORK=$(mktemp -d "${TMPDIR:-/tmp}/golem-helix.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
DEST=$ROOT/third_party/helix
# removes only the directories of this script
remove() {
  case "$1" in
    */golem-helix.* | */third_party/helix) [ ! -e "$1" ] || find "$1" -depth -delete ;;
  esac
}
trap 'remove "$WORK"' EXIT

# ---- Helix
if [ ! -f "$DEST/VERSION" ] || [ "$(cat "$DEST/VERSION")" != "$NAME.tar.xz $SHA" ] || [ ! -x "$DEST/hx" ]; then
  ARCHIVE=${GOLEM_DOWNLOADS:-$ROOT/third_party/downloads}/$NAME.tar.xz
  sh "$ROOT/scripts/ci/fetch-url.sh" "$ARCHIVE" "$SHA" "https://github.com/helix-editor/helix/releases/download/$VERSION/$NAME.tar.xz"
  mkdir "$WORK/x"
  tar -xJf "$ARCHIVE" -C "$WORK/x"
  if [ ! -x "$WORK/x/$NAME/hx" ] || [ ! -d "$WORK/x/$NAME/runtime" ]; then echo "helix: $NAME.tar.xz has no $NAME/hx or $NAME/runtime" >&2; exit 1; fi
  # the version is checked before anything is installed
  GOT=$("$WORK/x/$NAME/hx" --version 2>/dev/null | cut -d' ' -f1-2 || true)
  if [ "$GOT" != "helix $VERSION" ]; then echo "helix: $NAME/hx --version printed '$GOT', expected 'helix $VERSION'" >&2; exit 1; fi
  remove "$DEST"
  mkdir -p "$ROOT/third_party"
  mv "$WORK/x/$NAME" "$DEST"
  echo "$NAME.tar.xz $SHA" >"$DEST/VERSION"
fi

# the code block of the language $1 of the section "### Helix" of the README
readme_block() {
  awk -v want="$1" '
    /^```/ {
      if (inb) { inb = 0; if (insec && lang == want && !done) { printf "%s", buf; done = 1 } }
      else { inb = 1; lang = substr($0, 4); buf = "" }
      next
    }
    inb { buf = buf $0 "\n"; next }
    # a heading outside the code blocks ends the section
    /^#+ / { insec = ($0 == "### Helix") }
  ' "$EDITORS/README.md"
}

STATUS=0
fail() {
  echo "helix: $*" >&2
  STATUS=1
}

# ---- 1. and 2. the README, in a HOME of its own
mkdir "$WORK/home"
HOME=$WORK/home
export HOME
unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME XDG_STATE_HOME
HELIX_RUNTIME=$DEST/runtime
export HELIX_RUNTIME
readme_block sh | sed "s|<editors>|$EDITORS|g" >"$WORK/install.sh"
readme_block toml | sed "s|<editors>|$EDITORS|g" >"$WORK/languages.toml"
if [ ! -s "$WORK/install.sh" ] || [ ! -s "$WORK/languages.toml" ]; then
  echo "helix: no sh or toml block in the section Helix of tools/editors/README.md" >&2
  exit 1
fi
sh -eu "$WORK/install.sh" || { echo "helix: the sh block of tools/editors/README.md failed" >&2; exit 1; }
CONFIG=$HOME/.config/helix
mkdir -p "$CONFIG"
{
  echo 'use-grammars = { only = ["golem", "emet"] }'
  cat "$WORK/languages.toml"
} >"$CONFIG/languages.toml"

# ---- 3. the parsers
if "$DEST/hx" --grammar build; then
  for g in golem emet; do
    [ -f "$CONFIG/runtime/grammars/$g.so" ] || fail "hx --grammar build made no $CONFIG/runtime/grammars/$g.so"
  done
else
  fail "hx --grammar build failed"
fi

# ---- 4. what hx --health finds; without the colors of its output
for lang in golem emet; do
  "$DEST/hx" --health "$lang" | tr -d '\033' | sed 's/\[[0-9;]*m//g' >"$WORK/health-$lang"
  cat "$WORK/health-$lang"
  for item in 'Tree-sitter parser' 'Highlight queries'; do
    grep -q "^$item: ✓" "$WORK/health-$lang" || fail "hx --health $lang: no ✓ for $item"
  done
done
[ "$STATUS" -ne 0 ] || echo "helix: the grammars of golem and emet build and are found"
exit "$STATUS"
