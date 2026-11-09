// Tests of scripts/ci/textlint.sh: the jobs and the cache of the jobs that
// reported nothing (docs/adr/0258-textlint-per-file-jobs-and-a-cache-of-clean-results.md).
// Each test builds a small repository in a temporary directory with a copy
// of tools/textlint (node_modules linked) and of the script, and runs the
// script there. The profiles read the configuration of the rule tests. The names carry the numbers of the invariants of the ADR.
"use strict";

const { describe, test } = require("node:test");
const assert = require("node:assert/strict");
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const TOOL = path.join(__dirname, "..");
const ROOT = path.join(TOOL, "..", "..");
const SCRIPT = path.join(ROOT, "scripts", "ci", "textlint.sh");

const CLEAN = "一文目である。\n二文目である。\n";
const DIRTY = "一文目である。二文目である。\n";

const git = (dir, ...args) => {
  const r = spawnSync("git", args, { cwd: dir, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`git ${args.join(" ")}: ${r.stderr}`);
  return r.stdout;
};

// files: path -> text, written and added to the index of a new repository
const repo = (files) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "golem-textlint-"));
  const tool = path.join(dir, "tools", "textlint");
  fs.cpSync(TOOL, tool, {
    recursive: true,
    filter: (src) => !["node_modules", ".cache"].includes(path.basename(src)),
  });
  fs.symlinkSync(path.join(TOOL, "node_modules"), path.join(tool, "node_modules"));
  // every profile reads the light configuration of the rule tests (the Golem
  // rules and prh, without the published presets): the script does not
  // depend on the rules, and the presets take a second a process
  for (const profile of ["docs", "diagnostics", "adr", "manual", "manual-dev"]) {
    fs.copyFileSync(path.join(tool, "test", "config.js"), path.join(tool, "config", `${profile}.js`));
  }
  fs.mkdirSync(path.join(dir, "scripts", "ci"), { recursive: true });
  fs.copyFileSync(SCRIPT, path.join(dir, "scripts", "ci", "textlint.sh"));
  write(dir, files);
  git(dir, "init", "-q");
  git(dir, "add", "-A");
  return dir;
};

const write = (dir, files) => {
  for (const [name, text] of Object.entries(files)) {
    fs.mkdirSync(path.dirname(path.join(dir, name)), { recursive: true });
    fs.writeFileSync(path.join(dir, name), text);
  }
};

// env: TEXTLINT_CACHE and the others; a missing TEXTLINT_CACHE means the
// cache file .cache-file of the repository
// (asynchronous, so that the tests run in parallel)
const run = (dir, env = {}) =>
  new Promise((resolve, reject) => {
    const p = spawn("sh", ["scripts/ci/textlint.sh"], {
      cwd: dir,
      env: { ...process.env, TEXTLINT_CACHE: path.join(dir, ".cache-file"), ...env },
      stdio: ["ignore", "pipe", "ignore"],
    });
    let out = "";
    p.stdout.on("data", (d) => (out += d));
    p.on("error", reject);
    p.on("close", (status) => resolve({ status, stdout: out.split(dir).join("<dir>") }));
  });
const uncached = (dir, env = {}) => run(dir, { ...env, TEXTLINT_CACHE: "" });
const cacheLines = (dir) => {
  const file = path.join(dir, ".cache-file");
  return fs.existsSync(file) ? fs.readFileSync(file, "utf8").split("\n").filter((l) => l) : null;
};

