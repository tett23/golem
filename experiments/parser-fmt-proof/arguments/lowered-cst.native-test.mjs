import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { compileArgumentProbe, run } from './ast-probe.mjs';
import { expectedLower, lowerCases, nativeLowerRows } from '../grammar/lower-cases.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));

test('root ADR 0351 I1: constructed CST keyword fields match actual Lower', async t => {
  const work = mkdtempSync(join(tmpdir(), 'golem-lower-probe-'));
  try {
    const probe = compileArgumentProbe(work, join(here, 'NativeLower.hs'));
    for (const [index, rows] of lowerCases.entries()) {
      await t.test('root ADR 0351 I1: lowered CST fixture ' + index, () => {
        const input = nativeLowerRows(rows);
        const expected = expectedLower(rows);
        const file = join(work, 'input.json');
        let actual = '';
        try {
          writeFileSync(file, JSON.stringify(input));
          actual = run(probe, [file]);
          assert.deepEqual(JSON.parse(actual), expected);
        } catch (error) {
          // These are constructed CST tokens, not a Golem manuscript.
          // Preserve JSON and a replay through the native comparison test.
          const failure = join(process.env.ROUND_TRIP_FAILURES || 'round-trip-failures', 'arguments', 'lower-cst-' + index);
          mkdirSync(failure, { recursive: true });
          writeFileSync(join(failure, 'input.json'), JSON.stringify(input, null, 2) + '\n');
          writeFileSync(join(failure, 'expected.json'), JSON.stringify(expected, null, 2) + '\n');
          writeFileSync(join(failure, 'actual.txt'), actual);
          writeFileSync(join(failure, 'failure.txt'), String(error.stack || error) + '\n');
          writeFileSync(join(failure, 'reproduce.txt'),
            'From the source repository with the same built Cabal plan and GHC:\n' +
            'node --test experiments/parser-fmt-proof/arguments/lowered-cst.native-test.mjs\n' +
            'Fixture: lower-cst-' + index + '\n');
          throw error;
        }
      });
    }
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
});
