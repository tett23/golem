import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

function checkRoundTrip(original, check, caseName) {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  const fixtures = join(root, 'modules/golem-driver/test/fixtures');
  const dir = mkdtempSync(join(tmpdir(), 'golem-argument-sites-'));
  const source = join(dir, 'a.gm');
  function run(args, expected) {
    const result = spawnSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8' });
    if (result.error) throw result.error;
    assert.equal(result.status, expected, result.stderr);
    return result;
  }

  try {
    cpSync(join(fixtures, 'functions'), dir, { recursive: true });
    cpSync(join(fixtures, 'int-width/style.toml'), join(dir, 'style.toml'));
    mkdirSync(join(dir, 'fonts'));
    cpSync(join(fixtures, 'kanikosen/fonts/NotoSerifJP-Regular.otf'), join(dir, 'fonts/ja.otf'));
    cpSync(join(root, 'modules/golem-font/test/fonts/SourceSansPro-Regular.otf'), join(dir, 'fonts/latin.otf'));
    appendFileSync(join(dir, 'fn/book.emet'), [
      '', 'pub inline triple :: Nat -> Nat -> Nat -> Inlines',
      'triple a b c = Inline.text (String.fromNat (a + b + c))', '',
    ].join('\n'));
    writeFileSync(source, original);
    check(source, run);
    run(['fmt', source], 0);
    assert.notEqual(readFileSync(source, 'utf8'), original);
    check(source, run);
  } catch (error) {
    saveProjectFailure('arguments', dir, original, error, caseName);
    throw error;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

function checkSites(source, run) {
  const bytes = readFileSync(source);
  const first = bytes.indexOf('x=1');
  const second = bytes.indexOf('x=1', first + 3);
  const third = bytes.indexOf('x=1', second + 3);
  const value = bytes.indexOf('abc');
  assert.ok(first >= 0 && first < second && second < value && value < third);
  const repeatedTax = bytes.lastIndexOf('tax=abc');
  assert.ok(repeatedTax > third);
  const endOfCall = bytes.lastIndexOf(']') + 1;
  const ds = JSON.parse(run(['check', '--format', 'json'], 1).stderr);
  assert.deepEqual(ds.map(({ code, span }) => [code, span.file, span.start, span.end]), [
    ['G02119', 'a.gm', first, first + 1],
    ['G02119', 'a.gm', second, second + 1],
    ['G02077', 'a.gm', second, second + 3],
    ['G02121', 'a.gm', value, value + 3],
    ['G02119', 'a.gm', third, third + 1],
    ['G02077', 'a.gm', third, third + 3],
    ['G02077', 'a.gm', repeatedTax, repeatedTax + 7],
    ['G02121', 'a.gm', repeatedTax + 4, repeatedTax + 7],
    ['G02120', 'a.gm', endOfCall, endOfCall],
    ['G02120', 'a.gm', endOfCall, endOfCall],
  ]);
  assert.match(ds.at(-2).message, /2 番目の位置引数がありません$/);
  assert.match(ds.at(-1).message, /3 番目の位置引数がありません$/);
}

test('Golem ADR 0351 I6-I8: error spans and missing arguments in declaration order', () => {
  checkRoundTrip('@import fn/book.emet as book\n\n注[book.price 1  x=1 %%甲%% x=1 tax=abc x=1]\n\n[book.price 1 tax=true %%乙%% tax=abc]\n\n[book.triple   1]\n', checkSites, 'mixed');
});

function checkRepeatedTax(source, run) {
  const bytes = readFileSync(source);
  const bad = bytes.indexOf('tax=abc');
  const good = bytes.indexOf('tax=true');
  assert.ok(bad >= 0 && good >= 0);
  const type = ['G02121', bad + 4, bad + 7];
  const duplicate = bad < good ? ['G02077', good, good + 8] : ['G02077', bad, bad + 7];
  const result = JSON.parse(run(['check', '--format', 'json'], 1).stderr);
  assert.deepEqual(result.map(({ code, span }) => [code, span.start, span.end]),
    bad < good ? [type, duplicate] : [duplicate, type]);
}

const base = ['tax=true', 'unit="円"'];
for (let index = 0; index <= base.length; index++) {
  test(`Golem ADR 0351 I7: repeated tax at insertion boundary ${index}`, () => {
    const args = base.toSpliced(index, 0, 'tax=abc');
    const original = '@import fn/book.emet as book\n\n[book.price 1  ' + args.join(' %%注%% ') + ']\n';
    checkRoundTrip(original, checkRepeatedTax, 'tax-' + index);
  });
}

test('Golem ADR 0351 I6: missing arguments point past the closing delimiter and its preceding comment', () => {
  const original = '@import fn/book.emet as book\n\n日本語[book.triple   1 %%末尾%% ]続き\n';
  checkRoundTrip(original, (source, run) => {
    const bytes = readFileSync(source);
    const comment = bytes.indexOf('%%末尾%%');
    const close = bytes.indexOf(']', comment);
    assert.ok(comment >= 0 && close > comment);
    const diagnostics = JSON.parse(run(['check', '--format', 'json'], 1).stderr);
    assert.deepEqual(diagnostics.map(d => [d.code, d.span.file, d.span.start, d.span.end]),
      Array.from({ length: 2 }, () => ['G02120', 'a.gm', close + 1, close + 1]));
    assert.match(diagnostics[0].message, /2 番目の位置引数がありません$/);
    assert.match(diagnostics[1].message, /3 番目の位置引数がありません$/);
  }, 'missing-after-comment');
});

for (const unquoted of [[0], [1], [0, 1]]) {
  test(`Golem ADR 0351 I2: fmt preserves bytes for unquoted arguments ${unquoted.join(", ")}`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'golem-argument-quotes-'));
    const file = join(dir, 'a.gm');
    const values = ['abc%%甲%%', 'def%%乙%%'];
    const manuscript = omit => '[f  ' + values.map((value, index) =>
      ['key=', 'other='][index] + (omit.includes(index) ? value : '"' + value + '"')).join(' ') + ']\n';
    const original = manuscript([]);
    const input = manuscript(unquoted);
    try {
      writeFileSync(file, original);
      const cli = process.env.GOLEM || 'golem';
      const valid = spawnSync(cli, ['fmt', file], { encoding: 'utf8' });
      assert.equal(valid.status, 0, valid.stderr);
      writeFileSync(file, input);
      const broken = spawnSync(cli, ['fmt', file], { encoding: 'utf8' });
      if (broken.error) throw broken.error;
      assert.equal(broken.status, 1);
      const reports = [...broken.stderr.matchAll(/:1:(\d+): error\[(\w+)\]/g)];
      assert.deepEqual(reports.map(match => [Number(match[1]), match[2]]),
        unquoted.map(index => [input.indexOf(values[index]) + 1, 'G01102']));
      assert.deepEqual(readFileSync(file), Buffer.from(input));
    } catch (error) {
      const name = 'required-quotes-' + unquoted.join('-');
      saveProjectFailure('arguments', dir, original, error, name);
      writeFileSync(join(process.env.ROUND_TRIP_FAILURES || 'round-trip-failures',
        'arguments', name, 'input.gm'), input);
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}

for (const [argument, code, column] of [
  ['%%=x', 'G01101', 7],
  ['%%=x%%', 'G01101', 7],
  ['%%foo=x', 'G01018', 7],
  ['foo=%%', 'G01102', 11],
]) {
  test(`Golem ADR 0351 I2: fmt diagnoses ${argument} at its argument boundary`, () => {
    const dir = mkdtempSync(join(tmpdir(), 'golem-percent-prefix-'));
    const file = join(dir, 'a.gm');
    const input = '@foo  ' + argument + '\n';
    try {
      writeFileSync(file, input);
      const result = spawnSync(process.env.GOLEM || 'golem', ['fmt', file], { encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.equal(result.status, 1);
      const reports = [...result.stderr.matchAll(/:1:(\d+): error\[(\w+)\]/g)];
      assert.deepEqual(reports.map(match => [Number(match[1]), match[2]]), [[column, code]]);
      assert.deepEqual(readFileSync(file), Buffer.from(input));
    } catch (error) {
      saveProjectFailure('arguments', dir, input, error, 'percent-' + argument);
      throw error;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
}

test('Golem ADR 0351 I8: each call reports its own unsupplied suffix in declaration order', () => {
  const original = '@import fn/book.emet as book\n\n前[book.triple   ]中[book.triple   1 2]後[book.triple   1]\n';
  checkRoundTrip(original, (source, run) => {
    const bytes = readFileSync(source);
    const expected = [];
    let cursor = 0;
    for (const firstMissing of [1, 3, 2]) {
      const close = bytes.indexOf(']', cursor);
      assert.ok(close >= cursor);
      cursor = close + 1;
      for (let ordinal = firstMissing; ordinal <= 3; ordinal++) {
        expected.push(['G02120', 'a.gm', cursor, cursor, String(ordinal)]);
      }
    }
    const reports = JSON.parse(run(['check', '--format', 'json'], 1).stderr);
    assert.deepEqual(reports.map(({ code, span, message }) =>
      [code, span.file, span.start, span.end, /(\d+) 番目の位置引数がありません$/.exec(message)?.[1]]), expected);
  }, 'missing-multiple-calls');
});

test('Golem ADR 0351 I1: the enclosing command consumes its delimiter after the final keyword', () => {
  const dir = mkdtempSync(join(tmpdir(), 'golem-argument-terminator-'));
  const file = join(dir, 'a.gm');
  try {
    for (const [input, token] of [
      ['@foo a=b c=d', null],
      ['@foo a=b c=d\n続き\n', 'KNewline'],
      ['[foo a=b c=d]続き\n', 'KRBracket'],
      ['```hs a=b c=d\nx\n```\n', 'KNewline'],
    ]) {
      writeFileSync(file, input);
      const cli = process.env.GOLEM || 'golem';
      const result = spawnSync(cli, ['inspect', file, '--as', 'cst'], { encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.equal(result.status, 0, result.stderr);
      const start = Buffer.from(input).indexOf('c=d');
      const end = start + 3;
      assert.ok(result.stdout.includes('NKeywordArgument@' + start + '..' + end));
      if (token === null) {
        assert.equal(end, Buffer.byteLength(input));
        assert.ok(result.stdout.includes('NBlockCommand@0..' + end + '\n'));
        assert.doesNotMatch(result.stdout, /KNewline@/);
      } else {
        assert.ok(result.stdout.includes(token + '@' + end + '..' + (end + 1)), result.stdout);
      }
    }
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
