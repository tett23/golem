#!/bin/sh
# Downloads a file pinned by its SHA-256, with retries, for the fetching
# scripts of CI and of the developers (docs/adr/0243):
#
#   fetch-url.sh FILE SHA256 URL [URL...]
#
# A FILE that is there with the SHA-256 SHA256 is used as it is, and nothing
# is fetched; so an archive restored from a cache is checked before it is
# used. Otherwise the URLs are tried in their order with curl into
# FILE.part, and the first that answers is the one taken. One attempt is a
# try of every URL; when all of them fail, the attempt failed, and the next
# one starts after a wait. FILE.part is moved to FILE only when its SHA-256
# is SHA256; the directory of FILE is made.
#
#   FETCH_ATTEMPTS  the number of attempts (3)
#   FETCH_WAITS     the seconds of the waits between them, separated by
#                   spaces ("10 30"); when there are fewer waits than
#                   needed, the last is used again
#   FETCH_MAX_TIME  the seconds that one curl may take (120)
#
# Each failed attempt writes one line on stderr per URL: the URL, the exit
# code of curl and the seconds of the next wait. Every failure of curl is
# retried (an HTTP error, a connection that died, a timeout, a name that
# did not resolve): the retries are not left to curl --retry, which retries
# only some of them. A file of another SHA-256 is not retried: the file of
# the upstream changed, which is not a transient error. Both that and the
# last failed attempt remove FILE.part, leave no FILE, and exit with 1.
set -eu
[ $# -ge 3 ] || {
  echo "usage: fetch-url.sh FILE SHA256 URL [URL...]" >&2
  exit 2
}
FILE=$1
SHA256=$2
shift 2
ATTEMPTS=${FETCH_ATTEMPTS:-3}
WAITS=${FETCH_WAITS-10 30}
MAX_TIME=${FETCH_MAX_TIME:-120}
case "$ATTEMPTS" in "" | *[!0-9]* | 0) echo "fetch-url: FETCH_ATTEMPTS is not a positive integer: $ATTEMPTS" >&2; exit 2 ;; esac
for w in $WAITS; do
  case "$w" in *[!0-9]*) echo "fetch-url: FETCH_WAITS is not integers separated by spaces: $WAITS" >&2; exit 2 ;; esac
done
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}
if [ -f "$FILE" ] && [ "$(sha256 "$FILE")" = "$SHA256" ]; then exit 0; fi
# a FILE of another SHA-256 is fetched again; it goes now, so that a failure
# leaves no FILE (I3, I4)
rm -f "$FILE"
mkdir -p "$(dirname "$FILE")"
PART=$FILE.part
# wait N: the seconds of the wait after the attempt N
wait_after() {
  n=$1 last=0 i=0
  for w in $WAITS; do
    i=$((i + 1))
    last=$w
    [ "$i" -lt "$n" ] || break
  done
  echo "$last"
}
attempt=1
while :; do
  [ "$attempt" -lt "$ATTEMPTS" ] && next=$(wait_after "$attempt") || next=none
  for url in "$@"; do
    rm -f "$PART"
    code=0
    curl --proto '=https' --tlsv1.2 -fsSL --connect-timeout 30 --max-time "$MAX_TIME" -o "$PART" "$url" || code=$?
    if [ "$code" = 0 ]; then
      actual=$(sha256 "$PART")
      if [ "$actual" != "$SHA256" ]; then
        rm -f "$PART"
        echo "fetch-url: SHA-256 mismatch for $url: $actual, expected $SHA256" >&2
        exit 1
      fi
      mv "$PART" "$FILE"
      exit 0
    fi
    rm -f "$PART"
    if [ "$next" = none ]; then
      echo "fetch-url: $url: curl exited with $code (attempt $attempt of $ATTEMPTS)" >&2
    else
      echo "fetch-url: $url: curl exited with $code (attempt $attempt of $ATTEMPTS); next in $next seconds" >&2
    fi
  done
  if [ "$next" = none ]; then
    echo "fetch-url: could not fetch $FILE after $ATTEMPTS attempts" >&2
    exit 1
  fi
  sleep "$next"
  attempt=$((attempt + 1))
done
