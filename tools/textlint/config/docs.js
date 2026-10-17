// docs/**/*.md (but the ADRs, docs/diagnostics.md and the records),
// README.md and CONTRIBUTING.md.
"use strict";

const { prh, words, markdownRules, golemRules } = require("./common");

module.exports = {
  rules: {
    ...markdownRules,
    ...golemRules([words.machine]),
    prh: prh("dev"),
  },
};
