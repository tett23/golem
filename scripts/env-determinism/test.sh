#!/bin/sh
# Tests of check.sh (docs/adr/0029): fake golems that write what a change
# alters must make it fail, naming the change, and one that writes a fixed
# text must pass. The changes job of .github/workflows/ci.yml runs this.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
FAILURES=0
COUNT=0
NOLOCALE="xx_XX.nonexistent"

ng() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
  sed 's/^/  /' "$WORK/out"
}

# fake NAME BODY: a golem that runs BODY in the project, with /bin/sh only
fake() {
  {
    echo '#!/bin/sh'
    echo '/bin/mkdir -p build'
    printf '%s\n' "$2"
  } >"$WORK/$1"
  chmod +x "$WORK/$1"
}

# run [ENV...]: check.sh on the input exprs alone, to be quick; the exit code to $CODE
run() {
  CODE=0
  env "$@" sh "$CHECK" --quick --input exprs >"$WORK/out" 2>&1 || CODE=$?
}

# expect NAME CODE [WORD...]: the exit code, and each word in the output
expect() {
  COUNT=$((COUNT + 1))
  name=$1 code=$2
  shift 2
  if [ "$CODE" != "$code" ]; then
    ng "$name (exit code $CODE, expected $code)"
    return 0
  fi
  for w in "$@"; do
    if ! grep -qF -- "$w" "$WORK/out"; then
      ng "$name (no \"$w\" in the output)"
      return 0
    fi
  done
}

# the locales installed, as check.sh finds them
has_locale() {
  locale -a 2>/dev/null | tr 'A-Z' 'a-z' | tr -d '-' | grep -Fqx "$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -d '-')"
}

CHECK=$HERE/check.sh

fake fixed 'printf fixed >build/out.txt'
run GOLEM="$WORK/fixed"
expect "a fixed output passes" 0 "ok   decoys exprs" "ok   combined exprs"

fake tz 'printf "%s" "${TZ-unset}" >build/out.txt'
run GOLEM="$WORK/tz"
expect "TZ" 1 "FAIL tz-east" "FAIL tz-west" "FAIL tz-unset" "out.txt"

fake loc '/usr/bin/locale >build/out.txt 2>&1'
run GOLEM="$WORK/loc"
expect "locale" 1 "FAIL locale-c" "FAIL locale-unset"
for l in eucjp:ja_JP.eucJP ja:ja_JP.UTF-8; do
  if has_locale "${l#*:}"; then
    COUNT=$((COUNT + 1))
    grep -qF "FAIL locale-${l%%:*}" "$WORK/out" || ng "locale-${l%%:*} is applied"
  fi
done

fake sde 'printf "%s" "${SOURCE_DATE_EPOCH-unset}" >build/out.txt'
run GOLEM="$WORK/sde"
expect "SOURCE_DATE_EPOCH" 1 "FAIL sde-zero" "FAIL sde-future"

fake home 'printf "%s" "${HOME-unset}" >build/out.txt'
run GOLEM="$WORK/home"
expect "HOME" 1 "FAIL home-other" "FAIL home-unset"

fake xdg 'printf "%s" "${XDG_CACHE_HOME-unset}" >build/out.txt'
run GOLEM="$WORK/xdg"
expect "XDG" 1 "FAIL xdg"

fake path 'printf "%s" "$PATH" >build/out.txt'
run GOLEM="$WORK/path"
expect "PATH" 1 "FAIL path-empty"

fake umask 'umask >build/out.txt'
run GOLEM="$WORK/umask"
expect "umask" 1 "FAIL umask"

fake pwd 'pwd >build/out.txt'
run GOLEM="$WORK/pwd"
expect "the path of the project" 1 "FAIL root-path"

fake mtime '/bin/ls -l manifest.toml | /usr/bin/awk "{print \$6, \$7, \$8}" >build/out.txt'
run GOLEM="$WORK/mtime"
expect "the time of the files" 1 "FAIL mtime-past" "FAIL mtime-future"

fake ls '/bin/ls -A >build/out.txt'
run GOLEM="$WORK/ls"
expect "the files of the project" 1 "FAIL decoys"

# the number of capabilities (docs/adr/0050)
fake caps 'printf "%s" "${GHCRTS-unset}" >build/out.txt'
run GOLEM="$WORK/caps"
expect "GHCRTS" 1 "FAIL caps-one" "FAIL caps-two" "FAIL combined"
run GOLEM="$WORK/fixed"
expect "a fixed output passes the capabilities" 0 "ok   caps-one exprs" "ok   caps-two exprs"
for c in caps-one caps-two; do
  CODE=0
  env GOLEM="$WORK/fixed" sh "$CHECK" --only "$c" --input exprs >"$WORK/out" 2>&1 || CODE=$?
  expect "--only $c is a change" 0 "ok   $c exprs"
done
# the GHCRTS of the outer environment does not reach the base: were it
# passed, the base would be the same as caps-two
CODE=0
env GOLEM="$WORK/caps" GHCRTS=-N2 sh "$CHECK" --only caps-two --input exprs >"$WORK/out" 2>&1 || CODE=$?
expect "the outer GHCRTS does not reach golem" 1 "FAIL caps-two"

fake stderr 'printf "%s" "${TZ-unset}" >&2'
run GOLEM="$WORK/stderr"
expect "a difference in stderr" 1 "FAIL tz-east" "stderr"

fake code '[ "${TZ-}" = UTC ] || exit 1'
run GOLEM="$WORK/code"
expect "a difference in the exit code" 1 "FAIL tz-east" "exit"

fake extra '[ "${TZ-}" = UTC ] || printf x >build/extra.txt'
run GOLEM="$WORK/extra"
expect "an extra file" 1 "FAIL tz-east" "build/extra.txt"

