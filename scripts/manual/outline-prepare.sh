#!/bin/sh
# Prepares the source of a figure of the manuals for Inkscape, so that the
# outline that scripts/manual/outline-figures.sh makes of it has its text
# where a browser draws the source (docs/adr/0234 section 4, docs/adr/0239):
#
#   outline-prepare.sh < SOURCE > INPUT          the input of Inkscape
#   outline-prepare.sh --strip < OUTPUT > FIGURE the output of Inkscape
#                                                without the added rules
#   outline-prepare.sh --check NAME < SOURCE     the punctuation of SOURCE,
#                                                named NAME in the messages
#                                                (scripts/manual/check-figures.sh)
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
# - Adjacent fullwidth punctuation (docs/adr/0239 section 3). The sources
#   set it with the spaces with which Golem sets the body text: the rule
#   text { text-spacing-trim: space-all; } stops the trimming of the
#   browsers, and a mark to be set half-width is in
#   <tspan class="halt">, which the rule
#   tspan.halt { font-feature-settings: "halt"; } of the source sets with
#   the feature halt. Inkscape reads that rule as the browsers do. The rule
#   of text-spacing-trim is removed from the input, since an outlined SVG
#   must not keep it (G08011), and Inkscape adds the baseline-shift of a
#   tspan to that of a tspan inside it, so the tspans of halt set it to 0.
#   --check checks that the marks in tspans of halt are those of the table
#   of docs/adr/0239: with O the opening brackets, P the closing brackets,
#   the full stops and the commas and S the ideographic space,
#     P P   the first          P O   the second
#     P S, O O, O P, S O       none
#   and that the source has the rule of text-spacing-trim, and the rule of
#   halt when it has a tspan of halt. A middle dot next to another mark,
#   any other pair of marks, and two marks next to each other in vertical
#   text are errors: Inkscape places vhal differently from Chromium.
#
# The rules that it adds are at the end of the style sheet between the
# comments golem-outline: begin and golem-outline: end; --strip removes
# them from the output, which keeps the style sheet of the source. The
# @font-face rules are removed: Inkscape does not read them, and an
# outlined SVG must not keep them (G08011).
#
# It reads what the sources are written in, and stops with an error on
# what it does not read: a text element must be on one line with only text
# and tspans of halt around one mark in it, a rule of the style sheet that
# sets dominant-baseline or writing-mode must be on one line, the only rule
# that sets text-spacing-trim is the one above, a selector of a rule that
# sets writing-mode is text, *, a class or text with a class, and there is
# one style element.
set -eu
if [ "${1:-}" = --strip ]; then
  exec sed '/\/\* golem-outline: begin \*\//,/\/\* golem-outline: end \*\//d'
