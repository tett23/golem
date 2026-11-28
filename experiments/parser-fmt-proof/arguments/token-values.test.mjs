import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { compileArgumentProbe, run } from './ast-probe.mjs';
import { expectedToken, tokenCases, tokenManuscript } from '../grammar/token-cases.mjs';

test('root ADR 0351 I1, I2, I3: token raw spelling, kinds and decoded values agree before and after fmt', async t => {
  const buildWork = mkdtempSync(join(tmpdir(), 'golem-token-probe-'));
  try {
    const probe = compileArgumentProbe(buildWork);
    for (const [index, args] of tokenCases.entries()) {
      await t.test('root ADR 0351 I1, I2, I3: token fields ' + index, () => {
        const work = mkdtempSync(join(tmpdir(), 'golem-token-fields-'));
        const source = tokenManuscript(args);
        const file = join(work, 'a.gm');
        try {
          writeFileSync(file, source);
          const expected = expectedToken(args);
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          const once = readFileSync(file);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(readFileSync(file), once);
        } catch (error) {
          saveProjectFailure('arguments', work, source, error, 'token-fields-' + index, 'token-values.test.mjs');
          throw error;
        } finally {
          rmSync(work, { recursive: true, force: true });
        }
      });
    }
  } finally {
    rmSync(buildWork, { recursive: true, force: true });
  }
});
