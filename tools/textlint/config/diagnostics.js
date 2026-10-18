// docs/diagnostics.md. Its section titles and quoted messages are the
// messages Golem shows to users: the polite style (です, ます) without a final
// 。, in a form the build checks, and some of them name Golem's brackets
// ("[ の後にコマンド名も = もありません"). The checks of the sentence end, of
// the style and of the brackets are off for this document only.
"use strict";

const { prh, words, markdownRules, golemRules } = require("./common");

module.exports = {
  rules: {
    ...markdownRules,
    "preset-ja-technical-writing": {
      ...markdownRules["preset-ja-technical-writing"],
      "ja-no-mixed-period": false,
      "no-mix-dearu-desumasu": false,
      "no-unmatched-pair": false,
    },
    "preset-ja-spacing": {
      ...markdownRules["preset-ja-spacing"],
      "ja-no-space-around-parentheses": false,
    },
    ...golemRules([words.machine, words.kiku]),
    prh: prh("dev"),
  },
};
