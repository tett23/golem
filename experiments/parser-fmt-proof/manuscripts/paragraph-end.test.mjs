import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

for (const [name, suffix] of [['eof', ''], ['newline-eof', '\n'], ['blank-line', '\n \t\nend\n']]) {
  test('Golem ADR 0351 I4: unclosed comment stops at ' + name, () => {
    const dir = mkdtempSync(join(tmpdir(), 'golem-para-end-'));
    const file = join(dir, 'a.gm');
    const original = 'a%%open%%' + suffix;
    const input = 'a%%open' + suffix;
    const cli = process.env.GOLEM || 'golem';
    try {
      writeFileSync(file, original);
      const clean = spawnSync(cli, ['inspect', file, '--as', 'cst'], { cwd: dir, encoding: 'utf8' });
      if (clean.error) throw clean.error;
      assert.equal(clean.status, 0, clean.stderr);
      assert.doesNotMatch(clean.stderr, /error\[/u);
      assert.match(clean.stdout, /KComment@1\.\.9 "%%open%%"/u);
      writeFileSync(file, input);
      const cst = spawnSync(cli, ['inspect', file, '--as', 'cst'], { cwd: dir, encoding: 'utf8' });
      if (cst.error) throw cst.error;
      assert.deepEqual([...cst.stderr.matchAll(/:(\d+):(\d+): error\[(\w+)\]/gu)].map(m => m.slice(1)),
        [['1', '8', 'G01018']]);
      assert.deepEqual([...cst.stdout.matchAll(/KComment@(\d+)\.\.(\d+) "(.*)"/gu)].map(m => m.slice(1)),
        [['1', '7', '%%open']]);
      if (name === 'blank-line') assert.match(cst.stdout, /KText@11\.\.14 "end"/u);
      const fmt = spawnSync(cli, ['fmt', file], { cwd: dir, encoding: 'utf8' });
      assert.equal(fmt.status, 1, fmt.stderr);
      assert.equal(readFileSync(file, 'utf8'), input);
    } catch (error) {
      saveProjectFailure('manuscripts', dir, original, error, 'para-end-' + name, 'paragraph-end.test.mjs', input);
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
