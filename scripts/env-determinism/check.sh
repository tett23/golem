#!/bin/sh
# Builds fixed inputs in a base environment and again with the environment
# changed, and compares the results (docs/adr/0029): the SHA-256 of every
# file under build/, the exit code, and the SHA-256 of stdout and of stderr
# of `golem build --format json`. Any difference fails the check.
#
#   GOLEM=/abs/path/to/golem sh scripts/env-determinism/check.sh [--quick] [--only NAME] [--input NAME]
#
#   --quick        leave out the large inputs (tempest, kanikosen, the ten
#                  public-domain books and the two manuals)
#   --only NAME    apply only the change NAME (tz-east, ..., caps-two, combined)
#   --input NAME   build only the input NAME; every change chosen is applied
#                  to it, a large one too
#
# Each change but combined is applied to the small inputs (exprs, sample,
# sample-pdf, diagnostics); combined, every change at once, to all inputs.
# caps-one and caps-two set GHCRTS=-N1 and -N2, the number of capabilities
# of golem (docs/adr/0050); the base gives no GHCRTS, so golem runs on every
# processor, as -with-rtsopts=-N says; combined uses -N2.
#
# GOLEM_REQUIRE_LOCALES=1 fails the check when a locale a change needs is not
# installed; otherwise the change is a SKIP. GOLEM_REQUIRE_FONTS=1 fails it
# when a font of a manual is missing; otherwise the manual is a SKIP.
# GOLEM_LOCALE_CANDIDATES_EUCJP and GOLEM_LOCALE_CANDIDATES_JA replace the
# names tried for the EUC-JP and the UTF-8 Japanese locale (for the tests).
#
# The root of the repository is found from where this script is.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
QUICK=0
ONLY=
INPUT=
while [ $# -gt 0 ]; do
  case "$1" in
    --quick) QUICK=1 ;;
    --only) shift; ONLY=${1-} ;;
    --input) shift; INPUT=${1-} ;;
    *) echo "usage: check.sh [--quick] [--only NAME] [--input NAME]" >&2; exit 2 ;;
  esac
  shift
