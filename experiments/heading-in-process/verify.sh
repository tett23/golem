#!/bin/sh
set -eu
: "${GOLEM_TEST:?absolute path to golem-cli-test}"
stash=$(mktemp -d)
trap 'rm -rf "$stash"' EXIT HUP INT TERM
cat > "$stash/golem" <<'SH'
#!/bin/sh
echo "$*" >> "$SPAWN_LOG"
exit 83
SH
chmod +x "$stash/golem"
: > "$stash/calls"
SPAWN_LOG="$stash/calls" PATH="$stash:$PATH" "$GOLEM_TEST" -p heading-limit -j1
count=$(wc -l < "$stash/calls" | tr -d ' ')
printf 'golem child processes=%s\n' "$count"
test "$count" -eq 0
