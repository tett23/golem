import assert from 'node:assert/strict';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

test('Golem ADR 0351 failure artifacts retain referenced tables with their project paths and bytes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'golem-artifact-test-'));
  const savedRoot = process.env.ROUND_TRIP_FAILURES;
  try {
    process.env.ROUND_TRIP_FAILURES = join(dir, 'failures');
    mkdirSync(join(dir, 'data'));
    const bytes = Buffer.from('\uFEFF甲\t𠮷\r\n');
    writeFileSync(join(dir, 'data/words.tsv'), bytes);
    saveProjectFailure('arguments', dir, 'original', new Error('test'), 'table');
    assert.deepEqual(readFileSync(join(dir, 'failures/arguments/table/data/words.tsv')), bytes);
  } finally {
    if (savedRoot === undefined) delete process.env.ROUND_TRIP_FAILURES;
    else process.env.ROUND_TRIP_FAILURES = savedRoot;
    rmSync(dir, { recursive: true, force: true });
  }
});
