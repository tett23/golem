import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

for (const broken of [[], [0], [1], [0, 1]]) {
  test(`Golem ADR 0351: reserved brackets recover at the marked sites ${JSON.stringify(broken)}`, () => {
    const original = '甲[em: 𠮷]乙[em: 丙]末\n';
    let index = 0;
    const input = original.replaceAll('[em:', () => broken.includes(index++) ? '[!' : '[em:');
    const dir = mkdtempSync(join(tmpdir(), 'golem-reserved-'));
    const file = join(dir, 'a.gm');
    const cli = process.env.GOLEM || 'golem';
    try {
      writeFileSync(file, input);
      const result = spawnSync(cli, ['inspect', file, '--as', 'cst'], { cwd: dir, encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.deepEqual([...result.stderr.matchAll(/error\[(\w+)\]/g)].map(m => m[1]), broken.map(() => 'G01100'));
      const expected = Array.from(input.matchAll(/\[![^\]]*\]/gu), m => {
        const start = Buffer.byteLength(input.slice(0, m.index));
        return [start, start + Buffer.byteLength(m[0])];
      });
      const errors = Array.from(result.stdout.matchAll(/NErrorNode@(\d+)\.\.(\d+)/g), m => [Number(m[1]), Number(m[2])]);
      assert.deepEqual(errors, expected);
      assert.match(result.stdout, /KText@\d+\.\.\d+ "末"/u);
      if (broken.length) {
        const fmt = spawnSync(cli, ['fmt', file], { cwd: dir, encoding: 'utf8' });
        assert.equal(fmt.status, 1, fmt.stderr);
        assert.equal(readFileSync(file, 'utf8'), input);
      }
    } catch (error) {
      saveProjectFailure('manuscripts', dir, original, error, 'reserved-' + broken.join('-'), 'reserved.test.mjs');
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
