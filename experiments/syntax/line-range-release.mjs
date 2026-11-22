// Compare the tagged rc4 CLI with the executable intended for v1.0.0.
import assert from "node:assert/strict";
import { copyFileSync, cpSync, existsSync, mkdtempSync, readdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const [rc4, candidate] = process.argv.slice(2).map((p) => resolve(p));
assert.ok(rc4 && candidate, "supply paths to the rc4 and candidate executables");
const manifest = `chapters = ["a.gm"]
[metadata]
id = "urn:uuid:00000000-0000-4000-8000-000000000163"
title = "listing"
language = "ja"
date = 2026-11-11
[targets.text]
[targets.pdf]
[targets.html]
[targets.epub]
[source]
paragraph-separator = "blank-line"
`;

function build(bin, line, rules = "", flags = [], target = "text") {
  const cwd = mkdtempSync(join(tmpdir(), "listing-release-"));
  try {
    writeFileSync(join(cwd, "manifest.toml"), manifest + rules);
    const fixture = new URL("../../modules/golem-driver/test/fixtures/tempest/", import.meta.url);
    copyFileSync(new URL("style.toml", fixture), join(cwd, "style.toml"));
    cpSync(new URL("fonts/", fixture), join(cwd, "fonts"), { recursive: true });
    writeFileSync(join(cwd, "a.gm"), line + "\n");
    writeFileSync(join(cwd, "a.txt"), "first\nsecond\nthird\nfourth\nfifth\n");
    const r = spawnSync(bin, ["build", "--target", target, "--format", "json", ...flags], { cwd, encoding: "utf8" });
    if (r.error) throw r.error;
    if (r.status === 1) assert.equal(existsSync(join(cwd, "build", target)), false);
    const out = join(cwd, "build", target);
    const files = existsSync(out) ? readdirSync(out, { recursive: true }).map(String).sort() : [];
    const text = target === "text" ? files.filter(f => f.endsWith(".txt")).map(f => readFileSync(join(out, f), "utf8")).join("") : "";
    return { exit: r.status, diagnostics: JSON.parse(r.stderr), files, text };
  } finally { rmSync(cwd, { recursive: true, force: true }); }
}


test("root ADR 0342 I3: a single old separator changes from an rc4 notice to a v1 error", () => {
  assert.match(spawnSync(rc4, ["--version"], { encoding: "utf8" }).stdout, /0\.1\.0-rc4\b/);
  const line = "@listing a.txt lines=1-2";
  for (const [bin, code, severity, exit] of [
    [rc4, "G02108", "notice", 0],
    [candidate, "G02251", "error", 1],
  ]) {
    const result = build(bin, line);
    assert.equal(result.exit, exit);
    assert.deepEqual(result.diagnostics.map(d => [d.code, d.severity]), [[code, severity]]);
  }
});

test("root ADR 0342 I4: only rc4 accepts G02108 in silence-notices", () => {
  const rules = '\n[diagnostics]\nsilence-notices = ["G02108"]\n';
  const before = build(rc4, "@listing a.txt", rules);
  assert.deepEqual([before.exit, before.diagnostics], [0, []]);
  const result = build(candidate, "@listing a.txt", rules);
  assert.equal(result.exit, 1);
  assert.deepEqual(result.diagnostics.map(d => d.code), ["G03024"]);
});

test("root ADR 0342 I2: each target rejects the entire legacy line argument once", () => {
  const line = "@listing a.txt lines=1-2,4-5";
  for (const target of ["pdf", "epub", "html", "text"]) {
    const result = build(candidate, line, "", ["--no-notices"], target);
    assert.equal(result.exit, 1, target);
    assert.deepEqual(result.diagnostics.map(d => [d.code, d.span.start, d.span.end]),
      [["G02251", line.indexOf("lines="), line.length]], target);
  }
});

test("root ADR 0342 I1: each target builds a list of lines and ranges in the order written", () => {
  const line = '@listing a.txt lines="4...5, 1"';
  for (const target of ["pdf", "epub", "html", "text"]) {
    const result = build(candidate, line, "", [], target);
    assert.equal(result.exit, 0, target);
    assert.deepEqual(result.diagnostics.filter(d => d.severity === "error"), [], target);
    assert.ok(result.files.length > 0, target);
    if (target === "text") assert.match(result.text, /fourth\s+fifth\s+first/);
    if (target === "text") assert.doesNotMatch(result.text, /second|third/);
  }
});
