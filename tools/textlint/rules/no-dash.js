// No dashes (U+2014, U+2015) in prose. Code, and a dash quoted by itself as in
// （——）, are not prose (CONTRIBUTING.md, "日本語の文章").
"use strict";

const { scanLines, quotedAlone } = require("./scan");

const DASH = /[—―]+/g;

module.exports = (context) => {
  const { Syntax, getSource, report, RuleError, locator } = context;
  return {
    [Syntax.Document](node) {
      for (const line of scanLines(getSource(node))) {
        for (const m of line.text.matchAll(DASH)) {
          if (quotedAlone(line.text, m.index, m.index + m[0].length)) continue;
          report(
            node,
            new RuleError("地の文でダッシュを使わない。読点、括弧、文の区切りで書き直す。", {
              padding: locator.range([line.start + m.index, line.start + m.index + m[0].length]),
            }),
          );
        }
      }
    },
  };
};
