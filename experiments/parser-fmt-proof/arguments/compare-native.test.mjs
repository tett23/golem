import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdtempSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const here = fileURLToPath(new URL('.', import.meta.url));
const root = fileURLToPath(new URL('../../../', import.meta.url));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', ...options });
  if (result.error) throw result.error;
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
}

function modelRows(dir) {
  cpSync(join(here, 'Arguments.lean'), join(dir, 'Arguments.lean'));
  cpSync(join(here, 'NativeComparison.lean'), join(dir, 'NativeComparison.lean'));
  const lean = process.env.LEAN || 'lean';
  run(lean, ['-o', 'Arguments.olean', 'Arguments.lean'], { cwd: dir });
  return run(lean, ['--run', 'NativeComparison.lean'], {
    cwd: dir, env: { ...process.env, LEAN_PATH: dir },
  }).trim().split('\n').map(line => line.split('\t'));
}

function nativeRows(dir, original, tokens, caseName, formatted = false) {
  const source = join(dir, 'a.gm');
  writeFileSync(source, original);
  if (formatted) {
    const fmt = spawnSync(process.env.GOLEM || 'golem', ['fmt', source],
      { cwd: dir, encoding: 'utf8' });
    if (fmt.error) throw fmt.error;
    assert.equal(fmt.status, 0, fmt.stderr);
  }
  const text = readFileSync(source, 'utf8');
  const result = spawnSync(process.env.GOLEM || 'golem', ['check', '--format', 'json'],
    { cwd: dir, encoding: 'utf8' });
  if (result.error) throw result.error;
  assert.equal(result.status, 1, result.stderr);
  const diagnostics = JSON.parse(result.stderr);
  const starts = tokens.map(token => Buffer.from(text).indexOf(token));
  assert.ok(starts.every(start => start >= 0));
  return diagnostics.map(({ code, span, message }) => {
    if (code === 'G02120') {
      const ordinal = /([0-9]+) 番目の位置引数がありません$/.exec(message)?.[1];
      assert.ok(ordinal, message);
      const end = Buffer.from(text).lastIndexOf(']') + 1;
      assert.deepEqual([span.start, span.end], [end, end]);
      return [caseName, ordinal, code, ordinal];
    }
    const position = starts.findIndex((start, index) =>
      start <= span.start && span.end <= start + Buffer.byteLength(tokens[index]));
    assert.ok(position >= 0, JSON.stringify({ code, span }));
    const token = tokens[position];
    const start = starts[position];
    const equal = Buffer.from(token).indexOf('=');
    const expected = code === 'G02119' ? [start, start + equal]
      : code === 'G02077' ? [start, start + Buffer.byteLength(token)]
        : [start + equal + 1, start + Buffer.byteLength(token)];
    assert.deepEqual([span.start, span.end], expected,
      JSON.stringify({ code, token, span }));
    return [caseName, String(position), code, token.slice(0, token.indexOf('='))];
  });
}

test('Golem ADR 0351 I6-I8: Lean findings equal native check codes, order and spans', () => {
  const dir = mkdtempSync(join(tmpdir(), 'golem-argument-model-native-'));
  try {
    const fixtures = join(root, 'modules/golem-driver/test/fixtures');
    cpSync(join(fixtures, 'functions'), dir, { recursive: true });
    cpSync(join(fixtures, 'int-width/style.toml'), join(dir, 'style.toml'));
    mkdirSync(join(dir, 'fonts'));
    cpSync(join(fixtures, 'kanikosen/fonts/NotoSerifJP-Regular.otf'), join(dir, 'fonts/ja.otf'));
    cpSync(join(root, 'modules/golem-font/test/fonts/SourceSansPro-Regular.otf'),
      join(dir, 'fonts/latin.otf'));
    appendFileSync(join(dir, 'fn/book.emet'),
      '\npub inline triple :: Nat -> Nat -> Nat -> Inlines\ntriple a b c = Inline.text (String.fromNat (a + b + c))\n');

    const model = modelRows(dir);
    const tokens = ['x=1', 'x=2', 'tax=true', 'tax=abc', 'unit="円"'];
    const price = '@import fn/book.emet as book\n\n[book.price 1 ' + tokens.join(' ') + ']\n';
    const priceRows = nativeRows(dir, price, tokens, 'price');
    const formattedPriceRows = nativeRows(dir, price, tokens, 'price', true);
    const missingRows = [];
    const formattedMissingRows = [];
    for (const supplied of [0, 1, 2]) {
      const positional = Array.from({ length: supplied }, (_, index) => String(index + 1));
      const manuscript = '@import fn/book.emet as book\n\n[book.triple   ' + positional.join(' ') + ']\n';
      const caseName = `missing-${supplied}`;
      missingRows.push(...nativeRows(dir, manuscript, [], caseName));
      formattedMissingRows.push(...nativeRows(dir, manuscript, [], caseName, true));
    }
    assert.equal(priceRows.length, 5);
    assert.equal(missingRows.length, 6);
    assert.deepEqual([...priceRows, ...missingRows], model);
    assert.deepEqual([...formattedPriceRows, ...formattedMissingRows], model);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
