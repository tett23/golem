#!/bin/sh
# Writes the report of a failed visual regression test: the images of the
# changed pages before and after, the images of their differences, and a
# summary (docs/adr/0096-before-and-after-images-of-changed-pages.md).
# The visual job of ci.yml runs it only when check.sh failed.
#
#   report.sh CHECK PDFS OUT [BASE]
#
# CHECK is the stdout of check.sh, PDFS the PDFs it checked, OUT the
# directory of the artifact visual-diff, and BASE the commit to compare
# with (the base of a pull request, or the commit before a push to main;
# none when ci.yml is called from release.yml). OUT gets:
#
#   after/<input>/page-<n>.png    the page now, at 150 dpi
#   before/<input>/page-<n>.png   the page at BASE, when it is known
#   diff/<input>/page-<n>.png     shem diff of the two
#   summary.md                    the tables of the job summary
#
# and the summary goes to stdout too. OUT/pages/<input>.txt, the references
# of the PDFS as check.sh --accept would write them, comes from the check
# step, check.sh --lists OUT/pages: the pages are not rendered twice.
#
# The PDFs of BASE are those of the artifact visual-pdfs of the first push
# run of ci.yml on BASE or on one of its first-parent ancestors, up to 20
# commits (gh run list and gh run download, GITHUB_REPOSITORY). A page of
# them is the page before only when its PPM at 72 dpi has the SHA-256 of
# scripts/visual/pages/<input>.txt at BASE: an ancestor with the same
# pixels is as good as BASE. A page without one is reported as 前の画像なし.
# Failures of gh, of the download and of shem diff go into the report; the
# exit code is 0 but on a usage error, since the job has already failed.
#
# SHEM is the path of shem, as for check.sh; the images are drawn for the
# first 100 changed pages (by input and page), and the summary is one row
# per input when more than 500 pages changed.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
[ $# -eq 3 ] || [ $# -eq 4 ] || { echo "usage: report.sh CHECK PDFS OUT [BASE]" >&2; exit 2; }
[ -f "$1" ] && [ -d "$2" ] || { echo "usage: report.sh CHECK PDFS OUT [BASE]" >&2; exit 2; }
CHECK=$1
PDFS=$(cd "$2" && pwd)
mkdir -p "$3"
OUT=$(cd "$3" && pwd)
BASE=${4-}
SHEM=${SHEM:-$ROOT/third_party/shem/shem}
IMAGES=100
TABLE=500
if command -v sha256sum >/dev/null 2>&1; then SHA="sha256sum"; else SHA="shasum -a 256"; fi
WORK=$(mktemp -d)
trap 'rm -rf "${WORK:?}"' EXIT
NOTES=$WORK/notes
: >"$NOTES"
note() { printf '%s\n' "$*" >>"$NOTES"; }
cell() { printf '%s' "$1" | sed 's/|/\\|/g'; }

# the lines of check.sh: the pages (input, page, kind) in the order of the
# inputs and pages, the unreadable inputs with the line of shem, and the
# references and PDFs missing or stale
awk -v pages="$WORK/pages" -v unreadable="$WORK/unreadable" -v others="$WORK/others" '
  pending != "" {
    if ($1 ~ /^(changed|added|removed|unlisted|stale|unreadable|missing)$/) { print pending "\t" >unreadable; pending = "" }
    else { print pending "\t" $0 >unreadable; pending = ""; next }
  }
  $1 == "unreadable" { pending = $2; next }
  $1 == "changed" || $1 == "added" || $1 == "removed" { print $2 "\t" $3 "\t" $1 >pages; next }
  $1 == "unlisted" || $1 == "stale" || $1 == "missing" { print $2 "\t" $1 >others; next }
  END { if (pending != "") print pending "\t" >unreadable }
' "$CHECK"
for f in pages unreadable others; do [ -f "$WORK/$f" ] || : >"$WORK/$f"; done
LC_ALL=C sort -t "$(printf '\t')" -k 1,1 -k 2,2 "$WORK/pages" >"$WORK/pages.sorted"
mv "$WORK/pages.sorted" "$WORK/pages"
NPAGES=$(wc -l <"$WORK/pages" | tr -d ' ')

# pages/ is written by check.sh --lists OUT/pages, which writes nothing
# when --accept would refuse
[ -d "$OUT/pages" ] || note "pages/ はない。PDF がない、ページがない、または shem が読めない入力があるので、check.sh --accept も参照を書かない。"

# the PDFs of BASE or of an ancestor
BEFORE=
if [ -z "${BASE}" ]; then
  note "比べるコミットがない（release.yml からの実行）。前の画像は探さない。"
elif ! git -C "$ROOT" rev-list --first-parent --max-count=20 "${BASE}" >"$WORK/ancestors" 2>"$WORK/git.err"; then
  note "前の画像なし：$(cell "${BASE}") の祖先をたどれなかった（$(head -n 1 "$WORK/git.err" | sed 's/|/\\|/g')）。"
else
  while IFS= read -r c; do
    if ! gh run list --repo "${GITHUB_REPOSITORY-}" --workflow ci.yml --commit "$c" --event push --json databaseId -q '.[].databaseId' >"$WORK/runs" 2>"$WORK/gh.err"; then
      note "gh run list が ${c} で失敗した：$(head -n 1 "$WORK/gh.err" | sed 's/|/\\|/g')"
      continue
    fi
    while IFS= read -r run; do
      [ -n "$run" ] || continue
      rm -rf "$WORK/before-pdfs"
      if gh run download "$run" --repo "${GITHUB_REPOSITORY-}" -n visual-pdfs -D "$WORK/before-pdfs" >/dev/null 2>"$WORK/gh.err"; then
        BEFORE=$c
        note "前の PDF は、コミット ${c} の実行 ${run} の成果物 visual-pdfs から取った。"
        break
      fi
    done <"$WORK/runs"
    [ -z "${BEFORE}" ] || break
  done <"$WORK/ancestors"
  [ -n "${BEFORE}" ] || note "前の画像なし：${BASE} から first-parent の 20 個の祖先に、成果物 visual-pdfs を持つ ci.yml の push の実行がない。"
fi

# pagenum PAGE: the number of page-0012, 12
pagenum() { printf '%s\n' "$1" | sed 's/^page-0*//'; }
# render PDF DIR DPI FORMAT PAGES: renders the pages (comma separated) of PDF
render() { "$SHEM" render --dpi "$3" --format "$4" --pages "$5" "$1" "$2" >/dev/null 2>"$WORK/render.err"; }
# sha FILE
sha() { $SHA "$1" | cut -d' ' -f1; }

# the pages before, checked against the references of BASE: before.ok has
# "input<TAB>page" of every page whose image before is known
: >"$WORK/before.ok"
if [ -n "${BEFORE}" ]; then
  cut -f 1 "$WORK/pages" | LC_ALL=C sort -u >"$WORK/inputs"
  while IFS= read -r input; do
    awk -F '\t' -v i="$input" '$1 == i && $3 != "added" { print $2 }' "$WORK/pages" >"$WORK/want"
    [ -s "$WORK/want" ] || continue
    if [ ! -f "$WORK/before-pdfs/$input.pdf" ]; then continue; fi
    if ! git -C "$ROOT" show "${BASE}:scripts/visual/pages/$input.txt" >"$WORK/ref" 2>/dev/null; then continue; fi
    list=$(while IFS= read -r p; do pagenum "$p"; done <"$WORK/want" | paste -s -d , -)
    rm -rf "$WORK/b72/$input"
    render "$WORK/before-pdfs/$input.pdf" "$WORK/b72/$input" 72 ppm "$list" || continue
    while IFS= read -r p; do
      f=$WORK/b72/$input/$p.ppm
      [ -f "$f" ] || continue
      if grep -qxF "$(sha "$f")  $p" "$WORK/ref"; then
        printf '%s\t%s\n' "$input" "$p" >>"$WORK/before.ok"
      else
        rm -f "$f"
      fi
    done <"$WORK/want"
  done <"$WORK/inputs"
fi
has_before() { grep -qxF "$(printf '%s\t%s' "$1" "$2")" "$WORK/before.ok"; }

# the differences at 72 dpi of the changed pages with a page before:
# counts has "input<TAB>page<TAB>cell"
: >"$WORK/counts"
cut -f 1 "$WORK/before.ok" | LC_ALL=C sort -u >"$WORK/inputs"
while IFS= read -r input; do
  awk -F '\t' -v i="$input" '$1 == i && $3 == "changed" { print $2 }' "$WORK/pages" >"$WORK/want"
  : >"$WORK/want.ok"
  while IFS= read -r p; do if has_before "$input" "$p"; then printf '%s\n' "$p" >>"$WORK/want.ok"; fi; done <"$WORK/want"
  [ -s "$WORK/want.ok" ] || continue
  list=$(while IFS= read -r p; do pagenum "$p"; done <"$WORK/want.ok" | paste -s -d , -)
  mkdir -p "$WORK/b72only/$input"
  while IFS= read -r p; do cp "$WORK/b72/$input/$p.ppm" "$WORK/b72only/$input/"; done <"$WORK/want.ok"
  if ! render "$PDFS/$input.pdf" "$WORK/a72/$input" 72 ppm "$list"; then
    while IFS= read -r p; do printf '%s\t%s\tエラー：%s\n' "$input" "$p" "$(head -n 1 "$WORK/render.err" | sed 's/|/\\|/g')" >>"$WORK/counts"; done <"$WORK/want.ok"
    continue
  fi
  code=0
  "$SHEM" diff --format ppm "$WORK/b72only/$input" "$WORK/a72/$input" "$WORK/d72/$input" >"$WORK/diff.out" 2>"$WORK/diff.err" || code=$?
  if [ "$code" -gt 1 ]; then
    while IFS= read -r p; do printf '%s\t%s\tエラー：%s\n' "$input" "$p" "$(head -n 1 "$WORK/diff.err" | sed 's/|/\\|/g')" >>"$WORK/counts"; done <"$WORK/want.ok"
    continue
  fi
  # differ: page-0002.ppm: 3221 pixels in x0 y0 x1 y1
  awk -v i="$input" '$1 == "differ:" { n = $2; sub(/:$/, "", n); sub(/\.ppm$/, "", n); print i "\t" n "\t" $3 "\t" $6 " " $7 " " $8 " " $9 }' "$WORK/diff.out" >>"$WORK/counts"
done <"$WORK/inputs"

# the images: the first IMAGES pages, at 150 dpi in PNG
head -n "${IMAGES}" "$WORK/pages" >"$WORK/drawn"
DRAWN=$(wc -l <"$WORK/drawn" | tr -d ' ')
cut -f 1 "$WORK/drawn" | LC_ALL=C sort -u >"$WORK/inputs"
while IFS= read -r input; do
  after=$(awk -F '\t' -v i="$input" '$1 == i && $3 != "removed" { print $2 }' "$WORK/drawn" | while IFS= read -r p; do pagenum "$p"; done | paste -s -d , -)
  before=$(awk -F '\t' -v i="$input" '$1 == i && $3 != "added" { print $2 }' "$WORK/drawn" | while IFS= read -r p; do if has_before "$input" "$p"; then pagenum "$p"; fi; done | paste -s -d , -)
  if [ -n "$after" ] && ! render "$PDFS/$input.pdf" "$OUT/after/$input" 150 png "$after"; then
    note "${input} の後の画像を描けなかった：$(head -n 1 "$WORK/render.err" | sed 's/|/\\|/g')"
  fi
  if [ -n "$before" ]; then
    if render "$WORK/before-pdfs/$input.pdf" "$OUT/before/$input" 150 png "$before"; then
      if [ -d "$OUT/after/$input" ]; then
        code=0
        "$SHEM" diff --format png "$OUT/before/$input" "$OUT/after/$input" "$OUT/diff/$input" >/dev/null 2>"$WORK/diff.err" || code=$?
        [ "$code" -le 1 ] || note "${input} の差分の画像を描けなかった：$(head -n 1 "$WORK/diff.err" | sed 's/|/\\|/g')"
      fi
    else
      note "${input} の前の画像を描けなかった：$(head -n 1 "$WORK/render.err" | sed 's/|/\\|/g')"
    fi
  fi
done <"$WORK/inputs"
[ "${NPAGES}" -le "${IMAGES}" ] || note "画像は、変わった ${NPAGES} ページのうち、入力とページの順で最初の ${IMAGES} ページだけ描いた。残りの $((NPAGES - IMAGES)) ページは手元で描いて見る。"

# the summary
{
  echo "## 見た目の回帰テスト"
  echo ""
  if [ -s "$WORK/unreadable" ]; then
    echo "### shem が読めなかった PDF"
    echo ""
    echo "Golem の Writer が shem の読む部分集合の外を書いた。参照を書き直しても通らない。shem を直してリリースし、固定した版を上げる（docs/adr/0093）。"
    echo ""
    echo "| 入力 | shem のエラー |"
    echo "| --- | --- |"
    awk -F '\t' '{ e = $2; gsub(/\|/, "\\|", e); print "| " $1 " | " e " |" }' "$WORK/unreadable"
    echo ""
  fi
  if [ "${NPAGES}" -gt 0 ]; then
    echo "### 変わったページ（${NPAGES}）"
    echo ""
    if [ "${NPAGES}" -gt "${TABLE}" ]; then
      echo "変わったページが ${TABLE} を超えたので、入力ごとにまとめる。"
      echo ""
      echo "| 入力 | 変わったページ | 違う画素の数の最大 |"
      echo "| --- | --- | --- |"
      awk -F '\t' -v cf="$WORK/counts" 'FILENAME == cf { if ($3 ~ /^[0-9]+$/ && (!($1 in max) || $3 + 0 > max[$1])) max[$1] = $3 + 0; next }
        { n[$1]++; if (!($1 in seen)) { seen[$1] = 1; order[++k] = $1 } }
        END { for (i = 1; i <= k; i++) { m = (order[i] in max) ? max[order[i]] : "前の画像なし"; print "| " order[i] " | " n[order[i]] " | " m " |" } }' "$WORK/counts" "$WORK/pages"
    else
      echo "| 入力 | ページ | 種類 | 違う画素の数 | 違う画素を囲む矩形 |"
      echo "| --- | --- | --- | --- | --- |"
      awk -F '\t' -v cf="$WORK/counts" -v okfile="$WORK/before.ok" '
        FILENAME == cf { c[$1 "\t" $2] = $3; r[$1 "\t" $2] = $4; next }
        FILENAME == okfile { ok[$1 "\t" $2] = 1; next }
        { k = $1 "\t" $2
          if ($3 == "changed" && (k in c)) { n = c[k]; box = r[k] }
          else if ($3 == "changed" || ($3 == "removed" && !(k in ok))) { n = "前の画像なし"; box = "" }
          else { n = ""; box = "" }
          print "| " $1 " | " $2 " | `" $3 "` | " n " | " box " |" }' "$WORK/counts" "$WORK/before.ok" "$WORK/pages"
    fi
    echo ""
  fi
  if [ -s "$WORK/others" ]; then
    echo "### 参照と PDF の過不足"
    echo ""
    echo "| 入力 | 種類 |"
    echo "| --- | --- |"
    awk -F '\t' '{ print "| " $1 " | `" $2 "` |" }' "$WORK/others"
    echo ""
  fi
  if [ -s "$NOTES" ]; then
    echo "### 前の画像と成果物"
    echo ""
    sed 's/^/- /' "$NOTES"
    echo ""
  fi
  echo "変わったページの前と後の画像と差分の画像は、成果物 visual-diff にある。違う画素の数は、目に見えるかどうかを示さない。目に見えない 0.001mm のずれでも数千になる。"
} >"$OUT/summary.md"
cat "$OUT/summary.md"
