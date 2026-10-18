// The user manual (manual/**/*.gm).
"use strict";

const { prh, words, golemRules, gmPlugin } = require("./common");

module.exports = {
  plugins: gmPlugin,
  rules: {
    ...golemRules([words.machineForUsers, words.shell, words.kiku]),
    prh: prh("user"),
  },
};
