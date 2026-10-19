// The developer manual (manual-dev/**/*.gm).
"use strict";

const { prh, words, golemRules, gmPlugin } = require("./common");

module.exports = {
  plugins: gmPlugin,
  rules: {
    ...golemRules([words.machine, words.diagnostic, words.notice, words.kiku, words.key]),
    prh: prh("dev"),
  },
};
