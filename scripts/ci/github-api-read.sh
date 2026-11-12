#!/bin/sh
# Read gh api output atomically across pages, retrying explicit GitHub rate limits.
# The optional budget applies to this invocation; callers also bound the entire step.
set -eu
deadline=
if [ -n "${GITHUB_API_READ_SECONDS:-}" ]; then
  deadline=$(( $(date +%s) + GITHUB_API_READ_SECONDS ))
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# gh --include writes the headers to stdout for a failed request too.
# Retry the operation, including all pages, only for an identified rate
# limit. Discard any partial pages before returning the successful response.
api() {
  backoff=60
  while :; do
    if gh api "$@" --include >"$tmp/response" 2>"$tmp/error"; then
      awk '/^HTTP\/[0-9.]+ [0-9][0-9][0-9]([[:space:]]|$)/ {header=1; next}
           header && /^\r?$/ {header=0; next}
           !header {print}' "$tmp/response"
      return 0
    else
      code=$?
    fi
    cat "$tmp/error" >&2
    status=$(awk '/^HTTP\/[0-9.]+ / {status=$2} END {print status}' "$tmp/response")
    case "$status" in
      429) ;;
      403) grep -Eiq 'API rate limit exceeded|secondary rate limit' "$tmp/error" || return "$code" ;;
      *) return "$code" ;;
    esac
    # Retry-After is in seconds. X-RateLimit-Reset is in epoch seconds
    # and also appears on ordinary responses: use it only if exhausted.
    delay=$(awk -v now="$(date +%s)" -v fallback="$backoff" '
      /^HTTP\/[0-9.]+ / {headers=1; retry=reset=0; remaining=""; next}
      /^\r?$/ {headers=0}
      headers && $2 ~ /^[0-9]+\r?$/ {
        key=tolower($1)
        if (key=="retry-after:") retry=$2+0
        if (key=="x-ratelimit-remaining:") remaining=$2+0
        if (key=="x-ratelimit-reset:") reset=$2+0
      }
      END {
        delay=retry
        if (remaining=="0" && reset > 0 && reset >= now && reset-now+1 > delay) delay=reset-now+1
        printf "%.0f\n", (delay > 0 ? delay : fallback)
      }' "$tmp/response")
    if [ -n "${deadline:-}" ] && [ "$delay" -ge "$((deadline - $(date +%s)))" ]; then
      echo "GitHub API retry would reach the job-list deadline" >&2
      return 1
    fi
    echo "GitHub API rate limited; retrying in ${delay}s" >&2
    sleep "$delay" || return $?
    if [ -n "${deadline:-}" ] && [ "$(date +%s)" -ge "$deadline" ]; then return 1; fi
    backoff=$((backoff * 2))
    [ "$backoff" -le 600 ] || backoff=600
  done
}

api "$@"
