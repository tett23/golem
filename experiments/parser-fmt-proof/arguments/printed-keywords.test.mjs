import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

const words = [['甲', '𠮷'], ['%k', '%v'], ['a', 'b'], ['a', 'c']];
for (const length of [0, 1, 2, 4]) {
  test(`Golem ADR 0351 I1: native parser keeps ${length} printed keywords and the following command`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'golem-printed-keywords-'));
    const file = join(dir, 'a.gm');
    const args = words.slice(0, length);
    const original = '@inspect' + args.map(([k, v]) => ' ' + k + '=' + v).join('') + '\n@next\n';
    const cli = process.env.GOLEM || 'golem';
    function inspect(source) {
      const cst = execFileSync(cli, ['inspect', file, '--as', 'cst'], { cwd: dir, encoding: 'utf8' });
      const expected = args.map(([k, v]) => k + '=' + v);
      const bytes = Buffer.from(source);
      const extract = kind => Array.from(cst.matchAll(new RegExp('^\\s*' + kind + '@(\\d+)\\.\\.(\\d+)', 'gm')),
        ([, start, end]) => bytes.subarray(Number(start), Number(end)).toString());
      assert.deepEqual(extract('NKeywordArgument'), expected);
      assert.deepEqual(extract('KWord'), args.flat());
      assert.deepEqual(extract('KIdent'), ['inspect', 'next']);
      assert.deepEqual(extract('KNewline'), ['\n', '\n']);
    }
    try {
      writeFileSync(file, original);
      inspect(original);
      execFileSync(cli, ['fmt', file], { cwd: dir });
      inspect(readFileSync(file, 'utf8'));
    } catch (error) {
      saveProjectFailure('arguments', dir, original, error, 'printed-keywords-' + length, 'printed-keywords.test.mjs');
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}
