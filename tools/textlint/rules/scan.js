// Line scanner shared by the Golem rules. It reads a Markdown document or a
// Golem source (.gm) as lines, tells what kind of block each line belongs to,
// and masks code with spaces so that the rules see prose only. Columns are
// kept, so an index in the masked line is an index in the source line.
"use strict";

const FENCE = /^\s*(```|~~~)/;
const LIST = /^\s*([-*+]|\d+[.)])\s/;
const DESC = /^\s*=:?\s/; // Golem's description list (= term, =: description)
// A Markdown footnote definition is one block, like a list item: a line that
// continues it would have to be indented.
const FOOTNOTE = /^\[\^[^\]]+\]:/;
const TABLE = /^\s*\|/;
const HEADING = /^#/;
const DIRECTIVE = /^[@%<>]/; // Golem directives and comments, HTML, quotes
const INDENTED = /^\s+\S/;

// Mask `inline code` and Golem's [code: ...] with spaces. A backslash escapes
// the next character in Golem sources.
const maskCode = (line) => {
  const out = line.split("");
  const blank = (from, to) => {
    for (let i = from; i < to; i++) out[i] = " ";
  };
  let i = 0;
  while (i < line.length) {
    if (line[i] === "`") {
      let n = 0;
      while (line[i + n] === "`") n++;
      const tick = "`".repeat(n);
      const end = line.indexOf(tick, i + n);
      if (end < 0) break;
      blank(i, end + n);
      i = end + n;
    } else if (line.startsWith("[code:", i)) {
      let depth = 0;
      let j = i;
      for (; j < line.length; j++) {
        if (line[j] === "\\") {
          j++;
          continue;
        }
        if (line[j] === "[") depth++;
        if (line[j] === "]" && --depth === 0) break;
      }
      blank(i, Math.min(j + 1, line.length));
      i = j + 1;
    } else {
      i++;
    }
  }
  return out.join("");
};

// kind: "code" | "prose" | "list" | "table" | "heading" | "other"
const scanLines = (text) => {
  const lines = text.split("\n");
  let offset = 0;
  let inFence = false;
  let inComment = false;
  let inList = false;
  return lines.map((raw) => {
    const start = offset;
    offset += raw.length + 1;
    const line = raw.replace(/\r$/, "");
    let kind;
    if (FENCE.test(line)) {
      inFence = !inFence;
      kind = "code";
    } else if (inFence) {
      kind = "code";
    } else if (inComment || line.trimStart().startsWith("<!--")) {
      inComment = !line.includes("-->");
      kind = "other";
    } else if (line.trim() === "") {
      inList = false;
      kind = "other";
    } else if (LIST.test(line) || DESC.test(line) || FOOTNOTE.test(line)) {
      inList = true;
      kind = "list";
    } else if (TABLE.test(line)) {
      kind = "table";
    } else if (HEADING.test(line)) {
      kind = "heading";
    } else if (DIRECTIVE.test(line)) {
      kind = "other";
    } else if (inList || INDENTED.test(line)) {
      kind = "list";
    } else {
      kind = "prose";
    }
    return { start, raw: line, text: kind === "code" ? "" : maskCode(line), kind };
  });
};

// Whether the characters at [from, to) are quoted by themselves, as in
// （——） or 「・」: a rule that names the character it forbids.
const quotedAlone = (text, from, to) => {
  const pairs = { "（": "）", "「": "」", "(": ")" };
  const open = text[from - 1];
  return pairs[open] !== undefined && pairs[open] === text[to];
};

// Whether the index is inside 「...」 on the line (a quoted title or word).
const insideKagi = (text, index) => {
  let depth = 0;
  for (let i = 0; i < index; i++) {
    if (text[i] === "「" || text[i] === "『") depth++;
    if ((text[i] === "」" || text[i] === "』") && depth > 0) depth--;
  }
  return depth > 0;
};

module.exports = { scanLines, maskCode, quotedAlone, insideKagi };
