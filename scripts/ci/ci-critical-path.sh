#!/bin/sh
# The time of the CI of a pull request (docs/adr ADR 0392): the median of
# the times of the last 20 successful runs of ci.yml for a pull request that
# did not skip the job build.
#
#   ci-critical-path.sh [--workflow FILE]              the runs read with gh
#   ci-critical-path.sh [--workflow FILE] JOBS.json... the runs of the files
#   ci-critical-path.sh [--workflow FILE] --needs      the needs of the jobs
#
# The time of a run is the longest path through the needs of its jobs, with
# no wait for a runner in it: the seconds t(j) of a job j are from its
# started_at to its completed_at, 0 for a job that was skipped (conclusion
# skipped) and for a job not in the run, and the longest of its runners
# for a job of a matrix (the jobs named j or "j (...)"). The end of a job is
# F(j) = t(j) + the largest F of its needs (0 for none), and the time of the
# run is F(ci). The needs are read from FILE, .github/workflows/ci.yml
# unless given, as they are when this runs.
#
# A run counts unless it has jobs of build and each of them was skipped (a
# change of documents only). The median of an even number of times is the
# mean of the two in the middle. The median is the last line of stdout; the
# time of each run is on stderr.
#
# Without files, the runs are read with gh, newest first, from the API of
# GH_REPO (tett23/golem unless given); fewer than 20 runs that count fail.
# A JOBS.json is the response of the API repos/REPO/actions/runs/ID/jobs,
# its pages joined into one {"jobs": [...]}.
#
# A recorded workflow_revision uses .github/workflows at that local Git
# commit, including all local callees. Online collection uses the actual
# workflow revision from local-call metadata or the changes job log.
# --graph writes the expanded graph as JSON; --needs stays unexpanded.
# --needs writes each job of FILE and its needs, "JOB: NEED NEED", one job
# a line, in the order of FILE.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
WORKFLOW=$HERE/../../.github/workflows/ci.yml
RUNS=20

usage() {
  echo "usage: ci-critical-path.sh [--workflow FILE] [--needs | --graph | JOBS.json...]" >&2
  exit 2
}

