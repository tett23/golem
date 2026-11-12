import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';

test('Golem ADR 0351 I6-I8: fmt preserves keyword errors and the declaration order of missing arguments', () => {
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
  function checkSites() {
    const bytes = readFileSync(source);
    const first = bytes.indexOf('x=1');
    const second = bytes.indexOf('x=1', first + 3);
    const third = bytes.indexOf('x=1', second + 3);
    const value = bytes.indexOf('abc');
    assert.ok(first >= 0 && first < second && second < value && value < third);
    const endOfCall = bytes.lastIndexOf(']') + 1;
    const ds = JSON.parse(run(['check', '--format', 'json'], 1).stderr);
    assert.deepEqual(ds.map(({ code, span }) => [code, span.file, span.start, span.end]), [
      ['G02119', 'a.gm', first, first + 1],
      ['G02119', 'a.gm', second, second + 1],
      ['G02077', 'a.gm', second, second + 3],
      ['G02121', 'a.gm', value, value + 3],
      ['G02119', 'a.gm', third, third + 1],
      ['G02077', 'a.gm', third, third + 3],
      ['G02120', 'a.gm', endOfCall, endOfCall],
      ['G02120', 'a.gm', endOfCall, endOfCall],
    ]);
    assert.match(ds.at(-2).message, /2 番目の位置引数がありません$/);
    assert.match(ds.at(-1).message, /3 番目の位置引数がありません$/);
  }
  const original = '@import fn/book.emet as book\n\n注[book.price 1  x=1 %%甲%% x=1 tax=abc x=1]\n\n[book.triple   1]\n';
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
    checkSites();
    run(['fmt', source], 0);
    assert.notEqual(readFileSync(source, 'utf8'), original);
    checkSites();
  } catch (error) {
    saveProjectFailure('arguments', dir, original, error);
    throw error;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
