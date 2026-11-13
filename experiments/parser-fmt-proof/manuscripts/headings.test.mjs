import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

const headings = ['###### 甲\n', '###### 𠮷\n'];
for (const index of headings.keys()) {
  test(`Golem ADR 0351: seventh heading marker on line ${index + 1}`, () => {
    const original = headings.join('');
    const input = headings.map((line, i) => i === index ? '#' + line : line).join('');
    const dir = mkdtempSync(join(tmpdir(), 'golem-heading-level-'));
    const source = join(dir, 'a.gm');
    try {
      writeFileSync(source, input);
      const fmt = spawnSync(process.env.GOLEM || 'golem', ['fmt', source], { encoding: 'utf8' });
      if (fmt.error) throw fmt.error;
      assert.equal(fmt.status, 1);
      const reports = [...fmt.stderr.matchAll(/:(\d+):(\d+): error\[(\w+)\]/g)];
      assert.deepEqual(reports.map(m => m.slice(1)), [[String(index + 1), '7', 'G01012']]);
      assert.equal(readFileSync(source, 'utf8'), input);
    } catch (error) {
      saveProjectFailure('manuscripts', dir, original, error, 'heading-level-' + index, 'headings.test.mjs', input);
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
