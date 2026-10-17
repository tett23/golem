// Words whose replacement depends on the meaning, so that they are reported
// for a person to choose, never fixed automatically. Code and words inside
// 「」 (a quoted title, or the word named as a word) are skipped.
//
// options.words: [{ pattern: "regular expression", message: "..." }]
"use strict";

const { scanLines, insideKagi } = require("./scan");

module.exports = (context, options = {}) => {
  const { Syntax, getSource, report, RuleError, locator } = context;
  const words = (options.words || []).map((w) => ({ re: new RegExp(w.pattern, "g"), message: w.message }));
  return {
    [Syntax.Document](node) {
      for (const line of scanLines(getSource(node))) {
        for (const w of words) {
          for (const m of line.text.matchAll(w.re)) {
            if (insideKagi(line.text, m.index)) continue;
            report(
              node,
              new RuleError(w.message, {
                padding: locator.range([line.start + m.index, line.start + m.index + m[0].length]),
              }),
            );
          }
        }
      }
    },
  };
};
