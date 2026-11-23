#!/bin/sh
# Generates the tables of golem-unicode (docs/adr/0411): the properties of
# the grapheme cluster boundaries and of the word boundaries of UAX #29, and
# the code points whose General_Category is a letter (L*) or a number (N*).
#
#   sh scripts/gen-unicode-segmentation.sh GraphemeBreakProperty.txt \
#     WordBreakProperty.txt emoji-data.txt DerivedCoreProperties.txt \
#     UnicodeData.txt
#
# The files are read from the paths given; nothing is downloaded. They are
# those of Unicode 17.0.0, the version of libgrapheme 3.0.0, and can be
# fetched, checked by their SHA-256, with scripts/ci/fetch-url.sh:
#
#   https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakProperty.txt
#     d6b51d1d2ae5c33b451b7ed994b48f1f4dc62b2272a5831e7fd418514a6bae89
#   https://www.unicode.org/Public/17.0.0/ucd/auxiliary/WordBreakProperty.txt
#     72274cac1e6b919507db35655c3e175aa27274668a1ece95c28d2069f2ad9852
#   https://www.unicode.org/Public/17.0.0/ucd/emoji/emoji-data.txt
#     2cb2bb9455cda83e8481541ecf5b6dfda66a3bb89efa3fa7c5297eccf607b72b
#   https://www.unicode.org/Public/17.0.0/ucd/DerivedCoreProperties.txt
#     24c7fed1195c482faaefd5c1e7eb821c5ee1fb6de07ecdbaa64b56a99da22c08
#   https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt
#     2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c
#
# The conformance data of the tests of golem-unicode
# (modules/golem-unicode/test/data/) comes from the same version:
#
#   https://www.unicode.org/Public/17.0.0/ucd/auxiliary/GraphemeBreakTest.txt
#     e2d134d2c52919bace503ebb6a551c1855fe1a1faec18478c78fff254a1793ec
#   https://www.unicode.org/Public/17.0.0/ucd/auxiliary/WordBreakTest.txt
#     1de23a75f37904abc7d206239ee8d34f8fdf0fb4ab32a7174dfbabbde25419b2
#
# A code point with two properties gets the combined value libgrapheme 3.0.0
# gives it (gen/character.c and gen/word.c of libgrapheme): Extend or ZWJ
# with an Indic_Conjunct_Break value, and ALetter with
# Extended_Pictographic. Any other combination is an error. Adjacent ranges
# with the same value are merged; a code point the files do not list is
# Other.
set -eu
if [ "$#" -ne 5 ]; then
  echo "usage: $0 GraphemeBreakProperty.txt WordBreakProperty.txt emoji-data.txt DerivedCoreProperties.txt UnicodeData.txt" >&2
  exit 2
