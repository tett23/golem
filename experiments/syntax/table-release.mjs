// Compare the tagged rc4 CLI with the executable intended for v1.0.0.
import assert from "node:assert/strict";
import { copyFileSync, cpSync, existsSync, mkdtempSync, writeFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";
import { test } from "node:test";

const allTargets = ["text", "pdf", "html", "epub"];
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
  const cwd = mkdtempSync(join(tmpdir(), "table-release-"));
  try {
    writeFileSync(join(cwd, "manifest.toml"), manifest + rules);
    const fixture = new URL("../../modules/golem-driver/test/fixtures/tempest/", import.meta.url);
    copyFileSync(new URL("style.toml", fixture), join(cwd, "style.toml"));
    cpSync(new URL("fonts/", fixture), join(cwd, "fonts"), { recursive: true });
    writeFileSync(join(cwd, "a.gm"), line + "\n");
    writeFileSync(join(cwd, "t.csv"), "a,b\nc,d\n");
    const r = spawnSync(bin, ["build", "--target", target, "--format", "json", ...flags], { cwd, encoding: "utf8" });
    if (r.error) throw r.error;
    if (r.status === 1) assert.equal(existsSync(join(cwd, "build", target)), false);
    return { exit: r.status, diagnostics: JSON.parse(r.stderr) };
  } finally { rmSync(cwd, { recursive: true, force: true }); }
}


test("I3: rc4 and v1 report the notice and errors for one or two table paths", () => {
  assert.match(spawnSync(rc4, ["--version"], { encoding: "utf8" }).stdout, /0\.1\.0-rc4\b/);
  for (const [line, oldExit, oldCodes, newCode] of [
    ["@table src=t.csv", 0, [["G02129", "notice"]], "G02252"],
    ["@table t.csv src=u.tsv", 1, [["G02129", "notice"], ["G02130", "error"]], "G02130"],
  ]) {
    const before = build(rc4, line);
    assert.equal(before.exit, oldExit);
    assert.deepEqual(before.diagnostics.map(d => [d.code, d.severity]).sort(), oldCodes);
    const span = newCode === "G02130" ? [0, line.length + 1] : [line.indexOf("src="), line.length];
    for (const target of allTargets) {
      for (const flags of [[], ["--no-notices"]]) {
        const after = build(candidate, line, "", flags, target);
        assert.equal(after.exit, 1, target);
        assert.deepEqual(after.diagnostics.map(d => [d.code, d.severity, d.span.start, d.span.end]),
          [[newCode, "error", ...span]], target);
      }
    }
  }
});

test("I4: rc4 accepts suppressing G02129, and v1 rejects the retired code", () => {
  const rules = '\n[diagnostics]\nsilence-notices = ["G02129"]\n';
  assert.deepEqual(build(rc4, "@table t.csv", rules), { exit: 0, diagnostics: [] });
  const result = build(candidate, "@table t.csv", rules);
  assert.equal(result.exit, 1);
  assert.deepEqual(result.diagnostics.map(d => d.code), ["G03024"]);
});
