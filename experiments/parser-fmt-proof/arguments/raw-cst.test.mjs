import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { compileArgumentProbe, run } from './ast-probe.mjs';
import { expectedWrapper, wrapperCases, wrapperManuscript } from '../grammar/wrapper-cases.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));

test('root ADR 0351 I1: canonical keyword CST retains raw token spelling', async t => {
  const buildWork = mkdtempSync(join(tmpdir(), 'golem-raw-cst-probe-'));
  try {
    const probe = compileArgumentProbe(buildWork, join(here, 'NativeRawCst.hs'));
    for (const [index, row] of wrapperCases.entries()) {
      await t.test('root ADR 0351 I1: raw CST fixture ' + index, () => {
        const work = mkdtempSync(join(tmpdir(), 'golem-raw-cst-fields-'));
        const source = wrapperManuscript(row);
        const file = join(work, 'a.gm');
        try {
          writeFileSync(file, source);
          assert.deepEqual(JSON.parse(run(probe, [file])), expectedWrapper(row));
        } catch (error) {
          saveProjectFailure('arguments', work, source, error, 'raw-cst-' + index, 'raw-cst.test.mjs');
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
