#!/bin/sh
# Run the actual warning-check step with a scripted GitHub API and a virtual clock.
set -eu
cd "$(dirname "$0")/../.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir "$work/bin"
export PATH="$work/bin:$PATH" GITHUB_REPOSITORY=owner/repo RUN_ID=19 RUN_ATTEMPT=3
export GH_TOKEN=test GITHUB_API_URL=https://api.github.invalid
awk '/^      - name: No warning in the logs/ {step=1}
     step && /^        run: \|/ {body=1; next}
     body && /^          / {print substr($0, 11); next}
     body {exit}' .github/workflows/ci.yml >"$work/step"
cat >"$work/bin/date" <<'MOCK'
#!/bin/sh
cat "$RUNNER_TEMP/time"
MOCK
cat >"$work/bin/sleep" <<'MOCK'
#!/bin/sh
echo $(( $(cat "$RUNNER_TEMP/time") + $1 )) >"$RUNNER_TEMP/time"
MOCK
cat >"$work/bin/gh" <<'MOCK'
#!/bin/sh
set -eu
case " $* " in *" repos/owner/repo/actions/runs/19/attempts/3/jobs?per_page=100 "*) ;; *) exit 2;; esac
cat "$RUNNER_TEMP/time" >>"$RUNNER_TEMP/calls"
case " $* " in *' --include '*) headers=yes;; *) headers=no;; esac
page() {
  if [ "$headers" = yes ]; then printf 'HTTP/2.0 200 OK\r\n\r\n'; fi
  printf '%s\tbuild\n' "$1"
}
case "$CASE" in
  empty) exit 0;;
  one) page 1; exit 0;;
  recover) if [ "$(wc -l <"$RUNNER_TEMP/calls")" -gt 1 ]; then page 1; page 2; exit 0; fi;;
esac
page 1
if [ "$headers" = yes ]; then
  printf 'HTTP/2.0 403 Forbidden\r\nX-RateLimit-Remaining: 0\r\nX-RateLimit-Reset: %s\r\n\r\n' "$RESET"
fi
if [ "$CASE" = denied ]; then echo 'gh: permission denied' >&2
else echo 'gh: API rate limit exceeded for installation' >&2; fi
exit 1
MOCK
cat >"$work/bin/curl" <<'MOCK'
#!/bin/sh
set -eu
while [ "$1" != -o ]; do shift; done
log=$2
id=$(basename "$log" .log)
echo "$id" >>"$RUNNER_TEMP/logged"
case "$id" in
  1) : >"$log";;
  2) cp scripts/ci/testdata/log-warnings/two.txt "$log";;
  *) exit 2;;
esac
MOCK
cat >"$work/bin/timeout" <<'MOCK'
#!/bin/sh
set -eu
[ "$1 $2 $3" = "-k 10 3600" ]
shift 3
exec "$@"
MOCK
chmod +x "$work/bin/"*
check() {
  name=$1 CASE=$2 RESET=$3 expected=$4 calls=$5 logged=$6
  export CASE RESET RUNNER_TEMP="$work/$CASE-$RESET"
  mkdir "$RUNNER_TEMP"
  echo 100 >"$RUNNER_TEMP/time"
  : >"$RUNNER_TEMP/logged"
  status=0
  bash -e "$work/step" >"$RUNNER_TEMP/out" 2>&1 || status=$?
  if [ ! -f "$RUNNER_TEMP/calls" ]; then cat "$RUNNER_TEMP/out" >&2; return 1; fi
  actual_calls=$(paste -sd, "$RUNNER_TEMP/calls")
  actual_logs=$(paste -sd, "$RUNNER_TEMP/logged")
  if [ "$expected:$calls:$logged" != "$status:$actual_calls:$actual_logs" ]; then
    echo "$name: expected $expected:$calls:$logged, got $status:$actual_calls:$actual_logs" >&2
    cat "$RUNNER_TEMP/out" >&2
    return 1
  fi
}
check 'I1 one job' one 0 0 100 1
check 'I1 empty list' empty 0 1 100 ''
check 'I2 I3 retry all pages and detect the warning on page two' recover 110 1 100,111 1,2
check 'I3 I4 permission denied' denied 110 1 100 ''
check 'I4 exact deadline' limited 3699 1 100 ''
check 'I4 beyond deadline' limited 3700 1 100 ''
