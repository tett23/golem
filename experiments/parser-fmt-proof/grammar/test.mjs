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
  const baselineUnsupported = [...strict.stderr.matchAll(/^unsupported [A-Za-z][A-Za-z0-9]* choice /gm)].length;
  assert.ok(baselineUnsupported <= 174, 'the full grammar model must not regress in unsupported choices');
  assert.equal(strict.status === 0, baselineUnsupported === 0,
    'strict generation succeeds exactly when every choice is supported');
  for (const line of strict.stderr.split('\n').filter(line => line.startsWith('unsupported '))) {
    assert.match(line, /^unsupported [A-Za-z][A-Za-z0-9]* choice \d+ at .*Golem\.hpeg:\d+: /,
      'unsupported choices need a rule name, choice number, and source line');
  }
  const newRule = `${original}\nUnmodeled <- ('a' / 'b') / 'c' { () }\n`;
  const newSource = join(work, 'Unmodeled.hpeg');
  writeFileSync(newSource, newRule);
  const newStrict = spawnSync(process.execPath, [join(here, 'generate.mjs'), newSource, generated], { encoding: 'utf8' });
  assert.notEqual(newStrict.status, 0);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'a'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'b'/);
  assert.match(newStrict.stderr, /unsupported Unmodeled choice .*'c'/);
  const changedLiteral = join(work, 'ChangedLiteral.hpeg');
  writeFileSync(changedLiteral, original.replace(/^Nl <- .*$/m, "Nl <- '\\n' 'x' { () }"));
  const strictLiteral = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedLiteral, generated], { encoding: 'utf8' });
  assert.match(strictLiteral.stderr, /unsupported Nl choice 1 at /,
    'a literal rule with a second item must return to the unsupported report');
  assert.match(strictLiteral.stderr, /unsupported EOL choice 2 at /,
    'the EOL nested choice needs the proved single-literal Nl rule');
  assert.doesNotMatch(strict.stderr,
    /^unsupported (EOL|Paragraph|BlockCommand|ListItem|DefTerm|DefNew|Table|CodeClose) choice \d+ at .*: (Nl|!\.)$/m,
    'the proved Nl/EOF nested choice applies inside every matching rule');
  const changedEol = join(work, 'ChangedEol.hpeg');
  writeFileSync(changedEol, original.replace('EOL <- Sp (Nl / !.)', "EOL <- Sp (Nl / !. / 'x')"));
  const strictEol = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedEol, generated], { encoding: 'utf8' });
  assert.match(strictEol.stderr, /unsupported EOL choice \d+ at .*'x'/,
    'a changed EOL nested choice must return to the unsupported report');
  const changedParagraph = join(work, 'ChangedParagraph.hpeg');
  writeFileSync(changedParagraph,
    original.replace('Inline(ind)+ (Nl / !.)', "Inline(ind)+ (Nl / !. / 'x')"));
  const strictParagraph = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedParagraph, generated], { encoding: 'utf8' });
  assert.match(strictParagraph.stderr, /unsupported Paragraph choice \d+ at .*'x'/,
    'a changed Nl/EOF choice in an argument rule must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported RowBreak choice [23] at /m,
    'the proved literal newline/EOF choice inside RowBreak must be covered');
  const changedRowBreak = join(work, 'ChangedRowBreak.hpeg');
  const rowBreakMutation = original.replace(/^RowBreak <- .*$/m,
    line => line.replace(' / !.)', " / !. / 'x')"));
  assert.notEqual(rowBreakMutation, original);
  writeFileSync(changedRowBreak, rowBreakMutation);
  const strictRowBreak = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedRowBreak, generated], { encoding: 'utf8' });
  assert.match(strictRowBreak.stderr, /unsupported RowBreak choice \d+ at .*'x'/,
    'a changed literal newline/EOF choice must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported SetDeclarationStart choice [23] at /m,
    'the proved character-class lookahead/EOF choice must be covered');
  const changedSetStart = join(work, 'ChangedSetDeclarationStart.hpeg');
  const setStartMutation = original.replace(/^SetDeclarationStart <- .*$/m,
    line => line.replace(' / !.)', " / !. / 'x')"));
  assert.notEqual(setStartMutation, original);
  writeFileSync(changedSetStart, setStartMutation);
  const strictSetStart = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSetStart, generated], { encoding: 'utf8' });
  assert.match(strictSetStart.stderr, /unsupported SetDeclarationStart choice \d+ at .*'x'/,
    'a changed character-class lookahead/EOF choice must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported (HeadInline|Inline|SlotInline|CellInline) choice /m,
    'single-reference ordered choices are covered by the generic error-preserving proof');
  const changedRefChoice = join(work, 'ChangedRefChoice.hpeg');
  const refChoiceMutation = original.replace('HeadInline <- Escape { () }',
    'HeadInline <- Escape Ws { () }');
  assert.notEqual(refChoiceMutation, original);
  writeFileSync(changedRefChoice, refChoiceMutation);
  const strictRefChoice = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedRefChoice, generated], { encoding: 'utf8' });
  assert.match(strictRefChoice.stderr, /unsupported HeadInline choice 1 at .*Escape Ws/,
    'a multi-item reference branch must return to the report');
  const changedClassPlus = join(work, 'ChangedClassPlus.hpeg');
  writeFileSync(changedClassPlus, original.replace(/^Ws <- .*$/m, "Ws <- [ \\t]+ 'x' { () }"));
  const strictClassPlus = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedClassPlus, generated], { encoding: 'utf8' });
  assert.match(strictClassPlus.stderr, /unsupported Ws choice 1 at /,
    'a repeated class rule with a second item must return to the unsupported report');
  const changedOptional = join(work, 'ChangedOptional.hpeg');
  writeFileSync(changedOptional, original.replace(/^Sp <- .*$/m, "Sp <- Ws? 'x' { () }"));
  const strictOptional = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedOptional, generated], { encoding: 'utf8' });
  assert.match(strictOptional.stderr, /unsupported Sp choice 1 at /,
    'an optional wrapper with a second item must return to the unsupported report');
  const changedAlias = join(work, 'ChangedAlias.hpeg');
  writeFileSync(changedAlias, original.replace(/^StringLiteral <- .*$/m, "StringLiteral <- StringLit 'x' { () }"));
  const strictAlias = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedAlias, generated], { encoding: 'utf8' });
  assert.match(strictAlias.stderr, /unsupported StringLiteral choice 1 at /,
    'a single-reference wrapper with a second item must return to the unsupported report');
  const changedOrdered = join(work, 'ChangedOrdered.hpeg');
  writeFileSync(changedOrdered, original.replace(/^HashMark <- .*$/m, "$& / 'extra' Ws { () }"));
  const strictOrdered = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedOrdered, generated], { encoding: 'utf8' });
  assert.match(strictOrdered.stderr, /unsupported HashMark choice \d+ at .*'extra'/,
    'a non-literal branch must return the ordered rule to the unsupported report');

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
  assert.match(model, /def literalProductions : List \(String × String × String\) := /);
  assert.match(model, /def classPlusProductions : List \(String × List \(Nat × Nat\) × String\) := /);
  assert.match(model, /def optionalRefProductions : List \(String × String\) := /);
  assert.match(model, /def aliasProductions : List \(String × String\) := /);
  assert.match(model, /def orderedLiteralProductions : List \(String × List \(String × String\)\) := /);
  const sourceRuleCount = [...original.matchAll(/^[A-Za-z][A-Za-z0-9]* <- /gm)].length;
  const emittedRuleCount = [...model.matchAll(/^  \("/gm)].length;
  assert.equal(emittedRuleCount, sourceRuleCount, 'every PEG production must appear in the Lean source data');
  const astRuleCount = [...model.matchAll(/^private def pegRule\d+ : PegModel.Rule := /gm)].length;
  assert.equal(astRuleCount, sourceRuleCount, 'the canonical PEG AST must emit every Lean rule');

  const parserCases = [
    ['', null, 0],
    ['# Title\n', 'Heading', 0],
    ['@set x = 1\n', 'BlockCommand', 0],
    ['set x = 1\n', 'BlockCommand', 0],
    ['@set x = 1+2\n', 'BlockCommand', 0, 'AddOp@10..11 "+"'],
    ['[= 1>=0]\n', 'Paragraph', 0, 'CmpOp@4..6 ">="'],
    ['[foo *[1]]\n', 'Paragraph', 0, 'Splat@5..7 "*["'],
    ['```en-US\nx\n```\n', 'CodeBlock', 0],
    ['| a | b |\n|---|---|\n| c | d |\n', 'Table', 4]
  ];
  for (const [sample, node, cells, chosen] of parserCases) {
    const samplePath = join(work, 'sample.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^File@0\\.\\.${sample.length}$`, 'm'),
      'the implementation parser must consume the same complete source');
    if (node) assert.match(parsed.stdout, new RegExp(`^ +${node}@`, 'm'));
    if (chosen) assert.ok(parsed.stdout.includes(chosen), `${chosen} was not chosen by the generated parser`);
    assert.equal([...parsed.stdout.matchAll(/cs: TableCellAndPipe@/g)].length, cells);
  }
  // The PEG accepts this token; Golem.Parser reports G01102 for the value.
  // Keep syntax acceptance separate from a valid manuscript round trip.
  const syntaxOnlyPath = join(work, 'syntax-only.gm');
  writeFileSync(syntaxOnlyPath, '@foo foo=%%\n');
  const syntaxOnly = spawnSync(process.env.PEG_HS ?? 'peg-hs',
    ['parse', '--format', 'cst', source, syntaxOnlyPath],
    { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
  assert.equal(syntaxOnly.status, 0, syntaxOnly.stderr);
  assert.match(syntaxOnly.stdout, /Word@9\.\.11 "%%"/);
  const rejectedParserCases = ['@foo %%=x\n', '@foo %%foo=x\n'];
  for (const sample of rejectedParserCases) {
    const samplePath = join(work, 'rejected.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, 'the proof comment prefix cannot start a plain keyword name');
    assert.match(parsed.stderr, /expected '%%'/);
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
  assert.doesNotMatch(strict.stderr, /^unsupported Word choice /m,
    'the canonical Word alternatives have arbitrary-input proofs');
  const changedWordPrefix = join(work, 'ChangedWordPrefix.hpeg');
  const wordPrefixMutation = original.replace(/^Word <- .*$/m,
    line => line.replace("'%%='", "'%%x'"));
  assert.notEqual(wordPrefixMutation, original);
  writeFileSync(changedWordPrefix, wordPrefixMutation);
  const strictWordPrefix = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedWordPrefix, generated], { encoding: 'utf8' });
  assert.match(strictWordPrefix.stderr, /unsupported Word choice 1 at /,
    'a changed Word prefix must return to the unsupported report');

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
  assert.equal(unsupportedChoices, baselineUnsupported, 'strict report count must remain stable through mutation tests');
  console.log(`grammar: source and AST rules ${emittedRuleCount}/${astRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proof modules 3, negative mutations 20, implementation parser cases ${parserCases.length}, syntax-only parser cases 1, rejected parser cases ${rejectedParserCases.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
