#!/usr/bin/env python3
"""Converts a Shakespeare play of the Project Gutenberg Cambridge edition
(plain text, UTF-8) into Golem source.

Kept: the list of characters and the play to the end of the epilogue.
Dropped: the Gutenberg header and licence, the transcriber's note, the
title page, footnotes and textual notes, line numbers.

Verse becomes @verse (docs/adr ADR 0003). The source marks verse only by
its line breaks, which prose also has where it was wrapped, so verse is
guessed: a speech of two lines or more whose every line after the first
starts a half line, is a stage direction, or starts with a capital, and a
song indented as a whole. Short prose speeches of capitalised lines are
taken for verse.

Usage: gutenberg_play_to_gm.py INPUT.txt OUTPUT.gm
"""
import re
import sys

SPECIAL_LINE_START = "#-+=@|"


def inline(text, in_slot=False):
    """_x_ toggles italic; [ is escaped; %% is escaped."""
    return inline_from(text, False, in_slot)[0]


def inline_from(text, italic, in_slot=False):
    """inline() starting in the given italic state; returns the text and the
    italic state at its end, so that italic can continue on the next line."""
    out = []
    buf = []

    def flush():
        s = "".join(buf)
        buf.clear()
        if not s:
            return
        if italic:
            # spaces at the edges stay outside: the ends of a slot are not text
            lead = s[: len(s) - len(s.lstrip(" "))]
            trail = s[len(s.rstrip(" ")):]
            core = s.strip(" ").replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]").replace("|", "\\|")
            out.append(lead + ("[italic: " + core + "]" if core else "") + trail)
        else:
            s = s.replace("\\", "\\\\").replace("[", "\\[")
            if in_slot:
                s = s.replace("]", "\\]").replace("|", "\\|")
            out.append(s)

    for ch in text:
        if ch == "_":
            flush()
            italic = not italic
        else:
            buf.append(ch)
    flush()
    s = "".join(out).replace("%%", "\\%%")
    return s, italic


def paragraph(text):
    s = inline(text)
    if s and s[0] in SPECIAL_LINE_START:
        s = "\\" + s
    return s


def strip_line_number(line):
    return re.sub(r"\s{2,}\d+\s*$", "", line)


SPEAKER = re.compile(r"^_([^_]+)_\s*(.*)$")
STAGE_ONLY = re.compile(r"^\[_[^_]*_\]?$")


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def verse_continues(line):
    """Whether a line after the first is a line of verse: a half line, a
    stage direction alone, or a capital after a stage direction, quotes and
    apostrophes."""
    if indent_of(line) >= 4:
        return True
    s = strip_line_number(line).strip()
    if STAGE_ONLY.match(s):
        return True
    s = re.sub(r"^\[_[^\]]*\]\s*", "", s).lstrip("\"“”‘’'")
    return bool(s) and s[0].isupper()


def is_verse(b):
    """Speeches and their continuations of two lines or more whose lines are
    verse, and songs and masque speeches indented as a whole."""
    if len(b) < 2:
        return False
    first = b[0]
    rest = b[1:]
    if indent_of(first) == 0:
        m = SPEAKER.match(first)
        speech = m and m.group(1).endswith(".")
        continuation = not first.startswith("_") and not first.startswith("[")
        # a song after a stage direction on its first line: "[_Sings._ The master, ..."
        sung = first.startswith("[_") and not STAGE_ONLY.match(strip_line_number(first).strip()) and all(indent_of(l) >= 4 for l in rest)
        return bool(speech or continuation) and all(verse_continues(l) for l in rest) or sung
    if indent_of(first) == 2 and SPEAKER.match(first.strip()) and SPEAKER.match(first.strip()).group(1).endswith("."):
        return all(indent_of(l) >= 4 for l in rest)
    if indent_of(first) >= 4 and not first.strip().startswith(("_", "[")):
        return all(indent_of(l) >= 4 for l in b)
    return False


