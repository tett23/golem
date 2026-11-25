#!/bin/sh
# Downloads the artifact NAME of the workflow run RUN into DIR, in the jobs
# of ci.yml that wait for it with scripts/visual/wait-pdfs.sh
# (docs/adr/0442, docs/adr/0446).
#
#   download-artifact.sh RUN NAME DIR
#
# gh reads the repository from GH_REPO and the token from GH_TOKEN; the
# token needs actions: read. An attempt asks for the list of the artifacts
# NAME of RUN through github-api-read.sh, which waits out the rate limits
# without counting them, and downloads the zip of the newest one that has
# not expired (the greatest created_at: an artifact of an earlier attempt
# of the run stays in the list under the same name, docs/adr/0446). It
# unpacks the zip into DIR and exits 0 once the SHA-256 of the zip is the
# digest of the artifact.
#
# No artifact, no digest of the newest one, and a download that fails
# with 404 or a rate limit are tried again DOWNLOAD_INTERVAL seconds (5 by
# default) later, up to DOWNLOAD_ATTEMPTS attempts (12 by default); then
# it exits 1 with the last reason. Two or more newest artifacts of the
# same created_at, a zip whose SHA-256 is not the digest, and any other
# failure of the download (401 and 403 among them) exit 1 at once: trying
# again does not mend them.
set -eu
[ $# -eq 3 ] || { echo "usage: download-artifact.sh RUN NAME DIR" >&2; exit 2; }
RUN=$1 NAME=$2 DIR=$3
INTERVAL=${DOWNLOAD_INTERVAL:-5}
ATTEMPTS=${DOWNLOAD_ATTEMPTS:-12}
HERE=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1; }
fail() { echo "download-artifact: $*" >&2; exit 1; }

# attempt: one attempt; 0 when DIR has the artifact, 1 (with $reason) when
# it is to be tried again, and exits 1 itself when it is not
attempt() {
  # the lines "created_at<TAB>id<TAB>digest<TAB>url" of the artifacts
  # NAME that have not expired, newest first
  sh "$HERE/github-api-read.sh" "repos/{owner}/{repo}/actions/runs/$RUN/artifacts?name=$NAME" \
    --jq '.artifacts[] | select(.expired | not) | [.name, .created_at, (.id | tostring), (.digest // ""), .archive_download_url] | @tsv' >"$tmp/list"
  NAME=$NAME awk -F '\t' '$1 == ENVIRON["NAME"] { print $2 "\t" $3 "\t" $4 "\t" $5 }' "$tmp/list" | LC_ALL=C sort -r >"$tmp/artifacts"
  count=$(awk 'END { print NR }' "$tmp/artifacts")
  if [ "$count" = 0 ]; then
    reason="the run has no artifact $NAME"
    return 1
  fi
  # by awk: read with IFS of a tab would join the tabs around an empty digest
  field() { awk -F '\t' -v n="$1" 'NR == 1 { print $n }' "$tmp/artifacts"; }
  created=$(field 1) id=$(field 2) digest=$(field 3) url=$(field 4)
  newest=$(awk -F '\t' -v c="$created" '$1 == c' "$tmp/artifacts" | awk 'END { print NR }')
  if [ "$newest" != 1 ]; then
    fail "$NAME: $newest of the $count artifacts are the newest, created at $created"
  fi
  echo "download-artifact: $NAME: the artifact $id created at $created, the newest of $count" >&2
  if [ -z "$digest" ]; then
    reason="the artifact $id has no digest"
    return 1
  fi
  if ! gh api "$url" >"$tmp/zip" 2>"$tmp/error"; then
    cat "$tmp/error" >&2
    if grep -q '(HTTP 404)' "$tmp/error"; then
      reason="the download of the artifact $id is not found"
      return 1
    fi
    if grep -q '(HTTP 429)' "$tmp/error" || grep -Eiq 'API rate limit exceeded|secondary rate limit' "$tmp/error"; then
      reason="the download of the artifact $id is rate limited"
      return 1
    fi
    fail "$NAME: the download of the artifact $id failed"
  fi
  sum=sha256:$(sha256 "$tmp/zip")
  if [ "$sum" != "$digest" ]; then
    fail "$NAME: the zip of the artifact $id is $sum, not its digest $digest"
  fi
  mkdir -p "$DIR"
  unzip -q -o "$tmp/zip" -d "$DIR"
}

i=1
while :; do
  reason=
  if attempt; then exit 0; fi
  if [ "$i" -ge "$ATTEMPTS" ]; then
    fail "$NAME of the run $RUN is not downloaded after $ATTEMPTS attempts: $reason"
  fi
  echo "download-artifact: attempt $i of $ATTEMPTS: $reason; again in ${INTERVAL}s" >&2
  i=$((i + 1))
  sleep "$INTERVAL"
done
