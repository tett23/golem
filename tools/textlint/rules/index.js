// textlint-rule-preset-golem: the writing rules of CONTRIBUTING.md that the
// published rules do not cover. See ../README.md.
"use strict";

module.exports = {
  rules: {
    "one-sentence-per-line": require("./one-sentence-per-line"),
    "no-dash": require("./no-dash"),
    "no-nakaguro-listing": require("./no-nakaguro-listing"),
    "review-words": require("./review-words"),
  },
  rulesConfig: {
    "one-sentence-per-line": true,
    "no-dash": true,
    "no-nakaguro-listing": true,
    "review-words": false,
  },
};
