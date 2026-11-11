// Compare the tagged rc4 CLI with the executable intended for v1.0.0.
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, rmSync } from "node:fs";
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
[source]
paragraph-separator = "blank-line"
`;

function build(bin, line, rules = "", flags = []) {
  const cwd = mkdtempSync(join(tmpdir(), "listing-release-"));
  try {
    writeFileSync(join(cwd, "manifest.toml"), manifest + rules);
    writeFileSync(join(cwd, "style.toml"), "");
    writeFileSync(join(cwd, "a.gm"), line + "\n");
    writeFileSync(join(cwd, "a.txt"), "source\n");
    const r = spawnSync(bin, ["build", "--target", "text", "--format", "json", ...flags], { cwd, encoding: "utf8" });
    if (r.error) throw r.error;
    return { exit: r.status, diagnostics: JSON.parse(r.stderr) };
  } finally { rmSync(cwd, { recursive: true, force: true }); }
}

test("I3: rc4 retains the notice and v1 rejects each legacy path at its argument", () => {
  assert.match(spawnSync(rc4, ["--version"], {encoding:"utf8"}).stdout, /0\.1\.0-rc4\b/);
  for (const [line, code] of [["@listing src=a.txt", "G02250"], ["@listing a.txt src=missing.txt", "G02253"]]) {
    for (const [bin, flags, exit, expected, severity] of [[rc4, [], 0, "G02065", "notice"], [candidate, [], 1, code, "error"], [candidate, ["--no-notices"], 1, code, "error"]]) {
      const result = build(bin, line, "", flags);
      assert.equal(result.exit, exit);
      assert.deepEqual(result.diagnostics.map(d => [d.code, d.severity, d.span.start,d.span.end]), [[expected, severity, line.indexOf("src="), line.length]]);
    }
  }
});

test("I4: silencing only the retired notice is accepted by rc4 and rejected by v1", () => {
  const rules = '\n[diagnostics]\nsilence-notices = ["G02065"]\n';
  assert.deepEqual(build(rc4, "@listing a.txt", rules), { exit: 0, diagnostics: [] });
  const result = build(candidate, "@listing a.txt", rules);
  assert.equal(result.exit, 1);
  assert.deepEqual(result.diagnostics.map(d => d.code), ["G03024"]);
});
