#!/bin/sh
# Prepares the source of a figure of the manuals for Inkscape, so that the
# outline that scripts/manual/outline-figures.sh makes of it has its text
# where a browser draws the source (docs/adr/0234 section 4, I4):
#
#   outline-prepare.sh < SOURCE > INPUT          the input of Inkscape
#   outline-prepare.sh --strip < OUTPUT > FIGURE the output of Inkscape
#                                                without the added rules
#
# Inkscape and Chromium lay out the text of the sources differently in two
# ways, and the input makes Inkscape do what Chromium does:
#
# - dominant-baseline: central. Inkscape puts the central baseline halfway
#   between the typographic ascender and descender of OS/2 (Noto Sans JP:
#   880 and -120, so 0.38 em above the alphabetic baseline); Chromium puts
#   it halfway between the ascent and descent of hhea (1160 and -288, so
#   0.436 em). The text of each text element is put in
#   <tspan class="golem-outline">, and each one-line rule of the style
#   sheet that sets central, and a text element that sets it itself, lowers
#   it by the difference, 0.056 em. Both weights of the fonts of
#   scripts/manual/fetch-fonts.sh have these metrics. Vertical text is not
#   lowered: there both put the glyphs on the centre line.
# - text-spacing-trim: normal. Chromium sets a fullwidth punctuation mark
#   half-width with the feature halt next to another
#   (third_party/blink/renderer/platform/fonts/shaping/han_kerning.cc):
#     I1 a close before a close, a middle dot or a narrow close;
#     I2 an open after an open, a middle dot, a close or a narrow open;
#     I3 nothing else, and not the first one of a text element when no
#        other is before it.
#   Inkscape does not, so the marks of I1 and I2 are put in
#   <tspan class="golem-halt">, which sets halt. The classes are those of
#   Chromium for Noto Sans JP: opens 「『（［｛〈《【〔〖〘〚〝｟, closes
#   」』）］｝〉》】〕〗〙〛〞〟｠、。，．, middle dots ：；・·‧ and the
#   ideographic space, narrow opens “‘([{｢, narrow closes ”’)]}｣. Chromium
#   does the same in vertical text with vhal, but Inkscape places the text
#   differently with vhal, so a mark of I1 or I2 in vertical text is an
#   error. Inkscape adds the baseline-shift of a tspan to that of a tspan
#   inside it, so the tspans of golem-halt set it to 0.
#
# The rules that it adds are at the end of the style sheet between the
# comments golem-outline: begin and golem-outline: end; --strip removes
# them from the output, which keeps the style sheet of the source. The
# @font-face rules are removed: Inkscape does not read them, and an
# outlined SVG must not keep them (G08011).
#
# It reads what the sources are written in, and stops with an error on
# what it does not read: a text element must be on one line with only text
# in it, a rule of the style sheet that sets dominant-baseline or
# writing-mode must be on one line, a selector of a rule that sets
# writing-mode is text, *, a class or text with a class, and there is one
# style element.
set -eu
if [ "${1:-}" = --strip ]; then
  exec sed '/\/\* golem-outline: begin \*\//,/\/\* golem-outline: end \*\//d'
