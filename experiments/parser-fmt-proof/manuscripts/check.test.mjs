import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';

test('Golem ADR 0351: a failed CLI inspection records the input and replay command', () => {
  const output = mkdtempSync(join(tmpdir(), 'golem-replay-'));
  const script = 'experiments/parser-fmt-proof/manuscripts/check.mjs';
  const env = { ...process.env, GOLEM: 'false', ROUND_TRIP_FAILURES: output };
  try {
    const result = spawnSync('node', [script, '1'], { env, encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.match(result.stdout, /19 cases/);
    const last = join(output, 'manuscript-18');
    const original = readFileSync(join(last, 'original.gm'), 'utf8');
    assert.equal(original, '@listing x.hs lang=haskell %%甲%%%%乙%% lines=1...1\n');
    assert.equal(readFileSync(join(last, 'result.gm'), 'utf8'), original);
    assert.match(readFileSync(join(last, 'error.txt'), 'utf8'), /false inspect/);
    const [node, ...args] = readFileSync(join(last, 'reproduce.txt'), 'utf8').trim().split(' ');
    assert.deepEqual(args, [script, '1', '18']);
    const replay = spawnSync(node, args, { env, encoding: 'utf8' });
    assert.equal(replay.status, 1);
    assert.match(replay.stdout, /1 cases/);
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
});
