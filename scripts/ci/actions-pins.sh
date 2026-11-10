#!/bin/sh
# Pins every action of the workflows by the SHA of a commit, with the tag of
# its version as a comment (docs/adr/0296).
#
#   actions-pins.sh check|verify|latest|update [DIR]
#
# DIR is the directory of the workflows, .github/workflows of the
# repository by default; its files *.yml are read. A uses: line is a line
# whose first non-blank characters are "uses: " or "- uses: ". Its value
# must be
#
#   ./<path>                                  (a workflow of this repository)
#   <owner>/<repo>[/<path>]@<SHA> # v<N>[.<N>[.<N>]]
#
# with SHA 40 lowercase hexadecimal digits and nothing after the comment.
# Quotes, tags, branches, short SHAs and docker:// are not this form.
#
# check   No network. Every uses: line has the form, and the lines of the
#         same <owner>/<repo> (whatever the path) have the same SHA and the
#         same comment. Writes "FILE:LINE: reason" for each line that is
#         not, then the number of uses: lines; 0 lines is a failure.
# verify  check, then for each <owner>/<repo>, SHA and comment, the tag of
#         the comment in `git ls-remote --tags` (peeled with ^{} when it is
#         annotated) is the commit SHA.
# latest  check, then for each <owner>/<repo>, the pinned SHA is the commit
#         of the greatest tag v<N>[.<N>[.<N>]] (by number; v7 < v7.0.1, a
#         tag with a suffix such as -beta.1 is not a version), and for each
#         action used, runs.using of its action.yml (or action.yaml) at the
#         SHA, read with gh api, is node<N> with N >= 24 or composite.
# update  Rewrites every <owner>/<repo>[/<path>]@... of a uses: line to the
#         commit of the greatest version, with its most specific tag as the
#         comment, and writes "owner/repo: OLD -> NEW" for each repository
#         that changed. When an action at that commit does not run on node
#         24 or later nor is composite, nothing is written and it fails.
#
# Exits 0 on success, 1 when a check fails, 2 on an error (usage, no
# directory, a failed git or gh).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
die() { echo "actions-pins: $*" >&2; exit 2; }
usage() { echo "usage: actions-pins.sh check|verify|latest|update [DIR]" >&2; exit 2; }
[ $# -ge 1 ] && [ $# -le 2 ] || usage
CMD=$1
case $CMD in check | verify | latest | update) ;; *) usage ;; esac
if [ $# -eq 2 ]; then
  DIR=$2
else
  cd "$ROOT"
  DIR=.github/workflows
fi
[ -d "$DIR" ] || die "no such directory: $DIR"

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

# lines: the uses: lines, FILE<TAB>LINE<TAB>VALUE, in the order of the files,
# to $TMP/lines
lines() {
  : >"$TMP/lines"
  for f in "$DIR"/*.yml; do
    [ -f "$f" ] || continue
    LC_ALL=C awk -v f="$f" '
      /^[ \t]*(- )?uses: / { v = $0; sub(/^[ \t]*(- )?uses: /, "", v); printf "%s\t%d\t%s\n", f, FNR, v }
    ' "$f" >>"$TMP/lines"
  done
}
lines

# check: the form (I1, I2), the same SHA and comment for a repository (I3)
# and the number of lines (I4). Writes the pins, REPO<TAB>SHA<TAB>COMMENT,
# one for each repository, to $TMP/pins, and the actions, REPO<TAB>NAME<TAB>
# SHA (NAME is <owner>/<repo>[/<path>]), to $TMP/actions.
check() {
  LC_ALL=C awk -F '\t' -v pins="$TMP/pins" -v actions="$TMP/actions" '
    {
      n++
      v = $3
      if (v ~ /^\.\/[^ \t"'"'"']+$/) next
      if (v !~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.\/-]+)?@[0-9a-f]+ # v[0-9]+(\.[0-9]+)?(\.[0-9]+)?$/ ||
          length(substr(v, index(v, "@") + 1, index(v, " ") - index(v, "@") - 1)) != 40) {
        printf "%s:%s: not <owner>/<repo>[/<path>]@<40 lowercase hex> # v<N>[.<N>[.<N>]] nor ./<path>: %s\n", $1, $2, v
        bad++
        next
      }
      name = substr(v, 1, index(v, "@") - 1)
      sha = substr(v, index(v, "@") + 1, 40)
      comment = substr(v, index(v, "#") + 2)
      split(name, p, "/")
      repo = p[1] "/" p[2]
      path = substr(name, length(repo) + 2)
      key = tolower(repo)
      if (key in first) {
        if (sha != shas[key] || comment != comments[key]) {
          printf "%s:%s: %s is pinned to %s # %s here and to %s # %s at %s\n", $1, $2, repo, sha, comment, shas[key], comments[key], first[key]
          bad++
        }
      } else {
        first[key] = $1 ":" $2
        shas[key] = sha
        comments[key] = comment
        order[++repos] = key
        names[key] = repo
      }
      if (!((key SUBSEP path) in seen)) {
        seen[key, path] = 1
        printf "%s\t%s\t%s\n", repo, name, sha >actions
      }
    }
    END {
      for (i = 1; i <= repos; i++) printf "%s\t%s\t%s\n", names[order[i]], shas[order[i]], comments[order[i]] >pins
      printf "%d uses: lines checked\n", n
      if (n == 0) { print "no uses: line in the workflows" >"/dev/stderr"; exit 1 }
      exit bad > 0
    }
  ' "$TMP/lines"
}

# tags REPO: fetches the output of git ls-remote --tags of the repository
# into $TAGS, once (not in a $(...), so that a failure stops the script)
tags() {
  TAGS=$TMP/tags-$(printf "%s" "$1" | tr / _)
  if [ ! -f "$TAGS" ]; then
    git ls-remote --tags "https://github.com/$1.git" >"$TAGS.part" || die "git ls-remote failed for $1"
    mv "$TAGS.part" "$TAGS"
  fi
}

# commit_of TAGS TAG: the commit of the tag (peeled), or nothing
commit_of() {
  LC_ALL=C awk -v t="refs/tags/$2" '$2 == t "^{}" { p = $1 } $2 == t { l = $1 } END { print (p != "" ? p : l) }' "$1"
}

# newest TAGS: COMMIT<TAB>TAG of the greatest version, the most specific of
# equal ones (v7.0 after v7); nothing when there is none
newest() {
  LC_ALL=C awk '
    { n = $2; peeled = sub(/\^\{\}$/, "", n); sub(/^refs\/tags\//, "", n)
      if (peeled || !(n in commit)) commit[n] = $1 }
    END {
      for (n in commit) {
        if (n !~ /^v[0-9]+(\.[0-9]+)?(\.[0-9]+)?$/) continue
        c = split(substr(n, 2), p, ".")
        k = sprintf("%012d%012d%012d%d", p[1], (c >= 2 ? p[2] : 0), (c >= 3 ? p[3] : 0), c)
        if (k > best) { best = k; tag = n }
      }
      if (tag != "") printf "%s\t%s\n", commit[tag], tag
    }
  ' "$1"
}

# using REPO NAME SHA: runs.using of the action.yml (or action.yaml) of
# the action at the commit; "missing" when there is neither
using() {
  path=${2#"$1"}
  path=${path#/}
  dir=${path:+$path/}
  for file in action.yml action.yaml; do
    if gh api -H 'Accept: application/vnd.github.raw' "repos/$1/contents/$dir$file?ref=$3" >"$TMP/action" 2>/dev/null; then
      LC_ALL=C awk '
        { sub(/\r$/, "") }
        /^runs:/ { on = 1; next }
        on && /^[^ \t#]/ { on = 0 }
        on && /^[ \t]+using:/ { v = $0; sub(/^[ \t]+using:[ \t]*/, "", v); gsub(/["'"'"']/, "", v); sub(/[ \t]*(#.*)?$/, "", v); u = v; exit }
        END { print (u == "" ? "none" : u) }
      ' "$TMP/action"
      return 0
    fi
  done
  echo missing
}

# runs_ok USING: node24 or later, or composite
runs_ok() {
  case $1 in
    composite) return 0 ;;
    node[0-9]*)
      v=${1#node}
      case $v in *[!0-9]*) return 1 ;; esac
      [ "$v" -ge 24 ]
      ;;
    *) return 1 ;;
  esac
}

