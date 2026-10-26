#!/bin/sh
# Writes the output of check.sh as Markdown tables for the job summary of
# the visual job (docs/adr/0095-visual-job-in-ci.md).
#
#   summary.sh FILE     FILE is the stdout of check.sh
#
# The inputs shem could not read come first, with the line of shem, in a
# table of their own: they are fixed in shem, not by accepting references
# (docs/adr/0093). The pages that differ from the references, and the
# references and PDFs that are missing or stale, follow.
set -eu
[ $# -eq 1 ] && [ -f "$1" ] || { echo "usage: summary.sh FILE" >&2; exit 2; }
awk '
  function cell(s) { gsub(/\|/, "\\|", s); return s }
  pending != "" {
    if ($1 ~ /^(changed|added|removed|unlisted|stale|unreadable|missing)$/) { u[++nu] = pending; e[nu] = ""; pending = "" }
    else { u[++nu] = pending; e[nu] = $0; pending = ""; next }
  }
  $1 == "unreadable" { pending = $2; next }
  $1 == "changed" || $1 == "added" || $1 == "removed" { p[++np] = "| " cell($2) " | " cell($3) " | `" $1 "` |"; next }
  $1 == "unlisted" || $1 == "stale" || $1 == "missing" { r[++nr] = "| " cell($2) " | `" $1 "` |"; next }
  END {
    if (pending != "") { u[++nu] = pending; e[nu] = "" }
    print "## 見た目の回帰テスト"
    print ""
    if (nu > 0) {
      print "### shem が読めなかった PDF"
      print ""
      print "Golem の Writer が shem の読む部分集合の外を書いた。参照を書き直しても通らない。shem を直してリリースし、固定した版を上げる（docs/adr/0093）。"
      print ""
      print "| 入力 | shem のエラー |"
      print "| --- | --- |"
      for (i = 1; i <= nu; i++) print "| " cell(u[i]) " | " cell(e[i]) " |"
      print ""
    }
    if (np > 0) {
      print "### 参照と違うページ（" np "）"
      print ""
      print "| 入力 | ページ | 種類 |"
      print "| --- | --- | --- |"
      for (i = 1; i <= np; i++) print p[i]
      print ""
    }
    if (nr > 0) {
      print "### 参照と PDF の過不足"
      print ""
      print "| 入力 | 種類 |"
      print "| --- | --- |"
      for (i = 1; i <= nr; i++) print r[i]
      print ""
    }
  }
' "$1"
