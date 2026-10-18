// The parts shared by the textlint profiles. Each profile (docs.js, adr.js,
// diagnostics.js, manual.js, manual-dev.js) builds its configuration from
// these. Why each published rule is changed or turned off is written next to
// it here and in ../README.md.
"use strict";

const path = require("path");

const prh = (name) => ({ rulePaths: [path.join(__dirname, "..", "prh", `${name}.yml`)] });

// Words reported for a person to choose the replacement
// (docs/manual-policy.md). The patterns are JavaScript regular expressions.
const words = {
  machine: {
    pattern: "機械(?!語|工業会)",
    message:
      "「機械」と書かない。一台を指すならマシン、演算の仕組みなら計算機、「人の手を介さずに」の意味なら言い換える（docs/manual-policy.md）。",
  },
  machineForUsers: {
    pattern: "機械(?!語|工業会)",
    message: "computer は「機械」と書かず、コンピューターと書く（docs/manual-policy.md）。",
  },
  shell: {
    pattern: "シェル",
    message: "使い手のマニュアルでは「シェル」を使わず、役割で説明する（docs/manual-policy.md）。",
  },
  diagnostic: {
    pattern: "診断",
    message:
      "Golem が報告する誤りや注意は「診断」と書かず、diagnostic（まとまりは diagnostics）と書く（docs/manual-policy.md）。",
  },
  // 効く, 効いて, 効かない... but not 有効, 無効, 効果, 効率 (効 followed by
  // a kana of the verb's endings).
  kiku: {
    pattern: "(?<![有無実発奏特即失])効[かきくけこい]",
    message:
      "マニュアルでは「効く」を使わない。文ごとに「有効」「適用される」「役に立つ」「働く」「左右する」などの正確な語を選ぶ（docs/manual-policy.md）。",
  },
  notice: {
    pattern: "お知らせ",
    message: "開発者に向けた文書では重大度を notice と書く。「お知らせ」は docs/diagnostics.md の値を引くときだけ「」で囲んで使う（docs/manual-policy.md）。",
  },
};

// The published presets for Markdown documents, tuned to the Golem style.
const markdownRules = {
  "preset-ja-technical-writing": {
    // Golem writes counts in kanji (二つ, 一文, 三つ目); docs/manual-policy.md
    // and the existing documents follow it.
    "arabic-kanji-numbers": false,
    // Specification sentences enumerate many items with code spans; 251
    // sentences of the documents exceed 100 characters and shortening them is
    // not mechanical. Left to review.
    "sentence-length": false,
    // 「A も B も」「A と B と」 and relative clauses (〜が指すファイルがない)
    // are Golem's style; nearly all of the 123 reports were of these.
    "no-doubled-joshi": false,
    // The documents are written in the plain style (である).
    "no-mix-dearu-desumasu": {
      preferInHeader: "",
      preferInBody: "である",
      preferInList: "である",
      strict: false,
    },
    // Lists of items separated by 、 are frequent in the specifications.
    "max-ten": { max: 5 },
    // Japanese sentences separate with 、; an ASCII comma appears only in
    // tuples such as (八分, 四分, 二分), which the rule counts as commas.
    "max-comma": false,
    // Repeated words that are not mistakes: ○○ (a placeholder), 一つ一つ,
    // …… (the three-dot leader doubled, as Japanese writes it).
    "ja-no-successive-word": { allow: ["○", "一つ", "…"] },
    // Names of organizations, standards and books.
    "max-kanji-continuous-len": {
      max: 6,
      allow: ["日本産業標準調査会", "日本印刷産業機械工業会", "日本語文字列照合順番", "楕円曲線関数入門", "日本語組版処理"],
    },
  },
  "preset-ja-spacing": {
    // Golem puts a space between full-width and half-width characters
    // ("Golem の"), and around code and links.
    "ja-space-between-half-and-full-width": { space: "always" },
    "ja-space-around-code": { before: true, after: true },
    "ja-space-around-link": { before: true, after: true },
  },
  "@textlint-ja/preset-ai-writing": {
    // "- **語**：説明" is the definition list of glossary.md, roadmap.md and
    // the specifications, not a mannerism.
    "no-ai-list-formatting": false,
    // "Fully static linking" and "exactly the same appearance" are facts,
    // not hype.
    "no-ai-hype-expressions": { allows: ["完全に静的", "完全に同じ"] },
  },
};

const golemRules = (reviewWords) => ({
  "preset-golem": {
    "review-words": { words: reviewWords },
  },
});

// Golem sources (.gm) are read as plain text: Golem's inline commands
// ([code: ...], [note: ...], [index ...]) make the Markdown presets report
// thousands of false positives, so only the rules that look at characters
// and lines (textlint-rule-preset-golem and prh) run on them.
const gmPlugin = { "@textlint/text": { extensions: [".gm"] } };

module.exports = { prh, words, markdownRules, golemRules, gmPlugin };
