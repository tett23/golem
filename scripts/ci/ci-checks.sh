#!/bin/sh
# Lists the checks that ci.yml runs on a pull request, for acceptance
# condition A1 of docs/adr/0395-bring-the-pull-request-ci-under-five-minutes.md:
# moving a step to another runner of build changes no line of the list.
#
#   ci-checks.sh [CI_YML [MODULES]]
#
# CI_YML is .github/workflows/ci.yml of the repository unless given;
# MODULES is passed to test-suites.sh. Writes, sorted (LC_ALL=C) and once
# each, tab-separated lines of three kinds:
#
#   needs   JOB              each job that ci needs
#   step    RUNNER  STEP     each step of build after the step "id: build"
#                            (cabal build), with each runner (matrix.runner)
#                            of a row of the matrix whose values meet its
#                            if on a pull request; STEP is the lines of the
#                            step but its if and its comments, less six
#                            spaces of indentation, joined by \n
#   suites  RUNNER  TARGET   each target of cabal test, with each runner
#                            whose row runs cabal test or the serial rest
#                            helper (root ADR 0481): the
#                            targets of test-suites.sh for matrix.suites
#
# The steps of actions/cache/save are left out: they save caches and check
# nothing. An if is read with the values of the row (matrix.*),
# github.event_name pull_request, github.ref refs/pull/1/merge, and
# success() and always() true, failure() and cancelled() false; it may
# use ( ), !, &&, ||, == and != on these and on 'strings', true and false.
# Any other term fails with exit code 1, so that no step is listed on a
# guess.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
[ $# -le 2 ] || { echo "usage: ci-checks.sh [CI_YML [MODULES]]" >&2; exit 2; }
CI_YML=${1:-$HERE/../../.github/workflows/ci.yml}
MODULES=${2:-}
[ -f "$CI_YML" ] || { echo "ci-checks: no file $CI_YML" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT
awk '
  function die(why) { printf "ci-checks: %s\n", why > "/dev/stderr"; failed = 1; exit 1 }
  function truthy(v) { return v != "" && v != "false" && v != "0" }
  function lex(s,   i, n, c, two, j) {
    ntok = 0; i = 1; n = length(s)
    while (i <= n) {
      c = substr(s, i, 1); two = substr(s, i, 2)
      if (c == " ") { i++; continue }
      if (two == "&&" || two == "||" || two == "==" || two == "!=") { tok[++ntok] = two; i += 2; continue }
      if (c == "(" || c == ")" || c == "!") { tok[++ntok] = c; i++; continue }
      if (c == "\047") {
        j = index(substr(s, i + 1), "\047")
        if (j == 0) die("no end of a string in: " s)
        tok[++ntok] = "\047" substr(s, i + 1, j - 1); i += j + 1; continue
      }
      if (c ~ /[A-Za-z0-9_.-]/) {
        j = i
        while (j <= n && substr(s, j, 1) ~ /[A-Za-z0-9_.-]/) j++
        tok[++ntok] = substr(s, i, j - i); i = j; continue
      }
      die("a character that is not read: " c " in: " s)
    }
    tok[ntok + 1] = ""
    pos = 1
  }
  function p_or(   v, r) {
    v = p_and()
    while (tok[pos] == "||") { pos++; r = p_and(); v = (truthy(v) || truthy(r)) ? "true" : "false" }
    return v
  }
  function p_and(   v, r) {
    v = p_not()
    while (tok[pos] == "&&") { pos++; r = p_not(); v = (truthy(v) && truthy(r)) ? "true" : "false" }
    return v
  }
  function p_not(   v) {
    if (tok[pos] == "!") { pos++; v = p_not(); return truthy(v) ? "false" : "true" }
    return p_cmp()
  }
  function p_cmp(   a, b, op) {
    a = p_prim()
    if (tok[pos] == "==" || tok[pos] == "!=") {
      op = tok[pos]; pos++; b = p_prim()
      return ((a == b) == (op == "==")) ? "true" : "false"
    }
    return a
  }
  function p_prim(   t, v, k) {
    t = tok[pos]; pos++
    if (t == "(") { v = p_or(); if (tok[pos] != ")") die("no ) in: " expr); pos++; return v }
    if (substr(t, 1, 1) == "\047") return substr(t, 2)
    if (t == "true" || t == "false") return t
    if (t == "success" || t == "always" || t == "failure" || t == "cancelled") {
      if (tok[pos] != "(" || tok[pos + 1] != ")") die("a function without (): " t)
      pos += 2
      return (t == "success" || t == "always") ? "true" : "false"
    }
    if (t ~ /^matrix\./) {
      k = substr(t, 8)
      if (!((row, k) in M)) die("no " t " in a row of the matrix")
      return M[row, k]
    }
    if (t == "github.event_name") return "pull_request"
    if (t == "github.ref") return "refs/pull/1/merge"
    die("a term that is not read: " t " in: " expr)
  }
  function eval_if(s,   v) {
    expr = s
    sub(/^\$\{\{ */, "", s); sub(/ *\}\}$/, "", s)
    lex(s)
    v = p_or()
    if (pos != ntok + 1) die("more after the end of: " expr)
    return truthy(v)
  }
  # one step of build after cabal build: its if and the other lines
  function flush(   i) {
    if (!instep) return
    instep = 0
    if (!after) { if (step ~ /(^|\\n)- id: build($|\\n)/) after = 1; return }
    if (step ~ /uses: actions\/cache\/save@/) return
    ns++; S[ns] = step; I[ns] = cond
    R[ns] = index(step, "sh scripts/ci/run-rest-suites.sh \"$SUITES\"") > 0
    if (index(step, "scripts/ci/run-rest-suites.sh") > 0 && !R[ns])
      die("an invocation of run-rest-suites.sh that is not read")
    if (R[ns] && index(step, "SUITES: ${{ matrix.suites }}") == 0)
      die("run-rest-suites.sh needs SUITES from matrix.suites")
    T[ns] = index(step, "cabal test $(sh scripts/ci/test-suites.sh \"$SUITES\")") > 0
  }
  /^  [a-z][a-z-]*:$/ { if (job == "build") flush(); job = substr($1, 1, length($1) - 1); next }
  job == "build" && /^        include:$/ { inc = 1; next }
  job == "build" && inc && /^          - runner: / { nr++; M[nr, "runner"] = $3; next }
  job == "build" && inc && /^            [a-z][a-z-]*: / { k = $1; sub(/:$/, "", k); v = $0; sub(/^ *[a-z-]+: */, "", v); M[nr, k] = v; next }
  job == "build" && inc && !/^          / { inc = 0 }
  job == "build" && /^      - / { flush(); instep = 1; cond = ""; step = substr($0, 7); next }
  job == "build" && instep && /^ *#/ { next }
  job == "build" && instep && /^        if: / { cond = substr($0, 13); next }
  job == "build" && instep && NF { step = step "\\n" substr($0, 7); next }
  job == "ci" && /^    needs: / {
    v = $0; sub(/^    needs: */, "", v); gsub(/[][ ]/, "", v)
    n = split(v, need, ",")
    for (i = 1; i <= n; i++) print "needs\t" need[i]
  }
  END {
    if (failed) exit 1
    if (job == "build") flush()
    if (nr == 0) die("no row in the matrix of build")
    if (!after) die("no step id: build in build")
    for (s = 1; s <= ns; s++) for (row = 1; row <= nr; row++) {
      if (I[s] != "" && !eval_if(I[s])) continue
      print "step\t" M[row, "runner"] "\t" S[s]
      if (T[s] && R[s]) die("a step mixes direct and serial tests")
      if (R[s] && M[row, "suites"] != "rest-a" && M[row, "suites"] != "rest-b")
        die("run-rest-suites.sh on a row outside rest-a and rest-b")
      if (T[s] || R[s]) print "suites-of\t" M[row, "runner"] "\t" M[row, "suites"]
    }
    if (failed) exit 1
  }
' "$CI_YML" >"$TMP/list"
while IFS="$(printf '\t')" read -r kind a b; do
  case "$kind" in
    suites-of)
      sh "$HERE/test-suites.sh" "$b" ${MODULES:+"$MODULES"} >"$TMP/suites"
      while IFS= read -r target; do printf 'suites\t%s\t%s\n' "$a" "$target"; done <"$TMP/suites"
      ;;
    needs) printf 'needs\t%s\n' "$a" ;;
    *) printf '%s\t%s\t%s\n' "$kind" "$a" "$b" ;;
  esac
done <"$TMP/list" | LC_ALL=C sort -u
