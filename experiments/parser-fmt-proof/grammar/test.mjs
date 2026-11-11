import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = fileURLToPath(new URL('.', import.meta.url));
const source = fileURLToPath(new URL('../../../modules/golem-parser/grammar/Golem.hpeg', import.meta.url));
const lean = process.env.LEAN ?? 'lean';
const work = mkdtempSync(join(tmpdir(), 'golem-grammar-proof-'));
const original = readFileSync(source, 'utf8');
const generated = join(work, 'Generated.lean');

function generate(grammar) {
  const input = join(work, 'Golem.hpeg');
  writeFileSync(input, grammar);
  return spawnSync(process.execPath, [join(here, 'generate.mjs'), '--fragment', input, generated], { encoding: 'utf8' });
}

try {
  const strict = spawnSync(process.execPath, [join(here, 'generate.mjs'), source, generated], { encoding: 'utf8' });
  assert.notEqual(strict.status, 0, 'the incomplete full grammar model must fail generation');
  const requiredRules = [...original.matchAll(/^([A-Za-z][A-Za-z0-9]*) <- /gm)]
    .map(match => match[1]).filter(name => name !== 'StringLit' && name !== 'Word');
  for (const name of requiredRules) {
    assert.match(strict.stderr, new RegExp(`^unsupported ${name} choice `, 'm'), `${name} is not reported`);
  }
  assert.match(strict.stderr, /unsupported Block choice .*Heading\(ind\)/);
  assert.match(strict.stderr, /unsupported Block choice .*Paragraph\(ind\)/);
  const newRule = `${original}\nUnmodeled <- ('a' / 'b') / 'c' { () }\n`;
  const newSource = join(work, 'Unmodeled.hpeg');
  writeFileSync(newSource, newRule);
  const newStrict = spawnSync(process.execPath, [join(here, 'generate.mjs'), newSource, generated], { encoding: 'utf8' });
  assert.notEqual(newStrict.status, 0);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'a'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'b'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'c'/);
  if (/^Word <- '%%='/m.test(original)) {
    assert.match(strict.stderr, /unsupported Word choice 1: '%%='/);
  }

  const positive = generate(original);
  assert.equal(positive.status, 0, positive.stderr);
  const model = readFileSync(generated, 'utf8');
  assert.match(model, /def stringLitEscapeFirst : Bool := true/);
  assert.match(model, /def sourceSha256 : String := /);
  assert.match(model, /def wordForbidden : List Char := /);
  const sourceRuleCount = [...original.matchAll(/^[A-Za-z][A-Za-z0-9]* <- /gm)].length;
  const emittedRuleCount = [...model.matchAll(/^  \("/gm)].length;
  assert.equal(emittedRuleCount, sourceRuleCount, 'every PEG production must appear in the Lean source data');

  const reversed = original.replace(/^(StringLit <- )'"' \('\\\\' \. \/ !\["\\n\] \.\)\* '"'/m, '$1\'"\' (!["\\n] . / \'\\\\\' .)* \'"\'');
  assert.notEqual(reversed, original, 'the negative test must change StringLit');
  assert.equal(generate(reversed).status, 0);
  const mutation = readFileSync(generated, 'utf8');
  assert.match(mutation, /def stringLitEscapeFirst : Bool := false/);

  const missing = original.replace(/^StringLit <- .*$/m, 'StringLit <- \'"\' UnsupportedTerm* \'"\' { () }');
  const failed = generate(missing);
  assert.notEqual(failed.status, 0, 'unsupported PEG alternatives must fail generation');
  assert.match(failed.stderr, /StringLit/);
  assert.match(failed.stderr, /UnsupportedTerm/);

  const unsupportedArguments = original.replace(/^Arguments <- .*$/m, '$& / UnsupportedTerm');
  const argumentFailure = generate(unsupportedArguments);
  assert.notEqual(argumentFailure.status, 0, 'unsupported argument branches must fail generation');
  assert.match(argumentFailure.stderr, /Arguments/);
  assert.match(argumentFailure.stderr, /UnsupportedTerm/);

  const changedWord = original.replace(/^Word <- .*$/m, '$& / UnsupportedTerm');
  const wordFailure = generate(changedWord);
  assert.notEqual(wordFailure.status, 0, 'unsupported word branch must fail generation');
  assert.match(wordFailure.stderr, /Word/);
  assert.match(wordFailure.stderr, /UnsupportedTerm/);

  const bothUnsupported = unsupportedArguments.replace(/^Word <- .*$/m, '$& / AnotherTerm');
  const combinedFailure = generate(bothUnsupported);
  assert.notEqual(combinedFailure.status, 0);
  assert.match(combinedFailure.stderr, /Arguments: unsupported production/);
  assert.match(combinedFailure.stderr, /Word: unsupported production/);

  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], { cwd: work, stdio: 'pipe' });
  const stringProof = spawnSync(lean, [join(here, 'StringRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(stringProof.status, 0, stringProof.stderr);
  const wordProof = spawnSync(lean, [join(here, 'WordRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(wordProof.status, 0, wordProof.stderr);

  writeFileSync(generated, mutation);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], { cwd: work, stdio: 'pipe' });
  const refuted = spawnSync(lean, [join(here, 'StringRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.notEqual(refuted.status, 0, 'reversing the PEG choice must break the theorem');
  assert.match(refuted.stdout + refuted.stderr, /unsolved goals/, 'the mutation must refute the theorem, not fail to load a file');
  const unsupportedChoices = [...strict.stderr.matchAll(/^unsupported [A-Za-z][A-Za-z0-9]* choice /gm)].length;
  console.log(`grammar fragment: rules ${emittedRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proofs 2, negative mutations 6`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
