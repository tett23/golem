// docs/**/*.md (but the ADRs, docs/diagnostics.md and the records),
// README.md and CONTRIBUTING.md. The severity is written notice, not お知らせ,
// as in the developer manual (docs/manual-policy.md).
"use strict";

const { prh, words, markdownRules, golemRules } = require("./common");

module.exports = {
  rules: {
    ...markdownRules,
    ...golemRules([words.machine, words.notice, words.kiku]),
    prh: prh("dev"),
  },
};