if [ "${1-}" = --workflow ]; then
  [ $# -ge 2 ] || usage
  WORKFLOW=$2
  shift 2
fi
[ -f "$WORKFLOW" ] || { echo "ci-critical-path: no workflow $WORKFLOW" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ci-critical-path: jq is needed" >&2; exit 1; }

# the needs of the jobs of the workflow, "JOB: NEED NEED", from the three
# forms of needs: a word, a list in brackets, and the lines of a list
needs() {
  awk '
    function flush() { if (job != "") print job ":" (deps == "" ? "" : " " deps) }
    function add(w) {
      gsub(/["\047[:space:]]/, "", w)
      if (w != "") deps = (deps == "" ? w : deps " " w)
    }
    { sub(/[[:space:]]+#.*$/, "") }
    /^[^[:space:]#]/ { injobs = ($0 ~ /^jobs:[[:space:]]*$/); list = 0; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ {
      flush(); job = $0; sub(/^  /, "", job); sub(/:.*/, "", job); deps = ""; list = 0; next
    }
    /^    needs:/ {
      v = $0; sub(/^    needs:[[:space:]]*/, "", v)
      if (v == "") { list = 1; next }
      gsub(/[][]/, "", v)
      n = split(v, w, ",")
      for (i = 1; i <= n; i++) add(w[i])
      list = 0; next
    }
    list && /^      - / { v = $0; sub(/^      - /, "", v); add(v); next }
    /^    [^ ]/ { list = 0 }
    END { flush() }
  ' "$WORKFLOW"
}

if [ "${1-}" = --needs ]; then
  [ $# -eq 1 ] || usage
  needs
  exit 0
fi

# The expanded graph has zero-duration entry/exit nodes for local calls.
if [ "${1-}" = --graph ]; then
  [ $# -eq 1 ] || usage
  GRAPH=$(sh "$HERE/ci-workflow-graph.sh" "$WORKFLOW")
  printf '%s\n' "$GRAPH" | jq -e 'has("ci")' >/dev/null || { echo "ci-critical-path: no job ci in $WORKFLOW" >&2; exit 1; }
  printf '%s\n' "$GRAPH"
  exit 0
fi

# time FILE: the time of the run of FILE, or nothing when it skipped build
time_of() {
  revision=$(jq -r '.workflow_revision // empty' "$1")
  if [ -z "$revision" ] && jq -e 'has("workflow_files")' "$1" >/dev/null; then
    echo 'ci-critical-path: saved workflow files require an execution revision' >&2
    return 1
  fi
  if [ -n "$revision" ]; then
    case "$revision" in *[!0-9a-f]*) echo "ci-critical-path: invalid workflow revision $revision" >&2; return 1 ;; esac
    [ "${#revision}" -eq 40 ] || { echo "ci-critical-path: invalid workflow revision $revision" >&2; return 1; }
    if jq -e 'has("workflow_files")' "$1" >/dev/null; then
      jq -e '.workflow_files | type=="object" and length>0 and all(to_entries[]; (.key|test("^[.]github/workflows/[A-Za-z0-9_.-]+[.]ya?ml$")) and (.value|type=="string"))' "$1" >/dev/null || { echo 'ci-critical-path: invalid saved workflow files' >&2; return 1; }
      source_dir=$(mktemp -d "$TMP/snapshot.XXXXXX")
      mkdir -p "$source_dir/.github/workflows"
      jq -r '.workflow_files|keys[]' "$1" | while IFS= read -r file; do
        jq -j --arg path "$file" '.workflow_files[$path]' "$1" >"$source_dir/$file"
      done
    else
      source_dir=$TMP/revisions/$revision
      if [ ! -d "$source_dir" ]; then
        mkdir -p "$source_dir"
        git -C "$HERE/../.." archive "$revision" .github/workflows >"$TMP/workflows.tar" || { echo "ci-critical-path: unreadable workflow revision $revision" >&2; return 1; }
        tar -xf "$TMP/workflows.tar" -C "$source_dir"
      fi
    fi
    GRAPH=$(sh "$HERE/ci-workflow-graph.sh" "$source_dir/.github/workflows/ci.yml") || return 1
  else
    if [ ! -f "$TMP/current-graph.json" ]; then
      sh "$HERE/ci-workflow-graph.sh" "$WORKFLOW" >"$TMP/current-graph.json" || return 1
    fi
    GRAPH=$(cat "$TMP/current-graph.json")
  fi
  printf '%s\n' "$GRAPH" | jq -e 'has("ci")' >/dev/null || { echo "ci-critical-path: no job ci in selected workflow" >&2; return 1; }

  jq -r --argjson g "$GRAPH" '
    def base: .name | split(" / ") | (.[-1] |= sub(" \\(.*$"; "")) | join(" / ");
    def secs: if .conclusion == "skipped" then 0
              elif .status != null and .status != "completed" then error("incomplete job: " + .name)
              else (.completed_at | fromdateiso8601) - (.started_at | fromdateiso8601) end;
    $g as $template
    | def caller($name): ($name|split(" / ")|map(sub(" \\(.*$";""))|join(" / ")+" / @entry") as $entry | $template|has($entry);
      ([.jobs[].name | split(" / ") as $parts
        | range(1; $parts|length) as $i
        | {plain:($parts[:$i]|map(sub(" \\(.*$"; ""))),real:$parts[:$i]}] | unique) as $prefixes
    | ($template | to_entries | map(
        .key as $key | ($key|split(" / ")) as $parts | $parts[:-1] as $parents
        | ($prefixes|map(select(.plain==$parents)|.real)|unique) as $matches
        | (if ($parents|length)==0 then [[]] elif ($matches|length)==0 then [$parents] else $matches end)[] as $realparents
        | {template:$key,real:($realparents+[$parts[-1]]|join(" / ")),parents:$parents,realparents:$realparents})) as $nodes
    | ($nodes|map(. as $n | {key:.real,value:[
        $template[$n.template][] as $dep | $nodes[] | select(.template==$dep) | . as $d
        | select(all(range(0;[($n.parents|length),($d.parents|length)]|min); . as $i
            | if $n.parents[:($i+1)]==$d.parents[:($i+1)] then $n.realparents[$i]==$d.realparents[$i] else true end))
        | .real]})|from_entries) as $g
    | [.jobs[] | select(.conclusion != "skipped") | base as $n | select(($g|has($n)|not) and (caller($n)|not)) | .name] as $unknown
    | if ($unknown|length)>0 then error("unmatched workflow jobs: "+($unknown|join(", "))) else . end
    | [.jobs[] | select(base == "build")] as $b
    | if ($b | length) > 0 and all($b[]; .conclusion == "skipped") then empty
      else
        (reduce .jobs[] as $j ({}; ($j | base) as $n | if caller($n) then . else .[$n] = ([.[$n] // 0, ($j | secs)] | max) end)) as $t
        | def f($j): ($t[$j] // 0) + ([($g[$j] // [])[] | f(.)] | max // 0);
          f("ci")
      end' "$1"
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/ci-critical-path.XXXXXX")
trap 'rm -rf "${TMP:?}"' EXIT
: >"$TMP/times"

if [ $# -gt 0 ]; then
  for f in "$@"; do
    t=$(time_of "$f")
    [ -z "$t" ] || { printf '%s\t%s\n' "$f" "$t" >&2; printf '%s\n' "$t" >>"$TMP/times"; }
  done
  [ -s "$TMP/times" ] || { echo "ci-critical-path: no run that ran build" >&2; exit 1; }
else
  REPO=${GH_REPO:-tett23/golem}
  found=0
  LIST=$(gh run list --repo "$REPO" --workflow ci.yml --event pull_request --status success --limit 200 --json databaseId --jq '.[].databaseId')
  for run in $LIST; do
    [ "$found" -lt "$RUNS" ] || break
    sh "$HERE/github-api-read.sh" --paginate "repos/$REPO/actions/runs/$run/jobs?per_page=100" |
      jq -s '{jobs: [.[].jobs[]]}' >"$TMP/$run.json"
    sh "$HERE/github-api-read.sh" "repos/$REPO/actions/runs/$run" >"$TMP/$run-metadata.json"
    code=0
    revision=$(sh "$HERE/ci-workflow-revision.sh" "$REPO" "$TMP/$run-metadata.json" 2>"$TMP/revision-error") || code=$?
    if [ "$code" = 2 ]; then
      job=$(jq -er '[.jobs[]|select(.name=="changes")|.id] | if length==1 then .[0] else error("no unique changes job") end' "$TMP/$run.json")
      sh "$HERE/github-api-read.sh" --allow-escape-sequences "repos/$REPO/actions/jobs/$job/logs" >"$TMP/$run-changes.log"
      revision=$(sh "$HERE/ci-workflow-revision.sh" "$REPO" "$TMP/$run-metadata.json" "$TMP/$run-changes.log")
    elif [ "$code" != 0 ]; then
      cat "$TMP/revision-error" >&2
      exit "$code"
    fi
    if ! git -C "$HERE/../.." cat-file -e "$revision^{commit}" 2>/dev/null; then
      origin_url=$(git -C "$HERE/../.." remote get-url origin)
      case "$origin_url" in
        "https://github.com/$REPO"|"https://github.com/$REPO.git"|"git@github.com:$REPO"|"git@github.com:$REPO.git"|"ssh://git@github.com/$REPO"|"ssh://git@github.com/$REPO.git") ;;
        *) echo 'ci-critical-path: requested repository differs from origin; fetch the execution revision first' >&2; exit 1 ;;
      esac
      GIT_TERMINAL_PROMPT=0 git -C "$HERE/../.." fetch --no-tags origin "$revision" >&2
    fi
    jq --arg revision "$revision" '. + {workflow_revision:$revision}' "$TMP/$run.json" >"$TMP/with-revision.json"
    mv "$TMP/with-revision.json" "$TMP/$run.json"
    t=$(time_of "$TMP/$run.json")
    [ -n "$t" ] || continue
    found=$((found + 1))
    printf '%s\t%s\n' "$run" "$t" >&2
    printf '%s\n' "$t" >>"$TMP/times"
  done
  [ "$found" -eq "$RUNS" ] || { echo "ci-critical-path: only $found runs that ran build found" >&2; exit 1; }
fi

sort -n "$TMP/times" | awk '
  { v[NR] = $1 }
  END { print (NR % 2 == 1) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2 }'