describe("scripts/ci/textlint.sh", { concurrency: true }, () => {
  test("I1 I2: a cold and a warm run report what a run without the cache reports", async () => {
    const dir = repo({ "docs/a.md": CLEAN, "docs/b.md": DIRTY, "manual/x.gm": CLEAN });
    const plain = await uncached(dir);
    assert.equal(plain.status, 1);
    assert.match(plain.stdout, /one-sentence-per-line/);
    assert.equal(cacheLines(dir), null);
    assert.deepEqual(await run(dir), plain);
    // docs/a.md and the manual reported nothing
    assert.equal(cacheLines(dir).length, 2);
    assert.deepEqual(await run(dir), plain);
    assert.equal(cacheLines(dir).length, 2);
  });

  test("I1 I2 I3: a change of a document is checked again", async () => {
    const dir = repo({ "docs/a.md": CLEAN, "docs/diagnostics.md": CLEAN, "manual/x.gm": CLEAN });
    assert.equal((await run(dir)).status, 0);
    const before = cacheLines(dir);
    assert.equal(before.length, 3);
    write(dir, { "docs/a.md": DIRTY, "manual/x.gm": DIRTY });
    const plain = await uncached(dir);
    assert.equal(plain.status, 1);
    assert.deepEqual(await run(dir), plain);
    // I2: only the key of docs/diagnostics.md is left
    assert.equal(cacheLines(dir).length, 1);
    assert.ok(before.includes(cacheLines(dir)[0]));
    // a document that reported and reports nothing again gets its key back
    write(dir, { "docs/a.md": CLEAN, "manual/x.gm": CLEAN });
    assert.deepEqual(await run(dir), await uncached(dir));
    assert.deepEqual(cacheLines(dir), before);
  });

  test("I1 I3: a change of a dictionary under tools/textlint checks every document again", async () => {
    const dir = repo({ "docs/a.md": "上流に送る。\n" });
    assert.equal((await run(dir)).status, 0);
    const dict = path.join(dir, "tools", "textlint", "prh", "dev.yml");
    fs.appendFileSync(dict, "  - expected: 下流\n    pattern: /上流/\n");
    const plain = await uncached(dir);
    assert.equal(plain.status, 1);
    assert.match(plain.stdout, /prh/);
    assert.deepEqual(await run(dir), plain);
  });

  test("I1 I3: a renamed document is checked again", async () => {
    const dir = repo({ "docs/a.md": CLEAN });
    assert.equal((await run(dir)).status, 0);
    const before = cacheLines(dir);
    fs.renameSync(path.join(dir, "docs", "a.md"), path.join(dir, "docs", "c.md"));
    git(dir, "add", "-A");
    assert.equal((await run(dir)).status, 0);
    assert.notDeepEqual(cacheLines(dir), before);
  });

  test("I4: the same inputs make the same keys in another repository", async () => {
    const files = { "docs/a.md": CLEAN, "manual/x.gm": CLEAN };
    const one = repo(files);
    const two = repo(files);
    assert.equal((await run(one)).status, 0);
    assert.equal((await run(two)).status, 0);
    assert.notEqual(one, two);
    assert.deepEqual(cacheLines(one), cacheLines(two));
  });

  test("I1: a cache file of foreign, empty or garbled lines changes nothing", async () => {
    const dir = repo({ "docs/a.md": CLEAN, "docs/b.md": DIRTY });
    const plain = await uncached(dir);
    // the cache file of a run in another repository, with other documents
    const other = repo({ "docs/a.md": DIRTY, "docs/b.md": CLEAN, "docs/c.md": CLEAN });
    await run(other);
    const foreign = fs.readFileSync(path.join(other, ".cache-file"), "utf8");
    for (const text of ["", "\n\n", "\n\n0000000000000000000000000000000000000000\nnot a key\n", "- docs\n", foreign]) {
      fs.writeFileSync(path.join(dir, ".cache-file"), text);
      assert.deepEqual(await run(dir), plain);
    }
  });

  test("I5: the report does not depend on the number of parallel jobs", async () => {
    const files = {};
    for (let i = 0; i < 4; i++) files[`docs/f${i}.md`] = i % 2 ? DIRTY : CLEAN;
    const dir = repo(files);
    const one = await uncached(dir, { TEXTLINT_JOBS: "1" });
    assert.equal(one.status, 1);
    assert.deepEqual(await uncached(dir, { TEXTLINT_JOBS: "8" }), one);
    assert.deepEqual(await run(dir, { TEXTLINT_JOBS: "3" }), one);
  });

  test("I6: with TEXTLINT_ARGS the cache is neither read nor written", async () => {
    const dir = repo({ "docs/a.md": CLEAN });
    const file = path.join(dir, ".cache-file");
    fs.writeFileSync(file, "planted\n");
    assert.equal((await run(dir, { TEXTLINT_ARGS: "--format stylish" })).status, 0);
    assert.equal(fs.readFileSync(file, "utf8"), "planted\n");
  });

  test("I7: a profile without files makes no job, and a run without jobs leaves the cache alone", async () => {
    const dir = repo({});
    fs.writeFileSync(path.join(dir, ".cache-file"), "kept\n");
    assert.deepEqual(await run(dir), { status: 0, stdout: "" });
    assert.deepEqual(cacheLines(dir), ["kept"]);
  });
});
