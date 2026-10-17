// One Japanese sentence per line in paragraphs. List items and table cells may
// hold several sentences (CONTRIBUTING.md, "日本語の文章").
"use strict";

const { scanLines } = require("./scan");

const OPEN = new Set(["（", "「", "『", "【", "［", "(", "["]);
const CLOSE = new Set(["）", "」", "』", "】", "］", ")", "]"]);

// The index of the first 。 outside brackets that has more text after it
// (outside brackets) on the same line, or -1.
const secondSentence = (text) => {
  let depth = 0;
  let end = -1;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (OPEN.has(c)) depth++;
    else if (CLOSE.has(c)) depth = Math.max(0, depth - 1);
    else if (depth === 0) {
      if (c === "。") {
        if (end < 0) end = i;
      } else if (end >= 0 && !/\s/.test(c)) {
        return end;
      }
    }
  }
  return -1;
};

module.exports = (context) => {
  const { Syntax, getSource, report, RuleError, locator } = context;
  return {
    [Syntax.Document](node) {
      for (const line of scanLines(getSource(node))) {
        if (line.kind !== "prose") continue;
        const at = secondSentence(line.text);
        if (at < 0) continue;
        report(
          node,
          new RuleError("一文ごとに改行する（箇条書きと表のセルを除く）。", {
            padding: locator.range([line.start + at, line.start + at + 1]),
          }),
        );
      }
    },
  };
};

module.exports.secondSentence = secondSentence;
