// The configuration for the tests: the Golem rules and the dictionaries
// alone, without the published presets.
"use strict";

const { prh, gmPlugin } = require("../config/common");

module.exports = {
  plugins: gmPlugin,
  rules: {
    "preset-golem": {
      "review-words": { words: [{ pattern: "機械(?!語)", message: "machine" }] },
    },
    prh: prh(process.env.GOLEM_TEXTLINT_TEST_PRH || "dev"),
  },
};