fi
out="$(dirname "$0")/../modules/golem-unicode/src/Golem/Unicode/Table.hs"
tmp="$out.tmp"
LC_ALL=C awk '
function hex(s,    i, n, c) {
  n = 0
  s = toupper(s)
  for (i = 1; i <= length(s); i++) {
    c = index("0123456789ABCDEF", substr(s, i, 1))
    if (c == 0) { fail("bad code point: " s) }
    n = n * 16 + c - 1
  }
  return n
}
function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }
function fail(m) { print m > "/dev/stderr"; failed = 1; exit 1 }
# the range of the first field of a data line into lo and hi
function range(cp) {
  cp = trim(cp)
  if (index(cp, "..") > 0) { lo = hex(substr(cp, 1, index(cp, "..") - 1)); hi = hex(substr(cp, index(cp, "..") + 2)) }
  else { lo = hex(cp); hi = lo }
  if (hi < lo) fail("bad range: " cp)
}
function version(line, name,    v) {
  v = line
  sub(/^#[ \t]*/, "", v)
  sub(/[ \t\r]+$/, "", v)
  if (substr(v, 1, length(name) + 1) != name "-") fail("not " name ": " line)
  v = substr(v, length(name) + 2)
  sub(/\.txt$/, "", v)
  if (ver != "" && v != ver) fail("versions differ: " ver " and " v)
  ver = v
}
# one entry, in the layout of fourmolu (trailing commas)
function entry(n, text) {
  if (n == 0) printf "  [ %s", text
  else printf ",\n    %s", text
}
FNR == 1 { file++ }
file == 1 && FNR == 1 { version($0, "GraphemeBreakProperty") }
file == 2 && FNR == 1 { version($0, "WordBreakProperty") }
file == 4 && FNR == 1 { version($0, "DerivedCoreProperties") }
file <= 4 {
  line = $0
  sub(/#.*/, "", line)
  if (trim(line) == "") next
  n = split(line, f, ";")
  range(f[1])
  p = trim(f[2])
  if (file == 1) {
    if (!(p in gname)) fail("unknown Grapheme_Cluster_Break value: " $0)
    for (c = lo; c <= hi; c++) { if (c in gcb) fail("listed twice: " $0); gcb[c] = gname[p] }
  } else if (file == 2) {
    if (!(p in wname)) fail("unknown Word_Break value: " $0)
    for (c = lo; c <= hi; c++) { if (c in wb) fail("listed twice: " $0); wb[c] = wname[p] }
  } else if (file == 3) {
    if (p == "Extended_Pictographic") for (c = lo; c <= hi; c++) ep[c] = 1
  } else if (p == "InCB") {
    v = trim(f[3])
    if (v != "Consonant" && v != "Extend" && v != "Linker") fail("unknown InCB value: " $0)
    for (c = lo; c <= hi; c++) incb[c] = v
  }
  next
}
file == 5 {
  n = split($0, f, ";")
  if (n < 3) fail("bad line of UnicodeData.txt: " $0)
  c = hex(f[1])
  isln = (substr(f[3], 1, 1) == "L" || substr(f[3], 1, 1) == "N")
  if (f[2] ~ /, First>$/) { first = c; next }
  if (f[2] ~ /, Last>$/) { if (first < 0) fail("Last without First: " $0); lo = first; first = -1 }
  else lo = c
  if (isln) for (x = lo; x <= c; x++) ln[x] = 1
  next
}
BEGIN {
  first = -1
  gname["CR"] = "GbCR"; gname["LF"] = "GbLF"; gname["Control"] = "GbControl"
  gname["Extend"] = "GbExtend"; gname["ZWJ"] = "GbZWJ"
  gname["Regional_Indicator"] = "GbRegionalIndicator"; gname["Prepend"] = "GbPrepend"
  gname["SpacingMark"] = "GbSpacingMark"; gname["L"] = "GbL"; gname["V"] = "GbV"
  gname["T"] = "GbT"; gname["LV"] = "GbLV"; gname["LVT"] = "GbLVT"
  wname["CR"] = "WbCR"; wname["LF"] = "WbLF"; wname["Newline"] = "WbNewline"
  wname["Extend"] = "WbExtend"; wname["ZWJ"] = "WbZWJ"
  wname["Regional_Indicator"] = "WbRegionalIndicator"; wname["Format"] = "WbFormat"
  wname["Katakana"] = "WbKatakana"; wname["Hebrew_Letter"] = "WbHebrewLetter"
  wname["ALetter"] = "WbALetter"; wname["Single_Quote"] = "WbSingleQuote"
  wname["Double_Quote"] = "WbDoubleQuote"; wname["MidNumLet"] = "WbMidNumLet"
  wname["MidLetter"] = "WbMidLetter"; wname["MidNum"] = "WbMidNum"
  wname["Numeric"] = "WbNumeric"; wname["ExtendNumLet"] = "WbExtendNumLet"
  wname["WSegSpace"] = "WbWSegSpace"
}
# the value of the grapheme table of a code point, combined as libgrapheme does
function gvalue(c,    g) {
  g = (c in gcb) ? gcb[c] : ""
  if (c in ep) {
    if (g != "" || (c in incb)) fail(sprintf("Extended_Pictographic with another property: %04X", c))
    return "GbExtendedPictographic"
  }
  if (c in incb) {
    if (incb[c] == "Consonant" && g == "") return "GbInCBConsonant"
    if (incb[c] == "Extend" && g == "") return "GbInCBExtend"
    if (incb[c] == "Linker" && g == "") return "GbInCBLinker"
    if (incb[c] == "Extend" && g == "GbExtend") return "GbExtendInCBExtend"
    if (incb[c] == "Linker" && g == "GbExtend") return "GbExtendInCBLinker"
    if (incb[c] == "Extend" && g == "GbZWJ") return "GbZWJInCBExtend"
    fail(sprintf("InCB=%s with %s: %04X", incb[c], g, c))
  }
  return g == "" ? "GbOther" : g
}
function wvalue(c,    w) {
  w = (c in wb) ? wb[c] : ""
  if (c in ep) {
    if (w == "WbALetter") return "WbALetterExtendedPictographic"
    if (w != "") fail(sprintf("Extended_Pictographic with %s: %04X", w, c))
    return "WbExtendedPictographic"
  }
  return w == "" ? "WbOther" : w
}
END {
  if (failed) exit 1
  if (file != 5) fail("expected five files")
  if (first >= 0) fail("First without Last in UnicodeData.txt")
  print "{- | Generated by scripts/gen-unicode-segmentation.sh; do not edit."
  print "The properties of the grapheme cluster and word boundaries of UAX #29 and"
  print "the letters and numbers of the General_Category (docs/adr/0411), from"
  print "Unicode " ver " (GraphemeBreakProperty.txt, WordBreakProperty.txt,"
  print "emoji-data.txt, DerivedCoreProperties.txt and UnicodeData.txt of"
  print "https://www.unicode.org/Public/" ver "/ucd/). The values that combine two"
  print "properties are those of libgrapheme 3.0.0 (ISC, LICENSE-libgrapheme)."
  print "Unicode data: (c) Unicode, Inc., under the Unicode License v3"
  print "(UNICODE-LICENSE, https://www.unicode.org/license.txt)."
  print "-}"
  print "module Golem.Unicode.Table"
  print "  ( GraphemeBreak (..),"
  print "    WordBreak (..),"
  print "    unicodeVersion,"
  print "    graphemeBreakRanges,"
  print "    wordBreakRanges,"
  print "    letterOrNumberRanges,"
  print "  )"
  print "where"
  print ""
  print "{- | The Grapheme_Cluster_Break values, Extended_Pictographic, the"
  print "Indic_Conjunct_Break values, and their combinations."
  print "-}"
  print "data GraphemeBreak"
  print "  = GbOther"
  split("GbCR GbLF GbControl GbExtend GbZWJ GbRegionalIndicator GbPrepend GbSpacingMark GbL GbV GbT GbLV GbLVT GbExtendedPictographic GbInCBConsonant GbInCBExtend GbInCBLinker GbExtendInCBExtend GbExtendInCBLinker GbZWJInCBExtend", gs, " ")
  for (i = 1; i in gs; i++) print "  | " gs[i]
  print "  deriving stock (Eq, Show, Enum, Bounded)"
  print ""
  print "-- | The Word_Break values, Extended_Pictographic, and ALetter with it."
  print "data WordBreak"
  print "  = WbOther"
  split("WbCR WbLF WbNewline WbExtend WbZWJ WbRegionalIndicator WbFormat WbKatakana WbHebrewLetter WbALetter WbSingleQuote WbDoubleQuote WbMidNumLet WbMidLetter WbMidNum WbNumeric WbExtendNumLet WbWSegSpace WbExtendedPictographic WbALetterExtendedPictographic", ws, " ")
  for (i = 1; i in ws; i++) print "  | " ws[i]
  print "  deriving stock (Eq, Show, Enum, Bounded)"
  print ""
  print "-- | The version of the Unicode data the tables come from."
  print "unicodeVersion :: String"
  print "unicodeVersion = \"" ver "\""
  print ""
  print "-- | The ranges of a value other than GbOther, ascending and disjoint."
  print "graphemeBreakRanges :: [(Int, Int, GraphemeBreak)]"
  print "graphemeBreakRanges ="
  n = 0; have = 0
  for (c = 0; c <= 1114111; c++) {
    v = gvalue(c)
    if (have && v == val) { hi = c; continue }
    if (have && val != "GbOther") entry(n++, sprintf("(0x%04X, 0x%04X, %s)", lo, hi, val))
    have = 1; lo = c; hi = c; val = v
  }
  if (val != "GbOther") entry(n++, sprintf("(0x%04X, 0x%04X, %s)", lo, hi, val))
  printf "\n  ]\n\n"
  print "-- | The ranges of a value other than WbOther, ascending and disjoint."
  print "wordBreakRanges :: [(Int, Int, WordBreak)]"
  print "wordBreakRanges ="
  n = 0; have = 0
  for (c = 0; c <= 1114111; c++) {
    v = wvalue(c)
    if (have && v == val) { hi = c; continue }
    if (have && val != "WbOther") entry(n++, sprintf("(0x%04X, 0x%04X, %s)", lo, hi, val))
    have = 1; lo = c; hi = c; val = v
  }
  if (val != "WbOther") entry(n++, sprintf("(0x%04X, 0x%04X, %s)", lo, hi, val))
  printf "\n  ]\n\n"
  print "-- | The ranges of a General_Category L* or N*, ascending and disjoint."
  print "letterOrNumberRanges :: [(Int, Int)]"
  print "letterOrNumberRanges ="
  n = 0; have = 0
  for (c = 0; c <= 1114111; c++) {
    v = (c in ln) ? 1 : 0
    if (have && v == val) { hi = c; continue }
    if (have && val) entry(n++, sprintf("(0x%04X, 0x%04X)", lo, hi))
    have = 1; lo = c; hi = c; val = v
  }
  if (val) entry(n++, sprintf("(0x%04X, 0x%04X)", lo, hi))
  printf "\n  ]\n"
}
' "$@" >"$tmp" || {
  rm -f "$tmp"
  exit 1
}
mv "$tmp" "$out"
