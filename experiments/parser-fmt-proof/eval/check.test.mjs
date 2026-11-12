import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { cpSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import test from 'node:test';
import { withoutPositions } from '../manuscripts/corpus.mjs';

test('Golem ADR 0351 I5: an imported Emet function evaluates identically after fmt', () => {
  const fixture = fileURLToPath(new URL('../../../modules/golem-driver/test/fixtures/functions/', import.meta.url));
  const dir = mkdtempSync(join(tmpdir(), 'golem-fmt-evaluation-'));
  const file = join(dir, 'a.gm');
  const run = (...args) => execFileSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8' });
  try {
    cpSync(fixture, dir, { recursive: true });
    const original = '@import fn/book.emet as book\n\n[= book.sum(1,%%注%%2,3)]\n';
    writeFileSync(file, original);
    const evaluate = () => withoutPositions(run('inspect', 'a.gm', '--as', 'ir'));
    const before = evaluate();
    assert.match(before, /blockBody = Paragraph Nothing \[Text "6"\]/);
    run('fmt', 'a.gm');
    const formatted = readFileSync(file, 'utf8');
    assert.notEqual(formatted, original);
    assert.ok(formatted.includes('%%注%%'));
    assert.equal(evaluate(), before);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
