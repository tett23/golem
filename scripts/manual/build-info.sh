#!/bin/sh
# Writes PROJECT/common/build-info.gm, which the colophon of a manual
# imports: the edition and the commit it is built from
# (docs/adr/0024-manual-audiences-and-policy.md).
#
#   build-info.sh PROJECT     PROJECT is manual or manual-dev (a folder)
#
# edition is the tag of the commit that starts with v, or else the content
# of VERSION (in the folder that holds PROJECT, the root of the repository)
# followed by "の開発版". commit is the 40 hexadecimal digits of
# git rev-parse HEAD, followed by "（コミットしていない変更を含む）" when a
# tracked file has a change that is not committed.
#
# GOLEM_MANUAL_TAG and GOLEM_MANUAL_COMMIT, when set, are used instead of
# git, so that a manual can be built outside a Git repository. If the
# commit cannot be known, the exit code is 1 and no file is written: a
# sample whose edition is unknown is not handed out.
set -eu
[ $# -eq 1 ] || { echo "usage: build-info.sh PROJECT" >&2; exit 2; }
[ -d "$1" ] || { echo "build-info: no folder $1" >&2; exit 2; }
PROJECT=$(cd "$1" && pwd)
ROOT=$(dirname "$PROJECT")
ingit() { git -C "$PROJECT" "$@" 2>/dev/null; }

if [ -n "${GOLEM_MANUAL_COMMIT-}" ]; then
  COMMIT=$GOLEM_MANUAL_COMMIT
elif HASH=$(ingit rev-parse --verify -q HEAD) && [ -n "$HASH" ]; then
  COMMIT=$HASH
  if [ -n "$(ingit status --porcelain --untracked-files=no)" ]; then
    COMMIT="${COMMIT}（コミットしていない変更を含む）"
  fi
else
  echo "build-info: cannot read the commit of $PROJECT; set GOLEM_MANUAL_COMMIT (and GOLEM_MANUAL_TAG) to build it outside a Git repository" >&2
  exit 1
fi

if [ -n "${GOLEM_MANUAL_TAG-}" ]; then
  EDITION=$GOLEM_MANUAL_TAG
else
  EDITION=$( (ingit tag --points-at HEAD || true) | grep '^v' | LC_ALL=C sort | tail -n 1 || true)
  if [ -z "$EDITION" ]; then
    [ -f "$ROOT/VERSION" ] || { echo "build-info: no tag and no $ROOT/VERSION" >&2; exit 1; }
    EDITION="$(tr -d '[:space:]' <"$ROOT/VERSION") の開発版"
  fi
fi

mkdir -p "$PROJECT/common"
TMP=$(mktemp "$PROJECT/common/.build-info.XXXXXX")
trap 'rm -f "$TMP"' EXIT
{
  echo '%% scripts/manual/build-info.sh が書いたファイル。手で編集しない %%'
  printf '@set edition = "%s"\n' "$EDITION"
  printf '@set commit = "%s"\n' "$COMMIT"
} >"$TMP"
mv "$TMP" "$PROJECT/common/build-info.gm"
trap - EXIT