case $CMD in
  check)
    check
    ;;
  verify)
    check
    failed=0
    while IFS="$(printf '\t')" read -r repo sha comment; do
      tags "$repo"
      c=$(commit_of "$TAGS" "$comment")
      if [ -z "$c" ]; then
        echo "$repo: no tag $comment upstream"
        failed=1
      elif [ "$c" != "$sha" ]; then
        echo "$repo: $comment is $c upstream, not the pinned $sha"
        failed=1
      fi
    done <"$TMP/pins"
    exit "$failed"
    ;;
  latest)
    check
    failed=0
    while IFS="$(printf '\t')" read -r repo sha comment; do
      tags "$repo"
      newest=$(newest "$TAGS")
      if [ -z "$newest" ]; then
        echo "$repo: no version tag upstream"
        failed=1
      elif [ "${newest%%	*}" != "$sha" ]; then
        echo "$repo: the newest is ${newest#*	} (${newest%%	*}), pinned $comment ($sha)"
        failed=1
      fi
    done <"$TMP/pins"
    while IFS="$(printf '\t')" read -r repo name sha; do
      u=$(using "$repo" "$name" "$sha")
      if ! runs_ok "$u"; then
        echo "$name@$sha: runs.using is $u, not node24 or later nor composite"
        failed=1
      fi
    done <"$TMP/actions"
    exit "$failed"
    ;;
  update)
    # the repositories and the actions of the lines, whatever their form
    LC_ALL=C awk -F '\t' '
      $3 ~ /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.\/-]+)?@/ {
        name = substr($3, 1, index($3, "@") - 1)
        split(name, p, "/")
        repo = p[1] "/" p[2]
        old = substr($3, index($3, "@") + 1)
        if (old ~ / # /) old = substr(old, index(old, " # ") + 3)
        if (!(repo in seen)) { seen[repo] = 1; print "R\t" repo "\t" old }
        path = substr(name, length(repo) + 2)
        if (!((repo SUBSEP path) in act)) { act[repo, path] = 1; print "A\t" repo "\t" name }
      }
    ' "$TMP/lines" >"$TMP/found"
    [ -s "$TMP/found" ] || { echo "no action to update in $DIR" >&2; exit 1; }
    : >"$TMP/new"
    failed=0
    while IFS="$(printf '\t')" read -r kind repo rest; do
      [ "$kind" = R ] || continue
      tags "$repo"
      newest=$(newest "$TAGS")
      if [ -z "$newest" ]; then
        echo "$repo: no version tag upstream"
        failed=1
        continue
      fi
      printf '%s\t%s\t%s\n' "$repo" "$newest" "$rest" >>"$TMP/new"
    done <"$TMP/found"
    while IFS="$(printf '\t')" read -r kind repo name; do
      [ "$kind" = A ] || continue
      sha=$(LC_ALL=C awk -F '\t' -v r="$repo" '$1 == r { print $2 }' "$TMP/new")
      [ -n "$sha" ] || continue
      u=$(using "$repo" "$name" "$sha")
      if ! runs_ok "$u"; then
        echo "$name@$sha: runs.using is $u at the newest version, not node24 or later nor composite"
        failed=1
      fi
    done <"$TMP/found"
    [ "$failed" = 0 ] || { echo "nothing was written" >&2; exit 1; }
    for f in "$DIR"/*.yml; do
      [ -f "$f" ] || continue
      LC_ALL=C awk -F '\t' -v new="$TMP/new" '
        BEGIN { FS = "\t"; while ((getline l <new) > 0) { split(l, x, "\t"); sha[x[1]] = x[2]; tag[x[1]] = x[3] } FS = " " }
        /^[ \t]*(- )?uses: [A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\/[A-Za-z0-9_.\/-]+)?@/ {
          pre = $0; sub(/uses: .*$/, "uses: ", pre)
          v = substr($0, length(pre) + 1)
          name = substr(v, 1, index(v, "@") - 1)
          split(name, p, "/")
          r = p[1] "/" p[2]
          if (r in sha) { print pre name "@" sha[r] " # " tag[r]; next }
        }
        { print }
      ' "$f" >"$TMP/rewritten"
      if ! cmp -s "$TMP/rewritten" "$f"; then cat "$TMP/rewritten" >"$f"; fi
    done
    while IFS="$(printf '\t')" read -r repo sha tag old; do
      [ "$old" = "$tag" ] || echo "$repo: $old -> $tag"
    done <"$TMP/new"
    lines
    check >/dev/null
    ;;
esac
