#!/usr/bin/env python3
"""Converts an Aozora Bunko text (ruby edition, UTF-8) into Golem source.

Handled: ruby 《》 and ｜, emphasis dots ［＃「…」に傍点］, tate-chu-yoko
［＃「…」は縦中横］, headings ［＃「…」は大／中／小見出し］, the gaiji used
in the text, and the colophon (kept at the end, as the Aozora terms ask).
Layout annotations (字下げ, 字詰め, 罫囲み, 地付き) are dropped.

Usage: aozora_to_gm.py INPUT.txt OUTPUT.gm
"""
import re
import sys

SPECIAL_LINE_START = "#-+=@|"

GAIJI = {
    "二の字点": "〻",
    "感嘆符疑問符": "⁉",
    "疑問符感嘆符": "⁈",
    "感嘆符二つ": "‼",
}


def is_kanji(c):
    return "\u4e00" <= c <= "\u9fff" or "\u3400" <= c <= "\u4dbf" or c in "々〆ヶ〻※"


def char_class(c):
    if is_kanji(c):
        return "kanji"
    if "\u30a0" <= c <= "\u30ff":
        return "katakana"
    if "\u3040" <= c <= "\u309f":
        return "hiragana"
    if c.isascii() and c.isalnum() or "\uff10" <= c <= "\uff5a":
        return "alnum"
    return "other"


def slot(s):
    return s.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]").replace("|", "\\|").replace("/", "\\/")


def text_escape(s):
    return s.replace("\\", "\\\\").replace("[", "\\[").replace("%%", "\\%%")


def gaiji(m):
    note = m.group(1)
    name = note.split("、")[0]
    if name in GAIJI:
        return GAIJI[name]
    u = re.search(r"U\+([0-9A-Fa-f]{4,6})", note)
    if u:
        return chr(int(u.group(1), 16))
    return "〓"


def convert_line(line):
    """Returns the Golem text of one line and its heading level, if any."""
    line = re.sub(r"※［＃([^］]*)］", gaiji, line)
    heading = None
    m = re.search(r"［＃「([^」]*)」は(大|中|小)見出し］", line)
    if m:
        heading = {"大": 1, "中": 1, "小": 2}[m.group(2)]
        line = m.group(1)
    # emphasis and tate-chu-yoko: mark the preceding text, ruby still raw
    marks = []

    def mark(kind):
        def rep(m):
            marks.append((kind, m.group(1)))
            return "\u0000%d\u0000" % (len(marks) - 1)
        return rep

    line = re.sub(r"［＃「([^」]*)」に傍点］", mark("kenten"), line)
    line = re.sub(r"［＃「([^」]*)」は縦中横］", mark("tcy"), line)
    line = re.sub(r"［＃[^］]*］", "", line)  # layout annotations

    # tokens: ruby, marks, plain characters
    out = []  # list of (golem text, plain text)

    def emit(g, p):
        out.append((g, p))

    i = 0
    while i < len(line):
        c = line[i]
        if c == "｜" and "《" in line[i:]:
            j = line.index("《", i)
            k = line.index("》", j)
            base, reading = line[i + 1:j], line[j + 1:k]
            emit("[ruby: " + slot(base) + "|" + slot(reading) + "]", base)
            i = k + 1
        elif c == "《":
            k = line.index("》", i)
            reading = line[i + 1:k]
            # the base: the run of same-class characters just before
            plain = "".join(p for _, p in out)
            cls = char_class(plain[-1]) if plain else "other"
            n = 0
            while n < len(plain) and char_class(plain[-1 - n]) == cls and len(out) > 0:
                n += 1
            # take the base back out of the emitted plain characters
            base_chars = []
            while len(base_chars) < n and out and out[-1][0] == out[-1][1] and len(out[-1][1]) == 1:
                base_chars.insert(0, out.pop()[1])
            base = "".join(base_chars)
            if base:
                emit("[ruby: " + slot(base) + "|" + slot(reading) + "]", base)
            else:
                emit(text_escape("《" + reading + "》"), "《" + reading + "》")
            i = k + 1
        elif c == "\u0000":
            k = line.index("\u0000", i + 1)
            kind, target = marks[int(line[i + 1:k])]
            plain = "".join(p for _, p in out)
            if plain.endswith(target):
                # pull the target's tokens back out
                taken, got = [], ""
                while out and len(got) < len(target):
                    g, p = out.pop()
                    taken.insert(0, (g, p))
                    got = p + got
                inner = "".join(g for g, _ in taken)
                if kind == "kenten":
                    emit("[kenten: " + inner + "]", got)
                else:
                    emit("[tcy: " + slot(got) + "]", got)
            i = k + 1
        else:
            emit(text_escape(c), c)
            i += 1
    s = "".join(g for g, _ in out)
    if s and s[0] in SPECIAL_LINE_START:
        s = "\\" + s
    return s, heading


def convert(src):
    lines = src.replace("\r\n", "\n").split("\n")
    title, author = lines[0].strip(), lines[1].strip()
    # skip the explanation of the notation between the dashed lines
    dashes = [i for i, l in enumerate(lines) if l.startswith("-------")]
    body = lines[dashes[1] + 1:]
    colophon_at = next(i for i, l in enumerate(body) if l.startswith("底本："))
    text, colophon = body[:colophon_at], body[colophon_at:]
    out = []
    for l in text:
        if not l.strip():
            continue
        g, heading = convert_line(l)
        if heading:
            out.append("@nonumber\n" + "#" * heading + " " + g)
        elif g.strip():
            out.append(g)
    out.append("@nonumber\n# 底本と作成者")
    out.extend(text_escape(l.strip()) for l in colophon if l.strip())
    return "\n\n".join(out) + "\n", title, author


def main():
    src = open(sys.argv[1], encoding="utf-8").read()
    gm, _, _ = convert(src)
    open(sys.argv[2], "w", encoding="utf-8").write(gm)


if __name__ == "__main__":
    main()