def verse(b):
    """@verse: one line of source per line of verse, the speaker's name on the
    first; italic is closed at the end of each line and opened again."""
    lines = [re.sub(r"\s+", " ", strip_line_number(l).strip()).replace("--", "—") for l in b]
    out = []
    italic = False
    for i, l in enumerate(lines):
        prefix = ""
        if i == 0:
            m = SPEAKER.match(l)
            if m and m.group(1).endswith("."):
                prefix = "[strong: " + inline(m.group(1), in_slot=True) + "] "
                l = m.group(2)
        s, italic = inline_from(l, italic)
        s = (prefix + s).rstrip()
        if not s:
            continue
        if s[0] in SPECIAL_LINE_START:
            s = "\\" + s
        out.append("  " + s)
    return "@verse\n" + "\n".join(out)


def convert(src):
    body = src.split("*** START OF THE PROJECT GUTENBERG EBOOK")[1].split("*** END OF THE PROJECT GUTENBERG EBOOK")[0]
    lines = body.split("\n")[1:]
    start = next(i for i, l in enumerate(lines) if l.startswith("DRAMATIS PERSON"))
    end = next(i for i, l in enumerate(lines) if l.strip() == "NOTES.")
    lines = lines[start:end]

    blocks, cur = [], []
    for l in lines:
        if l.strip() == "":
            if cur:
                blocks.append(cur)
                cur = []
        else:
            cur.append(l.rstrip())
    if cur:
        blocks.append(cur)

    out = []
    in_dramatis = False
    in_notes = False
    for b in blocks:
        first = b[0].strip()
        # textual notes run from "Notes: ..." to the next act, scene or epilogue
        if first.startswith("Notes:"):
            in_notes = True
            continue
        if in_notes:
            if re.match(r"^(ACT [IVX]+\.|SCENE [IVX]+\.|EPILOGUE\.)", first) and len(b[0]) == len(b[0].lstrip()):
                in_notes = False
            else:
                continue
        # footnotes and textual notes
        if first == "Footnotes:" or re.match(r"^\s+\d+(-\d+)?:", b[0]):
            continue
        if first.startswith("DRAMATIS PERSON"):
            out.append("@nonumber\n# Dramatis Personæ")
            in_dramatis = True
            continue
        if first == "THE TEMPEST.":
            continue
        m = re.match(r"^ACT ([IVX]+)\.$", first)
        if m:
            in_dramatis = False
            out.append("@nonumber\n# Act " + m.group(1))
            continue
        m = re.match(r"^SCENE ([IVX]+)\.\s*(.*)$", first)
        if m and len(b[0]) == len(b[0].lstrip()):
            rest = " ".join([m.group(2)] + [x.strip() for x in b[1:]]).strip()
            out.append("@nonumber\n## Scene " + m.group(1))
            if rest:
                out.append(paragraph(rest))
            continue
        if first == "EPILOGUE.":
            out.append("@nonumber\n# Epilogue")
            if len(b) > 1:
                out.append(paragraph(" ".join(x.strip() for x in b[1:])))
            continue
        if first.startswith("SCENE--"):
            out.append(paragraph(first.replace("--", "—")))
            continue
        if in_dramatis:
            # one character per line: a list
            out.append("\n".join("- " + inline(re.sub(r"\[\d+\]", "", x.strip())) for x in b))
            continue
        if is_verse(b):
            out.append(verse(b))
            continue
        text = " ".join(strip_line_number(x).strip() for x in b)
        text = re.sub(r"\s+", " ", text).replace("--", "—")
        m = re.match(r"^_([^_]+)_\s*(.*)$", text)
        if m and len(b[0]) == len(b[0].lstrip()) and m.group(1).endswith("."):
            # a speech: the speaker's name, then the words
            out.append(("[strong: " + inline(m.group(1), in_slot=True) + "] " + inline(m.group(2))).rstrip())
        else:
            # stage directions and continuations
            out.append(paragraph(text))
    return "\n\n".join(out) + "\n"


def main():
    src = open(sys.argv[1], encoding="utf-8").read()
    open(sys.argv[2], "w", encoding="utf-8").write(convert(src))


if __name__ == "__main__":
    main()
