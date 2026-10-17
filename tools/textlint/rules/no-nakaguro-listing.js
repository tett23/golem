// No 中黒 (・) for parallel listing; separate the items with 、. A 中黒 between
// katakana, as in a loanword split into words, is allowed, so that case is left
// to review (CONTRIBUTING.md, "日本語の文章").
"use strict";

const { scanLines, quotedAlone } = require("./scan");

const NAKAGURO = /[・･]/g;
const KATAKANA = /[゠-ヺー-ヿｦ-ﾟ]/;

module.exports = (context) => {
  const { Syntax, getSource, report, RuleError, locator } = context;
  return {
    [Syntax.Document](node) {
      for (const line of scanLines(getSource(node))) {
        for (const m of line.text.matchAll(NAKAGURO)) {
          const i = m.index;
          if (quotedAlone(line.text, i, i + 1)) continue;
          if (KATAKANA.test(line.text[i - 1] || "") && KATAKANA.test(line.text[i + 1] || "")) continue;
          report(
            node,
            new RuleError("並列を中黒で表さない。読点（、）か「と」で並べる。", {
              padding: locator.range([line.start + i, line.start + i + 1]),
            }),
          );
        }
      }
    },
  };
};