done
GOLEM=${GOLEM-}
case "$GOLEM" in
  /*) [ -x "$GOLEM" ] || { echo "check: GOLEM is not an executable: $GOLEM" >&2; exit 2; } ;;
  *) echo "check: give the absolute path of golem in GOLEM" >&2; exit 2 ;;
esac

if command -v sha256sum >/dev/null 2>&1; then
  sha() { sha256sum "$1" | cut -d' ' -f1; }
else
  sha() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

WORK=$(mktemp -d)
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
mkdir -p "$WORK/home-a" "$WORK/home-b" "$WORK/xdg/cache" "$WORK/xdg/config" "$WORK/xdg/data" "$WORK/stage" "$WORK/lists"
FAILED=0
FIX=$ROOT/modules/golem-driver/test/fixtures
SMALL="exprs sample sample-pdf diagnostics"
BOOKS="merry-wives frogs snark elements-of-style nightmare-abbey koya-hijiri ichiaku-no-suna haru-to-shura taira-no-masakado ushiyama-hotel"
LARGE="tempest kanikosen $BOOKS manual manual-dev"
CHANGES="tz-east tz-west tz-unset locale-c locale-eucjp locale-ja locale-unset sde-zero sde-future home-other home-unset xdg path-empty umask root-path mtime-past mtime-future decoys caps-one caps-two combined"
# a name --only does not know would apply nothing and pass
if [ -n "$ONLY" ]; then
  case " $CHANGES " in
    *" $ONLY "*) ;;
    *) echo "check: unknown change $ONLY" >&2; exit 2 ;;
  esac
fi

# ------------------------------------------------------------------ locales

# the installed locale among the candidates, compared without case and '-'
norm() { tr 'A-Z' 'a-z' | tr -d '-'; }
# one awk for the whole list: macOS has some 500 locales, and a few
# processes for each of them took about 4 seconds a run there
INSTALLED=$(locale -a 2>/dev/null)
find_locale() {
  for c in $1; do
    n=$(printf '%s' "$c" | norm)
    l=$(printf '%s\n' "$INSTALLED" | awk -v n="$n" '{ t = tolower($0); gsub(/-/, "", t) } t == n { print; exit }')
    if [ -n "$l" ]; then
      printf '%s\n' "$l"
      return 0
    fi
  done
  return 1
}
EUCJP=$(find_locale "${GOLEM_LOCALE_CANDIDATES_EUCJP-ja_JP.eucJP ja_JP.EUC-JP ja_JP.eucjp ja_JP.ujis}") || EUCJP=
JA=$(find_locale "${GOLEM_LOCALE_CANDIDATES_JA-ja_JP.UTF-8 ja_JP.utf8}") || JA=
MISSING_LOCALES=

# ------------------------------------------------------------------ inputs

FONTS_MISSING=
# the fonts a manual needs: the files fetch-fonts.sh fetches
manual_fonts() {
  awk 'NF == 3 && $1 ~ /\.(otf|ttf)$/ { print $1 }' "$ROOT/scripts/manual/fetch-fonts.sh"
}

# stage NAME: a pristine copy of the input in $WORK/stage/NAME; 1 when it cannot be staged
stage() {
  d=$WORK/stage/$1
  [ -d "$d" ] && return 0
  case "$1" in
    exprs) cp -R "$ROOT/scripts/determinism" "$d" ;;
    sample) cp -R "$FIX/sample" "$d" ;;
    sample-pdf)
      cp -R "$FIX/sample" "$d"
      mkdir -p "$d/fonts"
      # Noto Serif JP has every character of the sample (docs/adr/0081)
      cp "$ROOT/modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf" "$d/fonts/ja.otf"
      cp "$ROOT/modules/golem-font/test/fonts/SourceSansPro-Regular.otf" "$d/fonts/latin.otf"
      cp "$ROOT/scripts/determinism/pdf-style.toml" "$d/style.toml"
      printf '\n[targets.pdf]\n' >>"$d/manifest.toml"
      ;;
    diagnostics) cp -R "$HERE/diagnostics" "$d" ;;
    tempest | kanikosen) cp -R "$FIX/$1" "$d" ;;
    merry-wives | frogs | snark | elements-of-style | nightmare-abbey)
      cp -R "$FIX/pd/$1" "$d"
      mkdir -p "$d/fonts"
      cp "$FIX/tempest/fonts/SourceSerifVariable-Roman.ttf" "$FIX/tempest/fonts/LICENSE-SourceSerif.txt" "$d/fonts/"
      ;;
    koya-hijiri | ichiaku-no-suna | haru-to-shura | taira-no-masakado | ushiyama-hotel)
      cp -R "$FIX/pd/$1" "$d"
      mkdir -p "$d/fonts"
      cp "$FIX/kanikosen/fonts/NotoSerifJP-Regular.otf" "$FIX/kanikosen/fonts/LICENSE-NotoSerifJP.txt" "$d/fonts/"
      ;;
    manual | manual-dev)
      missing=
      for f in $(manual_fonts); do
        [ -f "$ROOT/$1/fonts/$f" ] || missing="$missing $f"
      done
      if [ -n "$missing" ]; then
        case "$FONTS_MISSING" in *"$1:"*) ;; *) FONTS_MISSING="$FONTS_MISSING
  $1:$missing" ;; esac
        return 1
      fi
      # the colophon's build-info.gm, written once and copied to every change
      sh "$ROOT/scripts/manual/build-info.sh" "$ROOT/$1" >/dev/null || return 1
      mkdir -p "$d"
      for e in $(cd "$ROOT/$1" && ls -A); do
        [ "$e" = build ] || cp -R "$ROOT/$1/$e" "$d/$e"
      done
      ;;
    *) echo "check: unknown input $1" >&2; exit 2 ;;
  esac
  rm -rf "$d/build"
}

# ------------------------------------------------------------------ one build

# build CHANGE INPUT LIST: copies the staged input as CHANGE wants, builds it
# in the environment of CHANGE and writes the list of what came out to LIST;
# its variables start with b_, as sh has no local variables
build() {
  b_change=$1 b_input=$2 b_list=$3
  base=$WORK/run/$b_change
  dir=$base/$b_input
  [ "$b_change" = root-path ] || [ "$b_change" = combined ] && dir="$base/空白 と 日本語/深い/階層/$b_input"
  rm -rf "$base"
  mkdir -p "$dir"
  src=$WORK/stage/$b_input
  if [ "$b_change" = decoys ] || [ "$b_change" = combined ]; then
    # the entries in reverse order, and files nothing refers to
    for e in $(cd "$src" && ls -A | LC_ALL=C sort -r); do cp -R "$src/$e" "$dir/$e"; done
    printf '本文。\n' >"$dir/zz-unused.gm"
    [ -d "$dir/chapters" ] && printf '本文。\n' >"$dir/chapters/aa-unused.gm"
    [ -d "$dir/images" ] && printf 'not a png\n' >"$dir/images/unused.png"
    [ -d "$dir/fonts" ] && printf 'not a font\n' >"$dir/fonts/unused.otf"
  else
    cp -R "$src/." "$dir/"
  fi
  case "$b_change" in
    mtime-past | combined) find "$dir" -exec touch -t 197001020000 {} + ;;
    mtime-future) find "$dir" -exec touch -t 209912312359 {} + ;;
  esac
  # the base environment, then the change
  P=/usr/bin:/bin H=$WORK/home-a LNG=C.UTF-8 LCA= T=UTC SDE= XDG= U=022 RTS=
  case "$b_change" in
    tz-east) T=Pacific/Kiritimati ;;
    tz-west) T=Etc/GMT+12 ;;
    tz-unset) T=- ;;
    locale-c) LNG=C LCA=C ;;
    locale-eucjp) LCA=$EUCJP ;;
    locale-ja) LCA=$JA ;;
    locale-unset) LNG=- ;;
    sde-zero) SDE=0 ;;
    sde-future) SDE=4102444800 ;;
    home-other) H=$WORK/home-b ;;
    home-unset) H=- ;;
    xdg) XDG=$WORK/xdg ;;
    path-empty) P=/nonexistent ;;
    umask) U=077 ;;
    caps-one) RTS=-N1 ;;
    caps-two) RTS=-N2 ;;
    combined)
      T=Pacific/Kiritimati SDE=0 H=$WORK/home-b XDG=$WORK/xdg P=/nonexistent U=077 RTS=-N2
      LCA=${EUCJP:-C}
      ;;
  esac
  set -- PATH="$P"
  [ "$H" = - ] || set -- "$@" HOME="$H"
  [ "$LNG" = - ] || set -- "$@" LANG="$LNG"
  [ -z "$LCA" ] || set -- "$@" LC_ALL="$LCA"
  [ "$T" = - ] || set -- "$@" TZ="$T"
  [ -z "$SDE" ] || set -- "$@" SOURCE_DATE_EPOCH="$SDE"
  [ -z "$RTS" ] || set -- "$@" GHCRTS="$RTS"
  [ -z "$XDG" ] || set -- "$@" XDG_CACHE_HOME="$XDG/cache" XDG_CONFIG_HOME="$XDG/config" XDG_DATA_HOME="$XDG/data"
  code=0
  (cd "$dir" && umask "$U" && env -i "$@" "$GOLEM" build --format json >"$base/stdout" 2>"$base/stderr") || code=$?
  {
    if [ -d "$dir/build" ]; then
      (cd "$dir" && find build -type f | LC_ALL=C sort | while read -r f; do printf 'file %s %s\n' "$(sha "$f")" "$f"; done)
    fi
    printf 'exit %s\n' "$code"
    printf 'stdout %s\n' "$(sha "$base/stdout")"
    printf 'stderr %s\n' "$(sha "$base/stderr")"
  } >"$b_list"
  chmod -R u+rwX "$base" 2>/dev/null
  rm -rf "$base"
}

# ------------------------------------------------------------------ the changes

inputs_of() {
  if [ -n "$INPUT" ]; then
    echo "$INPUT"
  elif [ "$1" = combined ] && [ "$QUICK" = 0 ]; then
    echo "$SMALL $LARGE"
  else
    echo "$SMALL"
  fi
}

# whether a change can run here; records the missing locale otherwise
runnable() {
  case "$1" in
    locale-eucjp) [ -n "$EUCJP" ] || { MISSING_LOCALES="$MISSING_LOCALES $1"; return 1; } ;;
    locale-ja) [ -n "$JA" ] || { MISSING_LOCALES="$MISSING_LOCALES $1"; return 1; } ;;
    combined)
      if [ -z "$EUCJP" ]; then
        MISSING_LOCALES="$MISSING_LOCALES $1"
        [ "${GOLEM_REQUIRE_LOCALES-}" = 1 ] && return 1
        echo "note: combined uses LC_ALL=C, as no EUC-JP locale is installed"
      fi
      ;;
  esac
  return 0
}

SKIPPED_INPUTS=
for change in $CHANGES; do
  [ -z "$ONLY" ] || [ "$ONLY" = "$change" ] || continue
  if ! runnable "$change"; then
    echo "SKIP $change (no locale)"
    continue
  fi
  for input in $(inputs_of "$change"); do
    if ! stage "$input"; then
      case " $SKIPPED_INPUTS " in *" $input "*) ;; *) SKIPPED_INPUTS="$SKIPPED_INPUTS $input"; echo "SKIP $input (fonts missing)" ;; esac
      continue
    fi
    [ -f "$WORK/lists/base-$input" ] || build base "$input" "$WORK/lists/base-$input"
    build "$change" "$input" "$WORK/lists/$change-$input"
    if diff "$WORK/lists/base-$input" "$WORK/lists/$change-$input" >"$WORK/diff"; then
      echo "ok   $change $input"
    else
      FAILED=1
      echo "FAIL $change $input"
      # the files, the exit code or the output that differ
      grep '^[<>]' "$WORK/diff" | sed 's/^\([<>]\) \(file\) [0-9a-f]* /  \1 \2 /; s/^/  /'
    fi
  done
done

if [ -n "$MISSING_LOCALES" ]; then
  echo "locales not installed for:$MISSING_LOCALES (EUC-JP: ${GOLEM_LOCALE_CANDIDATES_EUCJP-ja_JP.eucJP ja_JP.EUC-JP ja_JP.eucjp ja_JP.ujis}; UTF-8: ${GOLEM_LOCALE_CANDIDATES_JA-ja_JP.UTF-8 ja_JP.utf8})"
  [ "${GOLEM_REQUIRE_LOCALES-}" = 1 ] && FAILED=1
fi
if [ -n "$FONTS_MISSING" ]; then
  echo "fonts missing (scripts/manual/fetch-fonts.sh fetches them):$FONTS_MISSING"
  [ "${GOLEM_REQUIRE_FONTS-}" = 1 ] && FAILED=1
fi
exit "$FAILED"
