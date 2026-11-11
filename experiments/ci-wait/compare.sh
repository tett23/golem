#!/bin/sh
# Tests the checked-in waiter and the proposal; all times are simulated seconds.
set -eu
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
git show 706e5888fb1d63a53da68a0e7223b76f8441d2f9:scripts/visual/wait-pdfs.sh >"$tmp/baseline"
cat >"$tmp/bin/sleep" <<'FAKE'
#!/bin/sh
set -eu
n=$(( $(cat "$CLOCK") + $1 ))
if [ "$n" -ge 3600 ]; then echo 3600 >"$CLOCK"; exit 124; fi
echo "$n" >"$CLOCK"
FAKE
cat >"$tmp/bin/date" <<'FAKE'
#!/bin/sh
[ "$*" = '+%s' ] || exit 80
cat "$CLOCK"
FAKE
cat >"$tmp/bin/gh" <<'FAKE'
#!/bin/sh
set -eu
now=$(cat "$CLOCK")
case "$*" in
  *'/artifacts?name='*) api=artifact ;;
  *'/attempts/1/jobs'*) api=jobs ;;
  *) exit 81 ;;
esac
echo "$now $api" >>"$CALLS"
case " $* " in *' --include '*) headers=yes;; *) headers=no;; esac
err() {
  code=$1 message=$2; shift 2
  if [ "$headers" = yes ]; then
    printf 'HTTP/2.0 %s failure\n' "$code"
    for h in "$@"; do printf '%s\n' "$h"; done
    printf '\n{"message":"%s"}\n' "$message"
  fi
  echo "gh: $message (HTTP $code)" >&2
  exit 1
}
case "$SCENARIO/$api" in
  rate-primary/artifact) [ "$now" -ge 125 ] || err 403 'API rate limit exceeded for installation' 'X-Ratelimit-Remaining: 0' 'X-Ratelimit-Reset: 125';;
  rate-jobs/jobs) [ "$now" -ge 65 ] || err 429 'Too many requests' 'Retry-After: 65';;
  rate-headerless/artifact) [ "$now" -ge 170 ] || err 403 'You have exceeded a secondary rate limit';;
  permanent/artifact) err 403 'Resource not accessible by integration' 'X-Ratelimit-Reset: 1000';;
  credentials/artifact) err 401 'Bad credentials';;
  missing-run/artifact) err 404 'Not Found';;
  timeout/artifact) err 403 'API rate limit exceeded for installation' 'X-Ratelimit-Remaining: 0' 'X-Ratelimit-Reset: 4000';;
esac
if [ "$headers" = yes ]; then printf 'HTTP/2.0 200 OK\nContent-Type: application/json\n\n'; fi
if [ "$api" = artifact ]; then
  if [ "$now" -ge "$READY" ]; then echo 1; else echo 0; fi
else
  case "$SCENARIO" in
    no-job) echo 'other	completed';;
    two-jobs) printf 'producer\tin_progress\nci / producer\tin_progress\n';;
    race) echo "$READY" >"$CLOCK"; printf 'producer\tcompleted\n';;
    *) if [ "$now" -ge "$FAILED" ]; then status=completed; else status=in_progress; fi
       printf 'ci / producer\t%s\n' "$status";;
  esac
fi
FAKE
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" CLOCK="$tmp/clock" CALLS="$tmp/calls"
unset WAIT_INTERVAL
printf 'version\tcase\texit\tseconds\tartifacts\tjobs\tdelay\n'
fail=0
trial() {
  rule=$1 SCENARIO=$2 READY=$3 FAILED=$4; export SCENARIO READY FAILED
  for version in old new; do
    script="$tmp/baseline"; [ "$version" = old ] || script=scripts/visual/wait-pdfs.sh
    echo 0 >"$CLOCK"; : >"$CALLS"
    rc=0; sh "$script" 1 1 producer >"$tmp/out" 2>"$tmp/err" || rc=$?
    secs=$(cat "$CLOCK")
    a=$(awk '$2=="artifact"{n++} END{print n+0}' "$CALLS")
    j=$(awk '$2=="jobs"{n++} END{print n+0}' "$CALLS")
    delay=-
    if [ "$rc" = 0 ]; then delay=$((secs - READY)); fi
    printf '%s\t%s\t%d\t%d\t%d\t%d\t%s\n' "$version" "$rule/$SCENARIO" "$rc" "$secs" "$a" "$j" "$delay"
    [ "$version" = new ] || continue
    case "$SCENARIO" in
      present|quick|middle|slow|race) [ "$rc" = 0 ] && [ "$delay" -le 30 ] && [ "$delay" -ge 0 ];;
      failed) [ "$rc" = 1 ] && [ "$secs" -le 180 ] && grep -q 'completed without uploading' "$tmp/err";;
      no-job) [ "$rc" = 1 ] && [ "$secs" = 0 ] && grep -q 'has no job' "$tmp/err";;
      two-jobs) [ "$rc" = 1 ] && [ "$secs" = 0 ] && grep -q '2 jobs' "$tmp/err";;
      rate-primary) [ "$rc" = 0 ] && [ "$secs" -ge 125 ] && [ "$secs" -le 126 ] && [ "$a" = 2 ];;
      rate-jobs) [ "$rc" = 0 ] && [ "$secs" -ge 65 ] && [ "$j" = 2 ];;
      rate-headerless) [ "$rc" = 0 ] && [ "$secs" = 180 ] && [ "$a" = 3 ];;
      permanent|credentials|missing-run) [ "$rc" != 0 ] && [ "$secs" = 0 ] && [ "$a" = 1 ];;
      timeout) [ "$rc" = 124 ] && [ "$secs" = 3600 ] && [ "$a" = 1 ];;
    esac || { echo "failed $rule/$SCENARIO" >&2; cat "$tmp/err" >&2; fail=1; }
    if [ "$SCENARIO" = slow ] && [ "$((a + j))" -gt 85 ]; then echo 'failed W5/request budget' >&2; fail=1; fi
  done
}
trial W1 present 0 9999
trial W5 quick 1 9999
trial W5 middle 301 9999
trial W5 slow 1801 9999
trial W2 race 1 9999
trial W2 failed 9999 61
trial W2 no-job 9999 9999
trial W2 two-jobs 9999 9999
trial W3 rate-primary 120 9999
trial W3 rate-jobs 62 9999
trial W3 rate-headerless 120 9999
trial W4 permanent 9999 9999
trial W4 credentials 9999 9999
trial W4 missing-run 9999 9999
trial W6 timeout 9999 9999
exit "$fail"
