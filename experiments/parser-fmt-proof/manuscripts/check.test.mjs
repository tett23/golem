import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
    assert.match(result.stdout, /^80 cases /);
    assert.equal(readFileSync(join(output, 'manuscript-70', 'original.gm'), 'utf8'),
      '###### %%注%%乙\n');
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
    const nested = spawnSync(node, [script, '1', '24', '2'], { env, encoding: 'utf8' });
    assert.equal(nested.status, 1);
    const nestedPath = join(output, 'manuscript-24');
    assert.equal(readFileSync(join(nestedPath, 'original.gm'), 'utf8'), '[em: [em: 鰍]]\n');
    assert.equal(readFileSync(join(nestedPath, 'reproduce.txt'), 'utf8'), `node ${script} 1 24 2\n`);
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
});

// A stable but incorrect CST would pass a comparison of before and after alone.
for (const [fault, comments] of [
  ['missing', []],
  ['reversed', ['KComment@13..20 "%%乙%%"', 'KComment@6..13 "%%甲%%"']],
  ['moved', ['KEquals@20..21 "="', 'KComment@6..13 "%%甲%%"', 'KComment@13..20 "%%乙%%"']],
]) {
  test(`Golem ADR 0351 I2: detect ${fault} adjacent comments before fmt`, () => {
    const output = mkdtempSync(join(tmpdir(), 'golem-comment-order-'));
    const stub = join(output, 'golem');
    const script = 'experiments/parser-fmt-proof/manuscripts/check.mjs';
    try {
      const tokens = ['KLBracket@0..1 "["', 'KIdent@1..2 "f"', 'KString@3..6 "x"', ...comments];
      writeFileSync(stub, "#!/bin/sh\ncat <<'CST'\n" + tokens.join('\n') + '\nCST\n', { mode: 0o755 });
      const result = spawnSync('node', [script, '0', '6'], {
        env: { ...process.env, GOLEM: stub, ROUND_TRIP_FAILURES: output }, encoding: 'utf8',
      });
      assert.equal(result.status, 1);
      const evidence = join(output, 'manuscript-6');
      assert.match(readFileSync(join(evidence, 'original.gm'), 'utf8'), /%%甲%%%%乙%%/);
      const reason = readFileSync(join(evidence, 'error.txt'), 'utf8');
      assert.match(reason, /%%甲%%/);
      assert.match(reason, /%%乙%%/);
    } finally {
      rmSync(output, { recursive: true, force: true });
    }
  });
}

test('Golem ADR 0351 I4: a listing keyword must occur in the accepted AST', () => {
  const output = mkdtempSync(join(tmpdir(), 'golem-listing-coverage-'));
  const stub = join(output, 'golem');
  try {
    writeFileSync(stub, '#!/bin/sh\necho \'BlockCommand ("listing") [Positional (Word "x.hs")] []\'\n', { mode: 0o755 });
    const result = spawnSync('node', ['experiments/parser-fmt-proof/manuscripts/check.mjs', '0', '9'], {
      env: { ...process.env, GOLEM: stub, ROUND_TRIP_FAILURES: output }, encoding: 'utf8',
    });
    assert.equal(result.status, 1);
    assert.match(readFileSync(join(output, 'manuscript-9', 'error.txt'), 'utf8'), /lines/);
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
});

test('Golem ADR 0351 I4: detect reordered fence arguments in a multiline AST', () => {
  const output = mkdtempSync(join(tmpdir(), 'golem-fence-order-'));
  const stub = join(output, 'golem');
  try {
    const reordered = ['CodeBlock', '  Nothing',
      ...['k', 'n', 'm'].map(key => '  - Keyword ("' + key + '") (StringLit "' + key + '")'),
      '  ["x"]'];
    writeFileSync(stub, "#!/bin/sh\ncat <<'AST'\n" + reordered.join('\n') + '\nAST\n', { mode: 0o755 });
    const result = spawnSync('node', ['experiments/parser-fmt-proof/manuscripts/check.mjs', '0', '17'], {
      env: { ...process.env, GOLEM: stub, ROUND_TRIP_FAILURES: output }, encoding: 'utf8',
    });
    assert.equal(result.status, 1);
    const evidence = join(output, 'manuscript-17');
    assert.match(readFileSync(join(evidence, 'original.gm'), 'utf8'), /k="k" m="m" n="n"/);
    assert.match(readFileSync(join(evidence, 'error.txt'), 'utf8'), /did not match the regular expression/);
  } finally {
    rmSync(output, { recursive: true, force: true });
  }
});