fi
[ $# -eq 0 ] || { echo "usage: outline-prepare.sh [--strip] < SVG" >&2; exit 2; }
# the narrow quotes are the characters that it classifies
# shellcheck disable=SC1112
exec awk '
function fail(m) { print "outline-prepare: line " NR ": " m > "/dev/stderr"; exit 1 }
function classes(list, t,   n, a, i) { n = split(list, a, " "); for (i = 1; i <= n; i++) type[a[i]] = t }
function vertical(s) { return s ~ /writing-mode[=:]["[:space:]]*(tb|tb-rl|vertical-rl|vertical-lr)/ }
function central(s) { return s ~ /dominant-baseline[=:]["[:space:]]*central/ }
# the rules for the selectors of a rule of the style sheet, and the
# classes of vertical text
function rule(sel, decls,   n, a, i, s, c) {
  n = split(sel, a, ",")
  for (i = 1; i <= n; i++) {
    s = a[i]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
    if (vertical(decls)) {
      if (s == "text" || s == "*") vall = 1
      else if (s ~ /^(text)?\.[-_A-Za-z0-9]+$/) { c = s; sub(/^text/, "", c); vclass[substr(c, 2)] = 1 }
      else fail("a selector of vertical text that it does not read: " s)
      after = after "    " s " > tspan.golem-outline { baseline-shift: 0; }\n"
    } else if (central(decls)) {
      before = before "    " s " > tspan.golem-outline { baseline-shift: " SHIFT "; }\n"
    }
  }
}
# whether the start tag TAG is that of vertical text
function isvertical(tag,   n, a, i) {
  if (vall || vertical(tag)) return 1
  if (match(tag, /class="[^"]*"/)) {
    n = split(substr(tag, RSTART + 7, RLENGTH - 8), a, " ")
    for (i = 1; i <= n; i++) if (a[i] in vclass) return 1
  }
  return 0
}
# the text S with the marks of I1 and I2 in tspans of golem-halt; in
# vertical text (V), such a mark is an error
function trim(s, v,   n, i, l, t, tok, ty, out) {
  n = 0
  for (i = 1; i <= length(s); i += l) {
    # a mark is 1 character, or 1 to 3 bytes when awk counts bytes
    ty = "x"
    for (l = 3; l >= 1; l--) { t = substr(s, i, l); if (t in type) { ty = type[t]; break } }
    if (l == 0) { l = 1; t = substr(s, i, 1) }
    n++; tok[n] = t; tt[n] = ty
  }
  tt[0] = "x"; tt[n + 1] = "x"; out = ""
  for (i = 1; i <= n; i++) {
    if ((tt[i] == "c" && (tt[i + 1] == "c" || tt[i + 1] == "m" || tt[i + 1] == "nc")) ||
        (tt[i] == "o" && (tt[i - 1] == "o" || tt[i - 1] == "m" || tt[i - 1] == "c" || tt[i - 1] == "no")))
    {
      if (v) fail("vertical text with fullwidth punctuation next to another (" tok[i] "): Inkscape does not set it half-width where Chromium does")
      out = out "<tspan class=\"golem-halt\">" tok[i] "</tspan>"
    }
    else out = out tok[i]
  }
  return out
}
BEGIN {
  SHIFT = "-0.056em"
  classes("「 『 （ ［ ｛ 〈 《 【 〔 〖 〘 〚 〝 ｟", "o")
  classes("」 』 ） ］ ｝ 〉 》 】 〕 〗 〙 〛 〞 〟 ｠ 、 。 ， ．", "c")
  classes("： ； ・ · ‧", "m"); type["\343\200\200"] = "m"
  classes("“ ‘ ( [ { ｢", "no")
  classes("” ’ ) ] } ｣", "nc")
}
/@font-face/ { next }
instyle || /<style[[:space:]>]/ {
  if (!instyle) { styles++; if (styles > 1) fail("more than one style element; the sources have one style element"); instyle = 1 }
  line = $0
  if (line ~ /<\/style>/) {
    i = index(line, "</style>")
    body = substr(line, 1, i - 1); rest = substr(line, i)
  } else { body = line; rest = "" }
  sub(/.*<style[^>]*>/, "", body)
  if (body ~ /dominant-baseline|writing-mode/) {
    if (body !~ /^[^{}]*\{[^{}]*\}[[:space:]]*$/) fail("a rule with dominant-baseline or writing-mode is not on one line")
    sel = body; sub(/\{.*/, "", sel); decls = body; sub(/^[^{]*\{/, "", decls)
    rule(sel, decls)
  }
  if (rest == "") { print; next }
  instyle = 0
  pre = substr(line, 1, length(line) - length(rest))
  if (pre !~ /^[[:space:]]*$/) { print pre; pre = "" }
  printf "    /* golem-outline: begin */\n    tspan.golem-halt { font-feature-settings: \"halt\"; baseline-shift: 0; }\n%s%s    /* golem-outline: end */\n", before, after
  print pre rest
  next
}
/<text[[:space:]>]/ {
  line = $0; out = ""
  while (match(line, /<text[[:space:]>][^>]*>/)) {
    tag = substr(line, RSTART, RLENGTH)
    out = out substr(line, 1, RSTART - 1) tag
    line = substr(line, RSTART + RLENGTH)
    if (tag ~ /\/>$/) continue
    i = index(line, "</text>")
    if (i == 0) fail("a text element is not on one line")
    content = substr(line, 1, i - 1)
    if (index(content, "<")) fail("a text element has markup inside")
    v = isvertical(tag)
    out = out "<tspan class=\"golem-outline\"" ((central(tag) && !v) ? " baseline-shift=\"" SHIFT "\"" : "") ">" trim(content, v) "</tspan></text>"
    line = substr(line, i + 7)
  }
  print out line
  next
}
{ print }
'
