// Tests of textlint-rule-preset-golem and the prh dictionaries
// (docs/adr/0036-textlint-for-documents.md). Run with
//   node --test tools/textlint/test/
// Each case lints a text through the textlint command and compares the rules
// that report.
"use strict";

const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { spawn } = require("node:child_process");
const path = require("node:path");

const TOOL = path.join(__dirname, "..");
const TEXTLINT = path.join(TOOL, "node_modules", ".bin", "textlint");
const CONFIG = path.join(__dirname, "config.js");

const lint = (text, { ext = "md", prh = "dev" } = {}) =>
  new Promise((resolve, reject) => {
    const p = spawn(TEXTLINT, ["--config", CONFIG, "--format", "json", "--stdin", "--stdin-filename", `case.${ext}`], {
      env: { ...process.env, GOLEM_TEXTLINT_TEST_PRH: prh },
    });
    let out = "";
    let err = "";
    p.stdout.on("data", (d) => (out += d));
    p.stderr.on("data", (d) => (err += d));
    p.on("error", reject);
    p.on("close", () => {
      if (!out) return reject(new Error(`textlint printed nothing: ${err}`));
      resolve(JSON.parse(out)[0].messages.map((m) => `${m.line}:${m.ruleId.replace(/^golem\//, "")}`));
    });
    p.stdin.end(text);
  });

const cases = [
  // one sentence per line
  ["two sentences on a line", "一文目である。二文目である。\n", {}, ["1:one-sentence-per-line"]],
  ["a sentence per line", "一文目である。\n二文目である。\n", {}, []],
  ["a list item may hold sentences", "- 一文目である。二文目である。\n", {}, []],
  ["a continued list item", "- 項目である。\n  続きである。次の文である。\n", {}, []],
  ["a table cell may hold sentences", "| 列 |\n| --- |\n| 一文。二文。 |\n", {}, []],
  ["a footnote definition is one block", "本文[^a]。\n\n[^a]: **語**：定義。説明。\n", {}, []],
  ["a sentence inside brackets", "例（これは例である。）を書く。\n", {}, []],
  ["a sentence inside quotes", "「止まる。」と書く。\n", {}, []],
  ["code is not prose", "`a。b` を書く。\n", {}, []],
  ["a fenced block is code", "```\n一。二。\n```\n", {}, []],
  ["a heading is not a paragraph", "# 一。二。\n", {}, []],
  ["a link after the end", "参照する。[仕様](a.md) を読む。\n", {}, ["1:one-sentence-per-line"]],
  ["Golem: a note after the end", "従う。[note: 注である。二つ目。]\n", { ext: "gm" }, []],
  ["Golem: a second sentence", "一つ目である。二つ目である。\n", { ext: "gm" }, ["1:one-sentence-per-line"]],
  ["Golem: a description list", "= 語\n=: 説明である。続きである。\n", { ext: "gm" }, []],
  ["Golem: a directive", "@caption 一。二。\n", { ext: "gm" }, []],
  // dashes
  ["an em dash", "これは——例である。\n", {}, ["1:no-dash"]],
  ["a horizontal bar", "これは――例である。\n", {}, ["1:no-dash"]],
  ["a dash named in brackets", "ダッシュ（——）を使わない。\n", {}, []],
  ["a dash in code", "`—` は分離禁止文字である。\n", {}, []],
  ["Golem: a dash in code", "二倍ダッシュの [code: —] を組む。\n", { ext: "gm" }, []],
  ["a dash in a list item", "- これは——例である。\n", {}, ["1:no-dash"]],
  // 中黒
  ["a nakaguro listing", "明朝・ゴシックを使う。\n", {}, ["1:no-nakaguro-listing"]],
  ["a nakaguro in a loanword", "マルチ・カラムを使う。\n", {}, []],
  ["a nakaguro named in brackets", "中黒（・）を使わない。\n", {}, []],
  ["a nakaguro in code", "`・` は中点類である。\n", {}, []],
  // review words
  ["a review word", "機械が読む。\n", {}, ["1:review-words"]],
  ["a review word excepted by the pattern", "機械語にする。\n", {}, []],
  ["a review word named in quotes", "「機械」と書かない。\n", {}, []],
  ["a review word in a quoted title", "ADR 0001「機械の話」を読む。\n", {}, []],
  ["a review word: 効く", "PDF にだけ効く。\n", {}, ["1:review-words"]],
  ["a review word: 効いて", "CI で効いてくる。\n", {}, ["1:review-words"]],
  ["not a review word: 有効", "PDF でだけ有効である。\n", {}, []],
  ["not a review word: 効果", "効果がある。\n", {}, []],
  // prh
  ["prh: upstream for developers", "本流に送る。\n", {}, ["1:prh"]],
  ["prh: public domain","公有の作品である。\n", {}, ["1:prh"]],
  ["prh: public domain in a quoted title", "ADR 0026「組みにくい公有の作品を fixture に十作加える」\n", {}, []],
  ["prh: asset for developers", "リリースの資産である。\n", {}, ["1:prh"]],
  ["prh: asset named in quotes", "「資産」と書かない。\n", {}, []],
  ["prh: asset is not a rule for users", "リリースの資産である。\n", { prh: "user" }, []],
  ["prh: tool for users", "外部の道具を使う。\n", { prh: "user" }, ["1:prh"]],
];

describe("textlint-rule-preset-golem and prh", { concurrency: true }, () => {
  for (const [name, text, opts, expected] of cases) {
    test(name, async () => assert.deepEqual(await lint(text, opts), expected));
  }
});
