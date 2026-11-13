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
  assert.ok(baselineUnsupported <= 94, 'the full grammar model must not regress in unsupported choices');
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
  assert.doesNotMatch(strict.stderr, /^unsupported (StringLiteral|KeywordLiteral) choice /m,
    'single-reference alternatives use the same error-preserving theorem');
  assert.doesNotMatch(strict.stderr, /^unsupported StringLit choice /m,
    'the generated string recognizer is total on arbitrary suffixes');
  const changedSingleRef = join(work, 'ChangedSingleRef.hpeg');
  const singleRefMutation = original.replace(/^KeywordLiteral <- .*$/m,
    'KeywordLiteral <- Keyword Ws { () }');
  assert.notEqual(singleRefMutation, original);
  writeFileSync(changedSingleRef, singleRefMutation);
  const strictSingleRef = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSingleRef, generated], { encoding: 'utf8' });
  assert.match(strictSingleRef.stderr, /unsupported KeywordLiteral choice 1 at .*Keyword Ws/,
    'a second item must return a single-reference rule to the unsupported report');
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
    ['@foo\n', 'BlockCommand', 0],
    ['@set x = 2*3\n', 'BlockCommand', 0, 'MulOp@10..11 "*"'],
    ['@set x = 2**3\n', 'BlockCommand', 0, 'PowOp@10..12 "**"'],
    ['@set x = 2%3\n', 'BlockCommand', 0, 'MulOp@10..11 "%"'],
    ['@set x = true\n', 'BlockCommand', 0, 'Keyword@9..13 "true"'],
    ['@set x = truex\n', 'BlockCommand', 0, 'ExprIdent@9..14 "truex"'],
    ['[= 1>=0]\n', 'Paragraph', 0, 'CmpOp@4..6 ">="'],
    ['[foo *[1]]\n', 'Paragraph', 0, 'Splat@5..7 "*["'],
    ['```en-US\nx\n```\n', 'CodeBlock', 0, 'CodeLine@9..11 "x\\n"'],
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
  assert.doesNotMatch(strict.stderr, /^unsupported MulOp choice /m,
    'the canonical guarded multiplication operators have arbitrary-input proofs');
  const changedMulOp = join(work, 'ChangedMulOp.hpeg');
  const mulOpMutation = original.replace(/^MulOp <- .*$/m,
    line => line.replace("'*' !'*'", "'*'"));
  assert.notEqual(mulOpMutation, original);
  writeFileSync(changedMulOp, mulOpMutation);
  const strictMulOp = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedMulOp, generated], { encoding: 'utf8' });
  assert.match(strictMulOp.stderr, /unsupported MulOp choice 1 at /,
    'a changed MulOp lookahead must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported Keyword choice /m,
    'the canonical keyword alternatives and boundary have arbitrary-input proofs');
  const changedKeyword = join(work, 'ChangedKeyword.hpeg');
  const keywordMutation = original.replace(/^Keyword <- .*$/m,
    line => line.replace(' ![a-z0-9_]', ''));
  assert.notEqual(keywordMutation, original);
  writeFileSync(changedKeyword, keywordMutation);
  const strictKeyword = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedKeyword, generated], { encoding: 'utf8' });
  assert.match(strictKeyword.stderr, /unsupported Keyword choice 1 at /,
    'removing the keyword boundary must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported BlockCommandStart choice /m,
    'the canonical block command start dispatch has an arbitrary-input proof');
  const changedBlockCommandStart = join(work, 'ChangedBlockCommandStart.hpeg');
  const blockCommandStartMutation = original.replace(/^BlockCommandStart <- .*$/m,
    line => line.replace('[a-z]', '[A-Z]'));
  assert.notEqual(blockCommandStartMutation, original);
  writeFileSync(changedBlockCommandStart, blockCommandStartMutation);
  const strictBlockCommandStart = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedBlockCommandStart, generated], { encoding: 'utf8' });
  assert.match(strictBlockCommandStart.stderr, /unsupported BlockCommandStart choice 1 at /,
    'changing the command prefix class must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported (SkipAll|SkipLine) choice /m,
    'the canonical skip rules have arbitrary-input proofs');
  const changedSkipAll = join(work, 'ChangedSkipAll.hpeg');
  writeFileSync(changedSkipAll, original.replace(/^SkipAll <- .*$/m, 'SkipAll <- .+ { () }'));
  const strictSkipAll = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSkipAll, generated], { encoding: 'utf8' });
  assert.match(strictSkipAll.stderr, /unsupported SkipAll choice 1 at /,
    'changing EOF consumption to one-or-more must return to the report');
  const changedSkipLine = join(work, 'ChangedSkipLine.hpeg');
  writeFileSync(changedSkipLine, original.replace(/^SkipLine <- .*$/m,
    'SkipLine <- (![x] .)* { () }'));
  const strictSkipLine = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSkipLine, generated], { encoding: 'utf8' });
  assert.match(strictSkipLine.stderr, /unsupported SkipLine choice 1 at /,
    'changing the newline boundary must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported CodeLine choice /m,
    'the canonical code line consumes a required newline after text');
  const changedCodeLine = join(work, 'ChangedCodeLine.hpeg');
  writeFileSync(changedCodeLine, original.replace(/^CodeLine <- .*$/m,
    'CodeLine <- (![x] .)* Nl { () }'));
  const strictCodeLine = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedCodeLine, generated], { encoding: 'utf8' });
  assert.match(strictCodeLine.stderr, /unsupported CodeLine choice 1 at /,
    'changing the code line boundary must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported ReservedBracket choice /m,
    'the canonical ReservedBracket choice has an all-input proof');
  const changedReservedBracket = join(work, 'ChangedReservedBracket.hpeg');
  writeFileSync(changedReservedBracket, original.replace(/^ReservedBracket <- .*$/m,
    "ReservedBracket <- &'[!' (&{ False } '[!')^changed { () }"));
  const strictReservedBracket = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedReservedBracket, generated], { encoding: 'utf8' });
  assert.match(strictReservedBracket.stderr, /unsupported ReservedBracket choice 1 at /,
    'a changed reserved label must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported (NumberOpen|SetIdent) choice /m,
    'both canonical prefix and class references have all-input proofs');
  const changedNumberOpen = join(work, 'ChangedNumberOpen.hpeg');
  writeFileSync(changedNumberOpen, original.replace(/^NumberOpen <- .*$/m,
    "NumberOpen <- '##' [a-z] { () }"));
  const strictNumberOpen = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedNumberOpen, generated], { encoding: 'utf8' });
  assert.match(strictNumberOpen.stderr, /unsupported NumberOpen choice 1 at /,
    'a changed required class must return to the unsupported report');
  const changedSetIdent = join(work, 'ChangedSetIdent.hpeg');
  writeFileSync(changedSetIdent, original.replace(/^SetIdent <- .*$/m,
    "SetIdent <- 'set' ![a-z] { () }"));
  const strictSetIdent = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSetIdent, generated], { encoding: 'utf8' });
  assert.match(strictSetIdent.stderr, /unsupported SetIdent choice 1 at /,
    'a changed boundary class must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported (TooDeep|BadBreak) choice /m,
    'the canonical throwing prefixes have all-input proofs');
  const changedTooDeep = join(work, 'ChangedTooDeep.hpeg');
  writeFileSync(changedTooDeep, original.replace(/^TooDeep <- .*$/m,
    "TooDeep <- &'#' (&{ False } '#')^changed { () }"));
  const strictTooDeep = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedTooDeep, generated], { encoding: 'utf8' });
  assert.match(strictTooDeep.stderr, /unsupported TooDeep choice 1 at /,
    'a changed lookahead label must return to the unsupported report');
  const changedBadBreak = join(work, 'ChangedBadBreak.hpeg');
  writeFileSync(changedBadBreak, original.replace(/^BadBreak <- .*$/m,
    "BadBreak <- '\\\\' (&{ False })^changed { () }"));
  const strictBadBreak = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedBadBreak, generated], { encoding: 'utf8' });
  assert.match(strictBadBreak.stderr, /unsupported BadBreak choice 1 at /,
    'a changed literal label must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported BadBracket choice /m,
    'the canonical bracket reference has an all-input proof');
  const changedBadBracket = join(work, 'ChangedBadBracket.hpeg');
  writeFileSync(changedBadBracket, original.replace(/^BadBracket <- .*$/m,
    'BadBracket <- &LBr (&{ False } LBr)^changed { () }'));
  const strictBadBracket = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedBadBracket, generated], { encoding: 'utf8' });
  assert.match(strictBadBracket.stderr, /unsupported BadBracket choice 1 at /,
    'a changed bracket label must return to the unsupported report');
  const changedLBr = join(work, 'ChangedLBr.hpeg');
  writeFileSync(changedLBr, original.replace(/^LBr <- .*$/m, "LBr <- '{' { () }"));
  const strictLBr = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedLBr, generated], { encoding: 'utf8' });
  assert.match(strictLBr.stderr, /unsupported BadBracket choice 1 at /,
    'a changed referenced bracket must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported Escape choice /m,
    'the canonical escape reference has an all-input proof');
  assert.ok(!strict.stderr.split('\n').some(line => line.startsWith('unsupported ReservedBracketBody choice ') &&
    line.endsWith(String.raw`'\\' ![\n] .`)),
    'the identical nested escape sequence has an all-input proof');
  assert.doesNotMatch(strict.stderr, /^unsupported Backslash choice /m);
  const changedBackslash = join(work, 'ChangedBackslash.hpeg');
  writeFileSync(changedBackslash, original.replace(/^Backslash <- .*$/m,
    line => line.replace("&'", "!'")));
  const strictBackslash = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedBackslash, generated], { encoding: 'utf8' });
  assert.match(strictBackslash.stderr, /unsupported Backslash choice 1 at /);
  const changedEscape = join(work, 'ChangedEscape.hpeg');
  writeFileSync(changedEscape, original.replace(/^Escape <- .*$/m,
    String.raw`Escape <- '\\' [\n] . { () }`));
  const strictEscape = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedEscape, generated], { encoding: 'utf8' });
  assert.match(strictEscape.stderr, /unsupported Escape choice 1 at /,
    'a changed escape guard must return to the unsupported report');
  const ordinaryBody = String.raw`![\[\]\\\n] .`;
  assert.ok(!strict.stderr.split('\n').some(line =>
    line.startsWith('unsupported ReservedBracketBody ') && line.endsWith(ordinaryBody)));
  const changedOrdinary = join(work, 'ChangedOrdinary.hpeg');
  writeFileSync(changedOrdinary, original.replace(ordinaryBody, String.raw`![\[\]\\\nX] .`));
  const strictOrdinary = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedOrdinary, generated], { encoding: 'utf8' });
  assert.match(strictOrdinary.stderr, /^unsupported ReservedBracketBody .*X\] \.$/m);
  for (const literal of ["'[!'", "'..'"]) {
    assert.ok(!strict.stderr.split('\n').some(line =>
      line.startsWith('unsupported SkippedReserved ') && line.endsWith(': ' + literal)));
  }
  const optionalBlankLines = join(work, 'OptionalBlankLines.hpeg');
  writeFileSync(optionalBlankLines, original.replace('BlankLines <- BlankLine+', 'BlankLines <- BlankLine*'));
  const strictBlankLines = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), optionalBlankLines, generated], { encoding: 'utf8' });
  assert.match(strictBlankLines.stderr, /^unsupported BlankLines .*: BlankLine\*$/m);
  const changedParaEnd = join(work, 'ChangedParaEnd.hpeg');
  writeFileSync(changedParaEnd, original.replace('ParaEnd <- Nl (BlankLine / !.)', 'ParaEnd <- Nl (BlankLines / !.)'));
  const strictParaEnd = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedParaEnd, generated], { encoding: 'utf8' });
  assert.match(strictParaEnd.stderr, /^unsupported ParaEnd .*: BlankLines$/m);
  const changedWsBoundary = join(work, 'ChangedWsBoundary.hpeg');
  writeFileSync(changedWsBoundary, original.replace(/^Ws <- .*$/m, 'Ws <- [ ]+ { () }'));
  const strictWsBoundary = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedWsBoundary, generated], { encoding: 'utf8' });
  assert.match(strictWsBoundary.stderr, /^unsupported BlankLine .*: Ws\? Nl$/m);
  assert.match(strictWsBoundary.stderr, /^unsupported EOL .*: Sp /m);
  const wrongLabel = join(work, 'WrongIndentedLabel.hpeg');
  writeFileSync(wrongLabel, original.replace("'=:')^def_orphan", "'=:')^reserved"));
  const strictLabel = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), wrongLabel, generated], { encoding: 'utf8' });
  assert.match(strictLabel.stderr, /^unsupported OrphanDef .*\^reserved$/m);
  const changedIndent = join(work, 'ChangedIndent.hpeg');
  writeFileSync(changedIndent, original.replace("' ' Ind(n - 1)", "' ' Ind(n - 2)"));
  const strictIndent = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedIndent, generated], { encoding: 'utf8' });
  assert.match(strictIndent.stderr, /^unsupported Ind .*: ' ' Ind\(n - 2\)$/m);
  const changedMarker = join(work, 'ChangedMarker.hpeg');
  const marked = original.replace("/ '-' [ \\t] { () }", "/ '-' [ \\t] 'x' { () }");
  assert.notEqual(marked, original);
  writeFileSync(changedMarker, marked);
  const strictMarker = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedMarker, generated], { encoding: 'utf8' });
  assert.match(strictMarker.stderr, /^unsupported BlockStart .*: '-' \[ \\t\] 'x'$/m);
  assert.match(strict.stderr, /^unsupported BlockStart .*: SetDeclarationStart$/m);
  const changedSkipped = join(work, 'ChangedSkipped.hpeg');
  writeFileSync(changedSkipped, original.replace("/ '..' { () }", "/ '..' 'x' { () }"));
  const strictSkipped = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSkipped, generated], { encoding: 'utf8' });
  assert.match(strictSkipped.stderr, /^unsupported SkippedReserved .*: '\.\.' 'x'$/m);
  const changedHashKey = join(work, 'ChangedHashKey.hpeg');
  writeFileSync(changedHashKey, original.replace('(ExprIdent / StringLit) ES Colon', "(ExprIdent ':' / StringLit) ES Colon"));
  const strictHashKey = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedHashKey, generated], { encoding: 'utf8' });
  assert.match(strictHashKey.stderr, /^unsupported HashEntry .*: ExprIdent ':'$/m);
  assert.doesNotMatch(strict.stderr, /^unsupported HashEntry .*: (ExprIdent|StringLit)$/m);
  assert.doesNotMatch(strict.stderr, /^unsupported AttributedBlock .*: Heading\(ind\)$/m);
  const changedAt = join(work, 'ChangedAt.hpeg');
  writeFileSync(changedAt, original.replace("/ '@!' (!", "/ '@?' (!"));
  const strictAt = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedAt, generated], { encoding: 'utf8' });
  assert.match(strictAt.stderr, /^unsupported SkippedReserved .*: '@\?' /m);
  const changedReservedBody = join(work, 'ChangedReservedBody.hpeg');
  writeFileSync(changedReservedBody, original.replace(
    String.raw`ReservedBracketBody <- ( '\\' ![\n] .`,
    String.raw`ReservedBracketBody <- ( '\\' [\n] .`));
  const strictReservedBody = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedReservedBody, generated], { encoding: 'utf8' });
  assert.match(strictReservedBody.stderr, /unsupported ReservedBracketBody choice 2 at /,
    'a changed nested escape guard must return to the unsupported report');

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
  const modelTestSource = join(work, 'PegModelTest.lean');
  copyFileSync(join(here, 'PegModelTest.lean'), modelTestSource);
  const modelTests = spawnSync(lean, ['-o', join(work, 'PegModelTest.olean'), modelTestSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(modelTests.status, 0, modelTests.stdout + modelTests.stderr);
  const wordSource = join(work, 'WordRoundTrip.lean');
  copyFileSync(join(here, 'WordRoundTrip.lean'), wordSource);
  const wordProof = spawnSync(lean, ['-o', join(work, 'WordRoundTrip.olean'), wordSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(wordProof.status, 0, wordProof.stderr);
  const growthSource = join(here, 'LeftRecursionTotal.lean');
  const growthEnv = { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' };
  const boundaryProof = spawnSync(lean, [join(here, 'LineBoundaryTotal.lean')], growthEnv);
  assert.equal(boundaryProof.status, 0, boundaryProof.stdout + boundaryProof.stderr);
  const indentSource = join(work, 'IndentTotal.lean');
  copyFileSync(join(here, 'IndentTotal.lean'), indentSource);
  const indentProof = spawnSync(lean, ['-o', join(work, 'IndentTotal.olean'), indentSource], growthEnv);
  assert.equal(indentProof.status, 0, indentProof.stdout + indentProof.stderr);
  const growthProof = spawnSync(lean, [growthSource], growthEnv);
  assert.equal(growthProof.status, 0, growthProof.stdout + growthProof.stderr);
  const wrongOperator = join(work, 'WrongOperator.lean');
  const growthText = readFileSync(growthSource, 'utf8');
  const swapped = growthText.replace('binarySuffix "AddOp" "MulExpr"', 'binarySuffix "MulOp" "MulExpr"');
  assert.notEqual(swapped, growthText);
  writeFileSync(wrongOperator, swapped);
  const wrongGrowth = spawnSync(lean, [wrongOperator], growthEnv);
  assert.notEqual(wrongGrowth.status, 0);
  assert.match(wrongGrowth.stdout + wrongGrowth.stderr, /application type mismatch/);
  const stringProof = spawnSync(lean, [join(here, 'StringRoundTrip.lean')], { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(stringProof.status, 0, stringProof.stderr);
  const argumentsSource = join(work, 'ArgumentsRoundTrip.lean');
  copyFileSync(join(here, 'ArgumentsRoundTrip.lean'), argumentsSource);
  const argumentsProof = spawnSync(lean, ['-o', join(work, 'ArgumentsRoundTrip.olean'), argumentsSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(argumentsProof.status, 0, argumentsProof.stderr);
  const printedArgumentsProof = spawnSync(lean, [join(here, 'PrintedArguments.lean')],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(printedArgumentsProof.status, 0, printedArgumentsProof.stderr);
  const reservedBracketProof = spawnSync(lean, [join(here, 'ReservedBracketTotal.lean')],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(reservedBracketProof.status, 0, reservedBracketProof.stderr);
  const prefixBoundaryProof = spawnSync(lean, [join(here, 'PrefixBoundaryTotal.lean')],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(prefixBoundaryProof.status, 0, prefixBoundaryProof.stderr);
  const throwingSource = join(work, 'ThrowingPrefixTotal.lean');
  copyFileSync(join(here, 'ThrowingPrefixTotal.lean'), throwingSource);
  const throwingPrefixProof = spawnSync(lean, ['-o', join(work, 'ThrowingPrefixTotal.olean'), throwingSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(throwingPrefixProof.status, 0, throwingPrefixProof.stderr);
  const indentedLabel = spawnSync(lean, [join(here, 'IndentedLabelTotal.lean')], growthEnv);
  assert.equal(indentedLabel.status, 0, indentedLabel.stdout + indentedLabel.stderr);
  const backslashProof = spawnSync(lean, [join(here, 'BackslashTotal.lean')],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(backslashProof.status, 0, backslashProof.stdout + backslashProof.stderr);
  const escapeProof = spawnSync(lean, [join(here, 'EscapeTotal.lean')],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(escapeProof.status, 0, escapeProof.stderr);

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
  console.log(`grammar: source and AST rules ${emittedRuleCount}/${astRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proof modules 14, negative mutations 48, implementation parser cases ${parserCases.length}, syntax-only parser cases 1, rejected parser cases ${rejectedParserCases.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
