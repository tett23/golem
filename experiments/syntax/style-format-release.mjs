// Compare the tagged rc4 CLI with the executable intended for v1.0.0 (root ADR 0344).
import assert from "node:assert/strict";
import { copyFileSync, cpSync, existsSync, mkdtempSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const allTargets = ["text", "pdf", "html", "epub"];
const [rc4, candidate] = process.argv.slice(2).map((p) => resolve(p));
assert.ok(rc4 && candidate, "supply paths to the rc4 and candidate executables");
const manifest = `chapters = ["a.gm"]
[metadata]
id = "urn:uuid:00000000-0000-4000-8000-000000000344"
title = "style formats"
language = "en"
date = 2026-11-11
[targets.text]
[targets.pdf]
[targets.html]
[targets.epub]
[source]
paragraph-separator = "blank-line"
`;

// One fixture per row of the ADR's table: the text appended to style.toml,
// the rc4 notice, the v1.0.0 error and the text the error is at.
const rows = [
  ["the double braces of [lists] numbers", '\n[lists]\nnumbers = ["{{{n}}}"]\n', "G03114", "G03250", '"{{{n}}}"'],
  ["a sample of [lists] numbers", '\n[lists]\nnumbers = ["({a})"]\n', "G03115", "G03251", '"({a})"'],
  ["the double braces of a running head", '\n[masters.extra]\nrunning-head = { position = "top-outside", content = ["{{title}}"] }\n', "G03116", "G03252", '"{{title}}"'],
  ["[notes] mark-size", '\n[notes]\nmark-size = "0.5zw"\n', "G03117", "G03253", '"0.5zw"'],
];

function build(bin, styleTail, rules = "", flags = [], target = "text") {
  const cwd = mkdtempSync(join(tmpdir(), "style-format-release-"));
  try {
    writeFileSync(join(cwd, "manifest.toml"), manifest + rules);
    const fixture = new URL("../../modules/golem-driver/test/fixtures/tempest/", import.meta.url);
    copyFileSync(new URL("style.toml", fixture), join(cwd, "style.toml"));
    const style = readFileSync(join(cwd, "style.toml"), "utf8") + styleTail;
    writeFileSync(join(cwd, "style.toml"), style);
    cpSync(new URL("fonts/", fixture), join(cwd, "fonts"), { recursive: true });
    writeFileSync(join(cwd, "a.gm"), "Text[note: A note.] here.\n\n+ one\n+ two\n");
    const r = spawnSync(bin, ["build", "--target", target, "--format", "json", ...flags], { cwd, encoding: "utf8" });
    if (r.error) throw r.error;
    return { exit: r.status, diagnostics: JSON.parse(r.stderr), style, written: existsSync(join(cwd, "build", target)) };
  } finally { rmSync(cwd, { recursive: true, force: true }); }
}

const sites = (result) => result.diagnostics.map((d) => [d.code, d.severity, d.span.file, d.span.start]);

test("root ADR 0344 I3: one old form changes from an rc4 notice to a v1 error at the value", () => {
  assert.match(spawnSync(rc4, ["--version"], { encoding: "utf8" }).stdout, /0\.1\.0-rc4\b/);
  for (const [name, tail, notice, error, at] of rows) {
    const before = build(rc4, tail);
    const offset = [...before.style.slice(0, before.style.lastIndexOf(at))].length;
    assert.equal(before.exit, 0, name);
    assert.deepEqual(sites(before), [[notice, "notice", "style.toml", offset]], name);
    const after = build(candidate, tail);
    assert.equal(after.exit, 1, name);
    assert.deepEqual(sites(after), [[error, "error", "style.toml", offset]], name);
    assert.equal(after.written, false, name);
  }
});

test("root ADR 0344 I4: only rc4 accepts the retired codes in silence-notices", () => {
  for (const [, , notice] of rows) {
    const rules = `\n[diagnostics]\nsilence-notices = ["${notice}"]\n`;
    const before = build(rc4, "", rules);
    assert.deepEqual([before.exit, before.diagnostics], [0, []], notice);
    const after = build(candidate, "", rules);
    assert.equal(after.exit, 1, notice);
    assert.deepEqual(after.diagnostics.map((d) => [d.code, d.span.file]), [["G03024", "manifest.toml"]], notice);
  }
});

test("root ADR 0344 I5: the size conflicts of ADR 0214 are G03006 in rc4 and G03253 in v1", () => {
  const conflicts = [
    ['[character-styles.note-mark]\nsize = "0.6zw"\n', ""],
    ['[character-styles.big]\nsize = "0.6zw"\n[character-styles.note-mark]\nbased-on = "big"\n', ""],
    ['[character-styles.note-mark]\nsize = "0.6zw"\n', 'mark-style = "note-mark"\n'],
    ['[character-styles.mine]\nsize = "0.6zw"\n', 'mark-style = "mine"\n'],
    ['[character-styles.big]\nsize = "0.6zw"\n[character-styles.mine]\nbased-on = "big"\n', 'mark-style = "mine"\n'],
  ];
  for (const [styles, notes] of conflicts) {
    const tail = "\n" + styles + '[notes]\nmark-size = "0.65zw"\n' + notes;
    const before = build(rc4, tail);
    assert.equal(before.exit, 1, tail);
    assert.deepEqual(before.diagnostics.map((d) => d.code), ["G03006"], tail);
    const after = build(candidate, tail);
    assert.equal(after.exit, 1, tail);
    assert.deepEqual(after.diagnostics.map((d) => d.code), ["G03253"], tail);
  }
});

test("root ADR 0344 I2: every target fails with each error once, also with --no-notices", () => {
  const tail = '\n[lists]\nnumbers = ["{{{n}}}", "({a})"]\n' + rows.slice(2).map(([, t]) => t).join("");
  for (const target of allTargets) {
    const result = build(candidate, tail, "", ["--no-notices"], target);
    assert.equal(result.exit, 1, target);
    assert.deepEqual(result.diagnostics.map((d) => d.code), ["G03250", "G03251", "G03252", "G03253"], target);
    assert.equal(result.written, false, target);
  }
});

test("root ADR 0344 I1: the new forms build every target with none of the four errors", () => {
  const tail = "\n[lists]\nnumbers = ['\\{{n:lower-alpha}\\}']\n[masters.extra]\nrunning-head = { position = \"top-outside\", content = ['\\{title\\}'] }\n[character-styles.note-mark]\nsize = \"0.5zw\"\n";
  for (const target of allTargets) {
    const result = build(candidate, tail, "", [], target);
    assert.equal(result.exit, 0, target);
    assert.deepEqual(result.diagnostics.filter((d) => /^G0325[0-3]$/.test(d.code) || d.severity === "error"), [], target);
    assert.equal(result.written, true, target);
  }
});