fake missing '[ "${TZ-}" = UTC ] && printf x >build/only-in-base.txt; printf fixed >build/out.txt'
run GOLEM="$WORK/missing"
expect "a file missing under a change" 1 "FAIL tz-east" "build/only-in-base.txt"

# usage errors: exit code 2 before anything is built
CODE=0
env GOLEM=golem sh "$CHECK" --quick --input exprs >"$WORK/out" 2>&1 || CODE=$?
expect "a GOLEM that is not an absolute path" 2 "absolute path"
CODE=0
env GOLEM="$WORK/no-such-golem" sh "$CHECK" --quick --input exprs >"$WORK/out" 2>&1 || CODE=$?
expect "a GOLEM that is not an executable" 2 "not an executable"
CODE=0
env GOLEM="$WORK/fixed" sh "$CHECK" --no-such-option >"$WORK/out" 2>&1 || CODE=$?
expect "an unknown option" 2 "usage"
CODE=0
env GOLEM="$WORK/fixed" sh "$CHECK" --only tz-east --input no-such-input >"$WORK/out" 2>&1 || CODE=$?
expect "an unknown input" 2 "unknown input no-such-input"

# an unknown change for --only: an error, not a check that applies nothing and passes
CODE=0
env GOLEM="$WORK/fixed" sh "$CHECK" --only tz-esat --input exprs >"$WORK/out" 2>&1 || CODE=$?
expect "an unknown change for --only" 2 "unknown change tz-esat"

# locales that are not installed: a SKIP, or a failure with GOLEM_REQUIRE_LOCALES=1 only
for req in "" GOLEM_REQUIRE_LOCALES=0 GOLEM_REQUIRE_LOCALES=yes GOLEM_REQUIRE_EXTERNAL_TOOLS=1 GOLEM_REQUIRE_FONTS=1; do
  run GOLEM="$WORK/fixed" GOLEM_LOCALE_CANDIDATES_EUCJP="$NOLOCALE" GOLEM_LOCALE_CANDIDATES_JA="$NOLOCALE" $req
  expect "a missing locale is a SKIP ($req)" 0 "SKIP locale-eucjp" "SKIP locale-ja" "$NOLOCALE"
done
run GOLEM="$WORK/fixed" GOLEM_LOCALE_CANDIDATES_EUCJP="$NOLOCALE" GOLEM_LOCALE_CANDIDATES_JA="$NOLOCALE" GOLEM_REQUIRE_LOCALES=1
expect "a missing locale fails with GOLEM_REQUIRE_LOCALES=1" 1 "SKIP locale-eucjp" "SKIP combined" "$NOLOCALE"

# the manuals without their fonts: a tree of the inputs without manual/fonts and manual-dev/fonts
TREE=$WORK/tree
mkdir -p "$TREE/scripts" "$TREE/modules/golem-driver/test/fixtures" "$TREE/modules/golem-font/test" "$TREE/scripts/manual"
cp -R "$HERE" "$TREE/scripts/env-determinism"
cp -R "$ROOT/scripts/determinism" "$TREE/scripts/determinism"
cp "$ROOT/scripts/manual/fetch-fonts.sh" "$ROOT/scripts/manual/build-info.sh" "$TREE/scripts/manual/"
cp -R "$ROOT/modules/golem-font/test/fonts" "$TREE/modules/golem-font/test/fonts"
for f in sample tempest kanikosen pd; do cp -R "$ROOT/modules/golem-driver/test/fixtures/$f" "$TREE/modules/golem-driver/test/fixtures/$f"; done
for m in manual manual-dev; do
  mkdir -p "$TREE/$m"
  cp "$ROOT/$m/manifest.toml" "$TREE/$m/"
done
CHECK=$TREE/scripts/env-determinism/check.sh
# fullrun INPUT [ENV...]: check.sh on one large input
fullrun() {
  CODE=0
  i=$1
  shift
  env "$@" sh "$CHECK" --only combined --input "$i" >"$WORK/out" 2>&1 || CODE=$?
}
for m in manual manual-dev; do
  for req in "" GOLEM_REQUIRE_FONTS=0 GOLEM_REQUIRE_FONTS=yes GOLEM_REQUIRE_EXTERNAL_TOOLS=1 GOLEM_REQUIRE_LOCALES=1; do
    # combined needs the EUC-JP locale with GOLEM_REQUIRE_LOCALES=1
    if [ "$req" = GOLEM_REQUIRE_LOCALES=1 ] && ! has_locale ja_JP.eucJP; then continue; fi
    fullrun "$m" GOLEM="$WORK/fixed" $req
    expect "$m without fonts is a SKIP ($req)" 0 "SKIP $m (fonts missing)"
  done
  fullrun "$m" GOLEM="$WORK/fixed" GOLEM_REQUIRE_FONTS=1
  expect "$m without fonts fails with GOLEM_REQUIRE_FONTS=1" 1 "NotoSerifJP-Regular.otf" "$m:"
done
fullrun tempest GOLEM="$WORK/fixed"
expect "a large input is built with --input" 0 "ok   combined tempest"
# a missing locale does not fail with GOLEM_REQUIRE_FONTS=1 alone
CHECK=$HERE/check.sh
run GOLEM="$WORK/fixed" GOLEM_LOCALE_CANDIDATES_EUCJP="$NOLOCALE" GOLEM_LOCALE_CANDIDATES_JA="$NOLOCALE" GOLEM_REQUIRE_FONTS=1
expect "GOLEM_REQUIRE_FONTS=1 does not require the locales" 0 "SKIP locale-eucjp"

printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
