#!/bin/sh
# Tests of the scripts of the manual (docs/adr/0022-manual-as-typesetting-sample.md).
# Each test builds its input (a small manual, a Git repository) in a
# temporary directory; nothing here uses the network.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
FAILURES=0
COUNT=0

ok() { COUNT=$((COUNT + 1)); }
ng() {
  COUNT=$((COUNT + 1))
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
  if [ -s "$WORK/out" ]; then sed 's/^/  stdout: /' "$WORK/out"; fi
  if [ -s "$WORK/err" ]; then sed 's/^/  stderr: /' "$WORK/err"; fi
  return 0
}

# run CMD...: stdin from $WORK/in, stdout to $WORK/out, stderr to $WORK/err,
# the exit code to $CODE
run() {
  CODE=0
  "$@" <"$WORK/in" >"$WORK/out" 2>"$WORK/err" || CODE=$?
}

# expect NAME CODE: checks the exit code of the last run
expect() {
  if [ "$CODE" != "$2" ]; then
    ng "$1 (exit code $CODE, expected $2)"
    return 0
  fi
  ok
}

# err_has NAME TEXT: the stderr of the last run has TEXT
err_has() {
  if grep -qF -- "$2" "$WORK/err"; then ok; else ng "$1 (stderr has no '$2')"; fi
}

: >"$WORK/in"

# ---------------------------------------------------------------- check-headings.sh

M=$WORK/headings
# mkmanual MD CHAPTERS FILE=CONTENT...: a root with docs/manual.md (MD),
# manual/manifest.toml (chapters = CHAPTERS) and the chapter files
mkmanual() {
  rm -rf "${M:?}"
  mkdir -p "$M/docs" "$M/manual/chapters"
  printf '%s\n' "$1" >"$M/docs/manual.md"
  printf 'chapters = %s\n\n[metadata]\ntitle = "t"\n' "$2" >"$M/manual/manifest.toml"
  shift 2
  for fc in "$@"; do
    printf '%s\n' "${fc#*=}" >"$M/manual/${fc%%=*}"
  done
}
headings() { sh "$HERE/check-headings.sh" "$M"; }

MD='# はじめに

本文。

## 組版とは

### 細部

# 原稿の記法

## ルビ'
mkmanual "$MD" '["chapters/01.gm", "chapters/02.gm"]' \
  'chapters/01.gm=# はじめに

本文。

## 組版とは

### 細部' \
  'chapters/02.gm=# 原稿の記法

## ルビ'
run headings
expect "check-headings: the same headings" 0

mkmanual "$MD" '["chapters/01.gm", "chapters/02.gm"]' \
  'chapters/01.gm=# はじめに

## 組版とは

### 細部' \
  'chapters/02.gm=# 原稿の記法

## ルビを振る'
run headings
expect "check-headings: a different heading" 1
err_has "check-headings: the heading of docs/manual.md is named" "ルビ"
err_has "check-headings: the heading of manual/ is named" "ルビを振る"

mkmanual "$MD" '["chapters/01.gm", "chapters/02.gm"]' \
  'chapters/01.gm=# はじめに

## 組版とは

## 細部' \
  'chapters/02.gm=# 原稿の記法

## ルビ'
run headings
expect "check-headings: a different level" 1

mkmanual '# [組版]の基本

## 強調と圏点' '["chapters/01.gm"]' \
  'chapters/01.gm=# \[[ruby: 組/版 | くみ/はん]\]の基本

## [strong: 強調]と[kenten: 圏点]'
run headings
expect "check-headings: ruby, emphasis and escapes are left out" 0

mkmanual "$MD" '[
  "chapters/b.gm",
  "chapters/a.gm",
]' \
  'chapters/a.gm=# 原稿の記法

## ルビ' \
  'chapters/b.gm=# はじめに

## 組版とは

### 細部'
run headings
expect "check-headings: the order of manifest.toml, not of the file names" 0

mkmanual '# はじめに

```toml
# 設定
[page]
```

## 組版とは' '["chapters/01.gm"]' \
  'chapters/01.gm=# はじめに

```toml
# 設定
[page]
```

## 組版とは'
run headings
expect "check-headings: # in a code block is not a heading" 0

mkmanual '# はじめに

