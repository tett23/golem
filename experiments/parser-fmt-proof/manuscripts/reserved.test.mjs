import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

const cases = [[], [0], [1], [0, 1]].map(sites => {
  const original = '甲[em: 𠮷]乙[em: 丙]末\n';
  let index = 0;
  const input = original.replaceAll('[em:', () => sites.includes(index++) ? '[!' : '[em:');
  return { name: 'sites-' + sites.join('-'), original, input, skipped: sites.map(i => ['[! 𠮷]', '[! 丙]'][i]) };
});
for (const [name, body] of [['nested', '[x]'], ['escaped', '\\]'], ['comment', '%%]%%']]) {
  const token = '[!' + body + ']';
  cases.push({ name, original: '甲末\n', input: '甲' + token + '末\n', skipped: [token] });
}

for (const { name, original, input, skipped } of cases) {
  test(`Golem ADR 0351: reserved bracket recovery ${name}`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'golem-reserved-'));
    const file = join(dir, 'a.gm');
    const cli = process.env.GOLEM || 'golem';
    try {
      writeFileSync(file, input);
      const result = spawnSync(cli, ['inspect', file, '--as', 'cst'], { cwd: dir, encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.deepEqual([...result.stderr.matchAll(/error\[(\w+)\]/g)].map(m => m[1]), skipped.map(() => 'G01100'));
      const expected = skipped.map(token => {
        const start = Buffer.from(input).indexOf(token);
        assert.ok(start >= 0);
        return [start, start + Buffer.byteLength(token)];
      });
      const errors = Array.from(result.stdout.matchAll(/NErrorNode@(\d+)\.\.(\d+)/g), m => [Number(m[1]), Number(m[2])]);
      assert.deepEqual(errors, expected);
      assert.match(result.stdout, /KText@\d+\.\.\d+ "末"/u);
      if (skipped.length) {
        const fmt = spawnSync(cli, ['fmt', file], { cwd: dir, encoding: 'utf8' });
        assert.equal(fmt.status, 1, fmt.stderr);
        assert.equal(readFileSync(file, 'utf8'), input);
      }
    } catch (error) {
      saveProjectFailure('manuscripts', dir, original, error, 'reserved-' + name, 'reserved.test.mjs');
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
