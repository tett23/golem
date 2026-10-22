// ADRs that the branch adds (docs/adr/, docs/<module>/adr/). Committed ADRs
// cannot change, so they are not checked. New ADRs follow the term rules of
// the developer manual from now on, diagnostic included.
"use strict";

const { prh, words, markdownRules, golemRules } = require("./common");

// An ADR has the status line "ステータス: 提案" (adr-guard checks it) and
// "なし" for no references, neither ending with 。, so the check of the
// sentence end is off.
module.exports = {
  rules: {
    ...markdownRules,
    "preset-ja-technical-writing": {
      ...markdownRules["preset-ja-technical-writing"],
      "ja-no-mixed-period": false,
    },
    ...golemRules([words.machine, words.diagnostic, words.notice, words.kiku, words.key, words.sidenoteArea]),
    prh: prh("dev"),
  },
};
