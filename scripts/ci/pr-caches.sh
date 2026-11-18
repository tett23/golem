#!/bin/sh
# The caches of pull requests to delete, for the workflow pr-caches.yml
# (docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md).
#
#   gh api --paginate 'repos/OWNER/REPO/actions/caches?per_page=100' |
#     pr-caches.sh [OPEN_PULL_REQUEST...]
#
# The input is the caches of the repository: the pages of the API one after
# the other ({"actions_caches": [...]}), or the caches themselves. Each
# cache has id, ref, key, size_in_bytes and created_at. The arguments are
# the numbers of the open pull requests. Writes the IDs of the caches to
# delete, one a line:
#
# - I1: every cache of a pull request that is not open (its ref is
#   refs/pull/N/merge and N is not an argument), in ascending order;
# - I2: of the dist- caches of an open pull request, of each family (the
#   key without its last part, the commit hash), all but the one made last
#   (of two made at the same time, the larger ID is kept), in ascending
#   order;
# - I3: when the caches left by I1 and I2 are more than 9 GB (10^9 bytes)
#   in all, the dist- caches of open pull requests left, the one made first
#   first, until the total is 9 GB or less; no more than that.
#
# No cache of another ref (refs/heads/main among them) is written. The exit
# code is 2 for a wrong argument; jq fails on an input that is not JSON.
set -eu
for n in "$@"; do
  case "$n" in
    '' | *[!0-9]*)
      echo "usage: pr-caches.sh [OPEN_PULL_REQUEST...] < caches.json" >&2
      exit 2
      ;;
  esac
done
OPEN="[$(printf '%s' "$*" | tr ' ' ',')]"
jq -rs --argjson open "$OPEN" --argjson limit 9000000000 '
  # the time as a string that sorts as the time: the fraction of the
  # second padded with zeros to nine digits
  def stamp: (.created_at | rtrimstr("Z") | split(".")) as $p
    | $p[0] + "." + ((($p[1] // "") + "000000000")[0:9]);
  # the number of the pull request of the ref, or null
  def pr: if (.ref | startswith("refs/pull/")) and (.ref | endswith("/merge"))
    then (.ref | ltrimstr("refs/pull/") | rtrimstr("/merge") | tonumber? // null)
    else null end;
  def family: .key | split("-") | .[:-1] | join("-");
  def isdist: .key | startswith("dist-");
  def open: pr as $n | $n != null and any($open[]; . == $n);
  [.[] | if type == "object" and has("actions_caches") then .actions_caches[] else . end] as $all
  | [$all[] | select(pr != null and (open | not)) | .id] as $closed
  | [$all[] | select(open and isdist)]
    | group_by([pr, family])
    | [.[] | sort_by([stamp, .id]) | .[:-1][] | .id] as $stale
  | ($closed + $stale) as $gone
  | [$all[] | select(.id as $id | $gone | index([$id]) | not)] as $left
  | ([$left[].size_in_bytes] | add // 0) as $total
  | [$left[] | select(open and isdist)] | sort_by([stamp, .id])
    | reduce .[] as $c ({total: $total, ids: []};
        if .total > $limit then {total: (.total - $c.size_in_bytes), ids: (.ids + [$c.id])} else . end)
    | .ids as $over
  | ($closed | sort) + ($stale | sort) + $over | .[]
'
