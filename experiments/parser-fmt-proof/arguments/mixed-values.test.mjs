import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { compileArgumentProbe, run } from './ast-probe.mjs';
import { expectedMixed, mixedCases, mixedManuscript } from '../grammar/mixed-cases.mjs';

test('root ADR 0351 I1, I2, I3: mixed names, kinds and values agree before and after fmt', async t => {
  const buildWork = mkdtempSync(join(tmpdir(), 'golem-mixed-probe-'));
  try {
    const probe = compileArgumentProbe(buildWork);
    for (const [index, args] of mixedCases.entries()) {
      await t.test('root ADR 0351 I1, I2, I3: mixed fields ' + index, () => {
        const work = mkdtempSync(join(tmpdir(), 'golem-mixed-fields-'));
        const source = mixedManuscript(args);
        const file = join(work, 'a.gm');
        try {
          writeFileSync(file, source);
          const expected = expectedMixed(args);
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(JSON.parse(run(probe, [file])), expected);
          const once = readFileSync(file);
          run(process.env.GOLEM ?? 'golem', ['fmt', file], { cwd: work });
          assert.deepEqual(readFileSync(file), once);
        } catch (error) {
          saveProjectFailure('arguments', work, source, error, 'mixed-fields-' + index, 'mixed-values.test.mjs');
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
