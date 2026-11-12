import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { copyFileSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
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
  const headingLine = original.slice(0, original.indexOf('Heading(ind)', original.indexOf('Block <-'))).split('\n').length;
  assert.match(strict.stderr, new RegExp(`unsupported Block choice .* at .*Golem\\.hpeg:${headingLine}: Heading\\(ind\\)`), 'unsupported choices need exact source lines');
  const newRule = `${original}\nUnmodeled <- ('a' / 'b') / 'c' { () }\n`;
  const newSource = join(work, 'Unmodeled.hpeg');
  writeFileSync(newSource, newRule);
  const newStrict = spawnSync(process.execPath, [join(here, 'generate.mjs'), newSource, generated], { encoding: 'utf8' });
  assert.notEqual(newStrict.status, 0);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'a'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'b'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'c'/);
  if (/^Word <- '%%='/m.test(original)) {
    assert.match(strict.stderr, /unsupported Word choice 1 at .*Golem\.hpeg:\d+: '%%='/);
  }

  const invalidPeg = generate(`${original}\nUnclosed <- (\n`);
  assert.notEqual(invalidPeg.status, 0, 'the canonical PEG parser must reject malformed grammar');
  assert.match(invalidPeg.stderr, /peg-hs/);

  const positive = generate(original);
  assert.equal(positive.status, 0, positive.stderr);
  const model = readFileSync(generated, 'utf8');
  assert.match(model, /def stringLitEscapeFirst : Bool := true/);
  assert.match(model, /def sourceSha256 : String := /);
  assert.match(model, /def wordForbidden : List Char := /);
  assert.match(model, /def pegRules : List PegModel.Rule := /, 'the canonical PEG AST must become an explicit Lean model');
  const sourceRuleCount = [...original.matchAll(/^[A-Za-z][A-Za-z0-9]* <- /gm)].length;
  const emittedRuleCount = [...model.matchAll(/^  \("/gm)].length;
  assert.equal(emittedRuleCount, sourceRuleCount, 'every PEG production must appear in the Lean source data');
  const astRuleCount = [...model.matchAll(/^private def pegRule\d+ : PegModel.Rule := /gm)].length;
  assert.equal(astRuleCount, sourceRuleCount, 'the canonical PEG AST must emit every Lean rule');

  const parserCases = [
    ['', null, 0],
    ['# Title\n', 'Heading', 0],
    ['@set x = 1\n', 'BlockCommand', 0],
    ['| a | b |\n|---|---|\n| c | d |\n', 'Table', 4]
  ];
  for (const [sample, node, cells] of parserCases) {
    const samplePath = join(work, 'sample.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^File@0\\.\\.${sample.length}$`, 'm'),
      'the implementation parser must consume the same complete source');
    if (node) assert.match(parsed.stdout, new RegExp(`^ +${node}@`, 'm'));
    assert.equal([...parsed.stdout.matchAll(/cs: TableCellAndPipe@/g)].length, cells);
  }

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
  writeFileSync(join(work, 'Golem.hpeg'), original.replace(/^StringLit <- .*$/m, "$& / 'extra'"));
  const strictString = spawnSync(process.execPath, [join(here, 'generate.mjs'), join(work, 'Golem.hpeg'), generated], { encoding: 'utf8' });
  assert.match(strictString.stderr, /unsupported StringLit choice \d+ at .*: 'extra'/);

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
  const changedWordSource = join(work, 'Golem.hpeg');
  writeFileSync(changedWordSource, original.replace(/^Word <- .*$/m, "$& / 'a' / 'b'"));
  const strictWord = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedWordSource, generated], { encoding: 'utf8' });
  assert.match(strictWord.stderr, /unsupported Word choice \d+ at .*: 'a'/, 'first new Word branch needs a choice report');
  assert.match(strictWord.stderr, /unsupported Word choice \d+ at .*: 'b'/, 'second new Word branch needs a choice report');

  const bothUnsupported = unsupportedArguments.replace(/^Word <- .*$/m, '$& / AnotherTerm');
  const combinedFailure = generate(bothUnsupported);
  assert.notEqual(combinedFailure.status, 0);
  assert.match(combinedFailure.stderr, /Arguments: unsupported production/);
  assert.match(combinedFailure.stderr, /Word: unsupported production/);

  writeFileSync(generated, model);
  const pegModel = join(work, 'PegModel.lean');
  copyFileSync(join(here, 'PegModel.lean'), pegModel);
  execFileSync(lean, ['-o', join(work, 'PegModel.olean'), pegModel], { cwd: work, stdio: 'pipe' });
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], { cwd: work, env: { ...process.env, LEAN_PATH: work }, stdio: 'pipe' });
  const modelTests = spawnSync(lean, [join(here, 'PegModelTest.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(modelTests.status, 0, modelTests.stdout + modelTests.stderr);
  const stringProof = spawnSync(lean, [join(here, 'StringRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(stringProof.status, 0, stringProof.stderr);
  const wordProof = spawnSync(lean, [join(here, 'WordRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(wordProof.status, 0, wordProof.stderr);

  writeFileSync(generated, mutation);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], { cwd: work, env: { ...process.env, LEAN_PATH: work }, stdio: 'pipe' });
  const pegRefuted = spawnSync(lean, [join(here, 'PegModelTest.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.notEqual(pegRefuted.status, 0, 'reversed choice must also break the AST interpreter proof');
  assert.match(pegRefuted.stdout + pegRefuted.stderr, /PegModelTest\.lean:\d+:/);
  const refuted = spawnSync(lean, [join(here, 'StringRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.notEqual(refuted.status, 0, 'reversing the PEG choice must break the theorem');
  assert.match(refuted.stdout + refuted.stderr, /unsolved goals/, 'the mutation must refute the theorem, not fail to load a file');
  const unsupportedChoices = [...strict.stderr.matchAll(/^unsupported [A-Za-z][A-Za-z0-9]* choice /gm)].length;
  console.log(`grammar fragment: source and AST rules ${emittedRuleCount}/${astRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proof modules 3, negative mutations 9, implementation parser cases ${parserCases.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