```
# 設定
```' '["chapters/01.gm"]' \
  'chapters/01.gm=# はじめに

# 設定'
run headings
expect "check-headings: a heading of manual/ against a code block" 1

# ---------------------------------------------------------------- check-updated.sh

G=$WORK/git
mkdir -p "$G"
git -C "$G" init -q -b main . 2>/dev/null
git -C "$G" config user.email test@example.com
git -C "$G" config user.name test
git -C "$G" config commit.gpgsign false
mkdir -p "$G/docs" "$G/modules"
echo m >"$G/docs/markup.md"
echo s >"$G/docs/specifications.md"
echo u >"$G/docs/manual.md"
echo h >"$G/modules/a.hs"
git -C "$G" add -A
git -C "$G" commit -q -m init
INIT=$(git -C "$G" rev-parse HEAD)

# branch NAME: a branch from the first commit of main, checked out
branch() {
  git -C "$G" checkout -q -B "$1" "$INIT"
}
# commit FILE MESSAGE: appends a line to FILE and commits it with MESSAGE
commit() {
  echo x >>"$G/$1"
  git -C "$G" add -A
  git -C "$G" commit -q -m "$2"
}
updated() { (cd "$G" && sh "$HERE/check-updated.sh" "$@"); }

branch markup-only
commit docs/markup.md "Change the markup"
run updated "$INIT" markup-only
expect "check-updated: the markup without the manual" 1
err_has "check-updated: the changed file is named" "docs/markup.md"

branch both
commit docs/markup.md "Change the markup"
commit docs/manual.md "Update the manual"
run updated "$INIT" both
expect "check-updated: the markup and the manual in two commits" 0

branch trailer
commit docs/specifications.md "List a v2 item

Manual: unchanged"
commit modules/a.hs "Change the code"
run updated "$INIT" trailer
expect "check-updated: the trailer Manual: unchanged" 0

branch not-trailer
commit docs/specifications.md "List a v2 item

Manual: unchanged

but this is not the end of the message."
run updated "$INIT" not-trailer
expect "check-updated: Manual: unchanged in the body" 1

branch code
commit modules/a.hs "Change the code"
run updated "$INIT" code
expect "check-updated: modules/ only" 0

branch late
commit modules/a.hs "Change the code"
git -C "$G" checkout -q main
commit docs/markup.md "Change the markup on main"
run updated main late
expect "check-updated: a change of main after the branch point" 0

# ---------------------------------------------------------------- .githooks/pre-push

ZERO=0000000000000000000000000000000000000000
git -C "$G" update-ref refs/remotes/origin/main "$(git -C "$G" rev-parse main)"
prepush() { (cd "$G" && sh "$ROOT/.githooks/pre-push" origin https://example.com/r.git); }
SHA=$(git -C "$G" rev-parse markup-only)
printf 'refs/heads/markup-only %s refs/heads/markup-only %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a branch without the manual" 1
SHA=$(git -C "$G" rev-parse both)
printf 'refs/heads/both %s refs/heads/both %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a branch with the manual" 0
SHA=$(git -C "$G" rev-parse markup-only)
printf 'refs/heads/markup-only %s refs/heads/main %s\n' "$SHA" "$ZERO" >"$WORK/in"
run prepush
expect "pre-push: a push to main" 0
printf '(delete) %s refs/heads/markup-only %s\n' "$ZERO" "$SHA" >"$WORK/in"
run prepush
expect "pre-push: the deletion of a branch" 0
: >"$WORK/in"

# ---------------------------------------------------------------- fetch-fonts.sh

F=$WORK/fonts
mkdir -p "$F"
echo broken >"$F/NotoSerifJP-Regular.otf"
fetch() { sh "$HERE/fetch-fonts.sh" "$F"; }
run fetch
expect "fetch-fonts: a file whose SHA-256 does not match" 1
if [ ! -e "$F/NotoSerifJP-Regular.otf" ]; then ok; else ng "fetch-fonts: the file is removed"; fi
err_has "fetch-fonts: the file is named" "NotoSerifJP-Regular.otf"

# ----------------------------------------------------------------
printf '%s tests, %s failures\n' "$COUNT" "$FAILURES"
[ "$FAILURES" -eq 0 ]
