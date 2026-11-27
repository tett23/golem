#!/bin/sh
# Expand local reusable workflows (root ADR 0472). Each call has a zero-time
# entry and exit; ordinary jobs keep the names returned by the jobs API.
set -eu
[ "$#" = 1 ] || { echo 'usage: ci-workflow-graph.sh WORKFLOW' >&2; exit 2; }
workflow=$1
workflow=$(cd "$(dirname "$workflow")" && printf '%s/%s\n' "$PWD" "$(basename "$workflow")")
case "$workflow" in
  */.github/workflows/*) root=${workflow%/.github/workflows/*} ;;
  *) root=$(dirname "$workflow") ;;
esac
parse() {
  awk '
    function flush() { if (job != "") print job ":" deps "|" use }
    function add(v) { gsub(/["\047[:space:]]/, "", v); if (v != "") deps = deps (deps == "" ? "" : " ") v }
    { sub(/[[:space:]]+#.*$/, "") }
    /^[^[:space:]#]/ { injobs = ($0 ~ /^jobs:[[:space:]]*$/); list = 0; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:[[:space:]]*$/ { flush(); job=$0; sub(/^  /,"",job); sub(/:.*/,"",job); deps=""; use=""; list=0; next }
    /^    uses:/ { use=$0; sub(/^    uses:[[:space:]]*/,"",use); gsub(/["\047[:space:]]/,"",use); list=0; next }
    /^    needs:/ {
      v=$0; sub(/^    needs:[[:space:]]*/,"",v)
      if(v=="") { list=1; next }
      gsub(/[][]/,"",v); n=split(v,a,","); for(i=1;i<=n;i++) add(a[i]); list=0; next
    }
    list && /^      - / { v=$0; sub(/^      - /,"",v); add(v); next }
    /^    [^ ]/ { list=0 }
    END { flush() }
  ' "$1" | jq -Rsc 'split("\n")|map(select(length>0)|capture("^(?<job>[^:]+):(?<deps>[^|]*)\\|(?<uses>.*)$"))'
}
expand() (
  file=$1 prefix=$2 inherited=$3 stack=$4
  [ -f "$file" ] || { echo "ci-critical-path: unreadable workflow $file" >&2; exit 1; }
  case "|$stack|" in *"|$file|"*) echo "ci-critical-path: recursive workflow $file" >&2; exit 1 ;; esac
  data=$(parse "$file")
  [ "$(printf '%s' "$data" | jq length)" -gt 0 ] || { echo "ci-critical-path: no readable jobs in $file" >&2; exit 1; }
  printf '%s' "$data" | jq -c '.[]' | while IFS= read -r row; do
    job=$(printf '%s' "$row" | jq -r .job)
    use=$(printf '%s' "$row" | jq -r .uses)
    key=$prefix$job
    deps=$(printf '%s' "$row" | jq -c --arg p "$prefix" --argjson inherited "$inherited" '.deps|split(" ")|map(select(length>0)|$p+.)|if length==0 then $inherited else . end')
    if [ -z "$use" ]; then
      jq -cn --arg key "$key" --argjson value "$deps" '{key:$key,value:$value}'
    else
      case "$use" in
        ./.github/workflows/*.yml|./.github/workflows/*.yaml) ;;
        *) echo "ci-critical-path: unsupported workflow reference $use" >&2; exit 1 ;;
      esac
      case "$use" in *..*) echo "ci-critical-path: invalid workflow reference $use" >&2; exit 1 ;; esac
      entry="$key / @entry"
      jq -cn --arg key "$entry" --argjson value "$deps" '{key:$key,value:$value}'
      gate=$(jq -cn --arg key "$entry" '[$key]')
      children=$(expand "$root/${use#./}" "$key / " "$gate" "$stack|$file") || exit 1
      printf '%s\n' "$children"
      ends=$(printf '%s\n' "$children" | jq -sc 'map(.key)')
      jq -cn --arg key "$key" --argjson value "$ends" '{key:$key,value:$value}'
    fi
  done
)
nodes=$(expand "$workflow" '' '[]' '') || exit 1
printf '%s\n' "$nodes" | jq -es '
  if (map(.key)|unique|length) != length then error("duplicate workflow job") else from_entries end
  | . as $g
  | if any(.[][]; . as $n | $g|has($n)|not) then error("unresolved workflow dependency") else . end
  | def visit($n;$active):
      if .[$n] then . elif ($active|index($n)) != null then error("cyclic workflow dependency: "+$n)
      else reduce $g[$n][] as $d (.; visit($d;$active+[$n])) | .[$n]=true end;
    (reduce keys[] as $n ({};visit($n;[]))) as $checked | $g'
