import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { appendFileSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { withoutPositions } from '../manuscripts/corpus.mjs';

test('Golem ADR 0351 I5: an imported Emet function evaluates identically after fmt', () => {
  const fixture = fileURLToPath(new URL('../../../modules/golem-driver/test/fixtures/functions/', import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), 'golem-fmt-evaluation-'));
  const file = join(dir, 'a.gm');
  const run = (...args) => execFileSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8' });
  const original = '@import fn/book.emet as book\n\n[= book.sum(1,%%注%%2,3)]\n\n' +
    '[= book.first(7,%%左%%0)]\n\n[= book.second(8,%%右%%0)]\n';
  try {
    cpSync(fixture, dir, { recursive: true });
    appendFileSync(join(dir, 'fn/book.emet'), [
      '', 'pub fn first :: Nat -> Nat -> Nat', 'first a b = True ? a : div a b',
      '', 'pub fn second :: Nat -> Nat -> Nat', 'second a b = False ? div a b : a', '',
    ].join('\n'));
    writeFileSync(file, original);
    const evaluate = () => withoutPositions(run('inspect', 'a.gm', '--as', 'ir'));
    const before = evaluate();
    assert.match(before, /blockBody = Paragraph Nothing \[Text "6"\]/);
    for (const value of ['7', '8']) {
      assert.ok(before.includes('blockBody = Paragraph Nothing [Text "' + value + '"]'));
    }
    run('fmt', 'a.gm');
    const formatted = readFileSync(file, 'utf8');
    assert.notEqual(formatted, original);
    assert.ok(formatted.includes('%%注%%'));
    assert.equal(evaluate(), before);
  } catch (error) {
    saveProjectFailure('eval', dir, original, error);
    throw error;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('Golem ADR 0351 I5: division failure in an imported function survives manuscript formatting', () => {
  const root = fileURLToPath(new URL('../../../', import.meta.url));
  const fixtures = join(root, 'modules/golem-driver/test/fixtures');
  const dir = mkdtempSync(join(tmpdir(), 'golem-fmt-division-'));
  const original = '@import fn/book.emet as book\n\n[= book.quotient(3,%%注%%0)]\n';
  const file = join(dir, 'a.gm');
  try {
    cpSync(join(fixtures, 'functions'), dir, { recursive: true });
    cpSync(join(fixtures, 'int-width/style.toml'), join(dir, 'style.toml'));
    mkdirSync(join(dir, 'fonts'));
    cpSync(join(fixtures, 'kanikosen/fonts/NotoSerifJP-Regular.otf'), join(dir, 'fonts/ja.otf'));
    cpSync(join(root, 'modules/golem-font/test/fonts/SourceSansPro-Regular.otf'), join(dir, 'fonts/latin.otf'));
    const book = join(dir, 'fn/book.emet');
    appendFileSync(book, '\npub fn quotient :: Nat -> Nat -> Nat\nquotient a b = div a b\n');
    writeFileSync(file, original);
    const cli = process.env.GOLEM || 'golem';
    function diagnostics() {
      const result = spawnSync(cli, ['check', '--format', 'json'], { cwd: dir, encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.equal(result.status, 1, result.stderr);
      return JSON.parse(result.stderr);
    }
    const before = diagnostics();
    assert.deepEqual(before.map(d => [d.code, d.severity, d.span.file]), [['G02003', 'error', 'fn/book.emet']]);
    const { start, end } = before[0].span;
    assert.equal(readFileSync(book).subarray(start, end).toString(), 'div a b');
    execFileSync(cli, ['fmt', 'a.gm'], { cwd: dir });
    assert.notEqual(readFileSync(file, 'utf8'), original);
    assert.deepEqual(diagnostics(), before);
  } catch (error) {
    saveProjectFailure('eval', dir, original, error, 'division');
    throw error;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