fi
CHECK=
if [ "${1:-}" = --check ] && [ $# -eq 2 ]; then
  CHECK=$2
elif [ $# -ne 0 ]; then
  echo "usage: outline-prepare.sh [--strip | --check NAME] < SVG" >&2
  exit 2
fi
exec awk -v check="$CHECK" '
function fail(m) { print "outline-prepare: line " NR ": " m > "/dev/stderr"; failed = 1; exit 1 }
# an error of --check: all of them are written, and the exit code is 1
function err(m) { print "check-figures: " check ": line " NR ": " m > "/dev/stderr"; errors++ }
function errfile(m) { print "check-figures: " check ": " m > "/dev/stderr"; errors++ }
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
# the characters of the content S of a text element in tok[1..n], their
# classes in tt (o, p, s, m or x) and whether each is in a tspan of halt
# in th; n is returned. A mark is 1 character, or 1 to 3 bytes when awk
# counts bytes; any other character is taken a byte at a time.
function chars(s,   n, i, l, t, j, inner, open) {
  open = "<tspan class=\"halt\">"
  n = 0; i = 1
  while (i <= length(s)) {
    if (substr(s, i, 1) == "<") {
      if (substr(s, i, length(open)) != open) fail("a text element has markup inside other than <tspan class=\"halt\">")
      i += length(open)
      j = index(substr(s, i), "</tspan>")
      if (j == 0) fail("a text element has markup inside other than <tspan class=\"halt\">")
      inner = substr(s, i, j - 1)
      if (!(inner in type)) fail("a tspan of halt must hold one fullwidth punctuation mark: " inner)
      n++; tok[n] = inner; tt[n] = type[inner]; th[n] = 1
      i += j - 1 + 8
      continue
    }
    for (l = 3; l >= 1; l--) { t = substr(s, i, l); if (t in type) break }
    if (l == 0) { l = 1; t = substr(s, i, 1) }
    n++; tok[n] = t; tt[n] = (t in type) ? type[t] : "x"; th[n] = 0
    i += l
  }
  return n
}
# --check: the marks of the text of N characters (V: vertical) against
# the table
function punct(n, v,   i, a, b, want) {
  for (i = 1; i <= n; i++) need[i] = 0
  for (i = 1; i < n; i++) {
    a = tt[i]; b = tt[i + 1]
    if (a == "x" || b == "x") continue
    if (v) { err("vertical text with punctuation next to another (" tok[i] tok[i + 1] ")"); continue }
    if (a == "m" || b == "m") { err("a middle dot next to punctuation (" tok[i] tok[i + 1] ")"); continue }
    if (a == "p" && b == "p") need[i] = 1
    else if (a == "p" && b == "o") need[i + 1] = 1
    else if (!((a == "p" && b == "s") || (a == "o" && b == "o") || (a == "o" && b == "p") || (a == "s" && b == "o")))
      err("a pair of punctuation that is not in the table of docs/adr/0239 (" tok[i] tok[i + 1] ")")
  }
  for (i = 1; i <= n; i++) {
    if (th[i] && v) err(tok[i] " has a tspan of halt in vertical text")
    else if (th[i] && !need[i]) err(tok[i] " has a tspan of halt that it does not need")
    else if (!th[i] && need[i]) err(tok[i] " needs a tspan of halt: <tspan class=\"halt\">" tok[i] "</tspan>")
    if (th[i]) halts++
  }
}
BEGIN {
  SHIFT = "-0.056em"
  SPACEALL = "text { text-spacing-trim: space-all; }"
  HALT = "tspan.halt { font-feature-settings: \"halt\"; }"
  classes("「 『 （ ［ ｛ 〈 《 【 〔 〖 〘 〚 〝 ｟", "o")
  classes("」 』 ） ］ ｝ 〉 》 】 〕 〗 〙 〛 〞 〟 ｠ 、 。 ， ．", "p")
  classes("： ； ・", "m"); type["\343\200\200"] = "s"
}
/@font-face/ { if (check == "") next }
instyle || /<style[[:space:]>]/ {
  if (!instyle) { styles++; if (styles > 1) fail("more than one style element; the sources have one style element"); instyle = 1 }
  line = $0
  if (line ~ /<\/style>/) {
    i = index(line, "</style>")
    body = substr(line, 1, i - 1); rest = substr(line, i)
  } else { body = line; rest = "" }
  sub(/.*<style[^>]*>/, "", body)
  trimmed = body; gsub(/^[[:space:]]+|[[:space:]]+$/, "", trimmed)
  if (trimmed == SPACEALL) {
    t = line; gsub(/^[[:space:]]+|[[:space:]]+$/, "", t)
    if (t != SPACEALL) fail("the rule " SPACEALL " is not on a line of its own")
    spaceall = 1
    if (check == "") next
  }
  else if (body ~ /text-spacing-trim/) fail("a rule with text-spacing-trim other than " SPACEALL)
  if (trimmed == HALT) haltrule = 1
  if (body ~ /dominant-baseline|writing-mode/) {
    if (body !~ /^[^{}]*\{[^{}]*\}[[:space:]]*$/) fail("a rule with dominant-baseline or writing-mode is not on one line")
    sel = body; sub(/\{.*/, "", sel); decls = body; sub(/^[^{]*\{/, "", decls)
    rule(sel, decls)
  }
  if (rest == "") { if (check == "") print; next }
  instyle = 0
  if (check != "") next
  pre = substr(line, 1, length(line) - length(rest))
  if (pre !~ /^[[:space:]]*$/) { print pre; pre = "" }
  printf "    /* golem-outline: begin */\n    tspan.halt { baseline-shift: 0; }\n%s%s    /* golem-outline: end */\n", before, after
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
    v = isvertical(tag)
    n = chars(content)
    if (check != "") punct(n, v)
    else for (k = 1; k <= n; k++) if (th[k] && v) fail("a tspan of halt in vertical text (" tok[k] "): Inkscape does not set it half-width where Chromium does")
    out = out "<tspan class=\"golem-outline\"" ((central(tag) && !v) ? " baseline-shift=\"" SHIFT "\"" : "") ">" content "</tspan></text>"
    line = substr(line, i + 7)
  }
  if (check == "") print out line
  next
}
check == "" { print }
END {
  if (failed || check == "") exit failed
  if (!spaceall) { errfile("the style sheet has no rule " SPACEALL) }
  if (halts && !haltrule) { errfile("a tspan of halt without the rule " HALT " in the style sheet") }
  exit (errors > 0 ? 1 : 0)
}
'
