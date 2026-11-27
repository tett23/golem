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
  assert.doesNotMatch(strict.stderr, /^unsupported (Delim|TableDelimiter) choice /m,
    'root ADR 0351 I1/I2: delimiter and indented delimiter rows require arbitrary-input proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (Number|Ident|ES) choice /m,
    'root ADR 0351 I1/I2: numeric literals, command identifiers and expression trivia require recognition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (VarExpr|ProseSlots|LineContinuation) choice /m,
    'root ADR 0351 I1/I2: variables, prose slots and continuations require recognition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (CallExpr|RangeExpr) choice /m,
    'root ADR 0351 I1/I2: calls and complete range alternatives require recognition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (InlineCommand|Arguments|PosArg) choice /m,
    'root ADR 0351 I1/I2: ordered arguments and inline commands require recognition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (Paragraph|DefTerm|CodeBlock) choice /m,
    'root ADR 0351 I1/I2: paragraph, definition term and code fences require recognition proofs');
  // root ADR 0459 added four choices of the ::: body (GroupBody, Div, DivBlocks),
  // which recurse through Block like the other block structures.
  assert.doesNotMatch(strict.stderr, /^unsupported ReservedRange choice /m,
    'root ADR 0351 I1, I2: the reserved-range guards and label have an arbitrary-input proof');
  assert.ok(baselineUnsupported <= 24, 'the full grammar model must not regress in unsupported choices');
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
  assert.doesNotMatch(strict.stderr, /^unsupported RowBreak choice /m,
    'the table line-end guard and hard-break diagnostic must be covered');
  const changedRowBreak = join(work, 'ChangedRowBreak.hpeg');
  const rowBreakMutation = original.replace(/^RowBreak <- .*$/m,
    line => line.replace(' / !.)', " / !. / 'x')"));
  assert.notEqual(rowBreakMutation, original);
  writeFileSync(changedRowBreak, rowBreakMutation);
  const strictRowBreak = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedRowBreak, generated], { encoding: 'utf8' });
  assert.match(strictRowBreak.stderr, /unsupported RowBreak choice \d+ at .*'x'/,
    'a changed literal newline/EOF choice must return to the report');
  assert.doesNotMatch(strict.stderr, /^unsupported BlockCommandStart choice /m,
    'root ADR 0351 I1/I2 and root ADR 0391 I1/I2: only the @ prefix starts a declaration');
  const changedSetStart = join(work, 'ChangedBlockCommandStart.hpeg');
  const setStartMutation = original.replace("BlockCommandStart <- '@' [a-z]", "BlockCommandStart <- '@' [a-z] 'x'");
  assert.notEqual(setStartMutation, original);
  writeFileSync(changedSetStart, setStartMutation);
  const strictSetStart = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSetStart, generated], { encoding: 'utf8' });
  assert.match(strictSetStart.stderr, /unsupported BlockCommandStart choice \d+ at .*'x'/,
    'root ADR 0351 I1/I2: a changed command prefix must invalidate its recognition proof');
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
  assert.doesNotMatch(strict.stderr, /^unsupported RangeExpr choice .*: &'\.\.\.'/m,
    'a leading range operator throws range_end before parsing either endpoint');
  assert.doesNotMatch(strict.stderr, /^unsupported (SplatArgument|ExprCtx|ExprBody|KwArg|HashEntry|HardBreak|ArrayExpr|HashExpr) choice /m);
  assert.doesNotMatch(strict.stderr, /^unsupported (ProseSlot|SkippedArgs|TableCell|TableCellAndPipe) choice /m);
  assert.doesNotMatch(strict.stderr, /^unsupported (CodeClose|DefNew) choice /m);
  const changedSingleRef = join(work, 'ChangedSingleRef.hpeg');
  const singleRefMutation = original.replace(/^KeywordLiteral <- .*$/m,
    'KeywordLiteral <- Keyword Ws? { () }');
  assert.notEqual(singleRefMutation, original);
  writeFileSync(changedSingleRef, singleRefMutation);
  const strictSingleRef = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSingleRef, generated], { encoding: 'utf8' });
  assert.match(strictSingleRef.stderr, /unsupported KeywordLiteral choice 1 at .*Keyword Ws\?/,
    'an optional suffix must return a plain reference sequence to the unsupported report');
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

  const argumentParserCases = [
    ['[f]', { Argument: 0, KeywordArgument: 0 }], ['[f x]', { Argument: 1 }],
    ['[f ""]', { Argument: 1 }], ['[f x y]', { Argument: 2 }],
    ['[f key=x]', { KeywordArgument: 1, Argument: 0 }], ['[f x key=y]', { Argument: 1, KeywordArgument: 1 }],
    ['[f key=x more=y]', { KeywordArgument: 2 }], ['[f key=x key=x]', { KeywordArgument: 2 }],
    ['[f %%a%%]', { Argument: 0, KeywordArgument: 0, Comment: 1 }],
    ['[f %%=a%% x]', { Argument: 1, ProofComment: 1 }],
    ['[f %%a%% x %%b%% key=y %%=c%%]', { Argument: 1, KeywordArgument: 1, Comment: 2, ProofComment: 1 }],
    ['[f key=%%=abc]', { KeywordArgument: 1, ProofComment: 0 }],
    ['[f *[xs]]', { SplatArgument: 1 }], ['[f **[h]]', { SplatArgument: 1 }],
    ['[f *[xs] **[h]]', { SplatArgument: 2 }],
    ['[f x *[xs] key=y **[h]]', { Argument: 1, KeywordArgument: 1, SplatArgument: 2 }],
    ['[f [= 1+2] key=[= 3*4]]', { Argument: 1, KeywordArgument: 1 }],
    ['[f [g: x] key=[h: y]]', { Argument: 1, KeywordArgument: 1, InlineCommand: 3 }],
    ['[f x: text|more]', { Argument: 1, ProseSlot: 2 }],
    ['[f key=x: y]', { KeywordArgument: 1, ProseSlot: 1 }],
    ['[f x  ]', { Argument: 1 }], ['- [f: a\n  b]', { ProseSlot: 1 }],
  ];
  const blockLeafParserCases = [
    ['abc\n', 'Paragraph', { Paragraph: 1 }], ['あいう\n次\n', 'Paragraph', { Paragraph: 1 }],
    ['=term\n', 'Paragraph', { DefTerm: 0 }], ['=term\n  body\n', 'Paragraph', { DefTerm: 0, Paragraph: 1 }],
    ['= term\n  body\n', 'DefList', { DefTerm: 1 }],
    ['= [f: term]\n  body\n', 'DefList', { DefTerm: 1, InlineCommand: 1 }],
    ['= term\n= other\n  body\n', 'DefList', { DefTerm: 2 }],
    ['```\n```\n', 'CodeBlock', { CodeBlock: 1, CodeLine: 0 }],
    ['```hs key=x\nbody\n```\n', 'CodeBlock', { CodeBlock: 1, CodeLine: 1 }],
    ['- x\n  ```\n  body\n  ```\n', 'BulletList', { CodeBlock: 1, CodeLine: 1 }],
  ];
  const parserCases = [
    ['', null, 0],
    ['# Title\n', 'Heading', 0],
    ['@set x = 1\n', 'BlockCommand', 0],
    ['set x = 1\n', 'Paragraph', 0, 'Text@0..9 "set x = 1"'],
    ['set   x = 3\n', 'Paragraph', 0, 'Text@0..11 "set   x = 3"'],
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
    ['| a | b |\n|---|---|\n| c | d |\n', 'Table', 4],
    ...['-', ':-', '-:', ':-:', '---', '  :-:  ', '\t-\t'].map(delim =>
      [`| a |\n|${delim}|\n`, 'Table', 1]),
    ['@foo\n  | a |\n  |:-:|\n', 'BlockGroup', 1],
    ...['0', '01', '1.25', '1e2', '1e+2', '1e-2', '1.2e-3'].map(value =>
      [`@set x = ${value}\n`, 'BlockCommand', 0, `Number@9..${9 + value.length} "${value}"`]),
    ...['a', 'a0', 'a-b', 'book.tax-included', 'foo.bar0', 'foo.bar-z'].map(name =>
      [`[${name}]\n`, 'Paragraph', 0, `Ident@1..${1 + name.length} "${name}"`]),
    ['[a..b]\n', 'Paragraph', 0, 'Word@2..5 "..b"'],
    ['[a.]\n', 'Paragraph', 0, 'Word@2..3 "."'],
    ...['[=1+2]\n', '[= 1 + 2 ]\n', '[=\t1\t+\t2\t]\n', '[=%%a%%1+2]\n',
      ].map(sample => [sample, 'Paragraph', 0]),
    ['[=%%=a%%1%%b%%+%%=c%%2]\n', 'Paragraph', 0, 'ProofComment@2..8 "%%=a%%"'],
    ...['x', '_x', 'x0', 'x.y', 'x.y.z', 'truex'].map(name =>
      [`[= ${name}]\n`, 'Paragraph', 0, `VarExpr@3..${3 + name.length}\n`]),
    ['[= foo %%a%% . bar]\n', 'Paragraph', 0, 'VarExpr@3..18\n'],
    ...[['[f:]\n', 1], ['[f:|]\n', 2], ['[f:x]\n', 1], ['[f:x|y]\n', 2],
      ['[f:|x|]\n', 3], ['[f : x | y]\n', 2]].map(([sample, slots]) =>
      [sample, 'Paragraph', 0, `ProseSlots@2..${sample.length - 2}\n`, slots]),
    ['- [f:x|y]\n', 'BulletList', 0, 'ProseSlots@4..8\n', 2],
    ['- [f: a\n  b|c]\n', 'BulletList', 0, 'Ind@8..10 "  "', 2],
    ['a\nb\n', 'Paragraph', 0, 'LineContinuation@1..2\n'],
    ['a\\\nb\n', 'Paragraph', 0, 'LineContinuation@2..3\n'],
    ['a\n\nb\n', 'Paragraph', 0, 'Paragraph@3..5\n'],
    ['a\n# h\n', 'Heading', 0, 'Heading@2..6\n'],
    ['- a\n  b\n', 'BulletList', 0, 'Ind@4..6 "  "'],
    ['- a\n- b\n', 'BulletList', 0, 'ListItem@4..8\n'],
    ['a\n@foo\n', 'BlockGroup', 0, 'BlockCommand@2..7\n'],
    // root ADR 0459: a line of ::: ends the paragraph between ::: lines
    ['@foo\n:::\na\n:::\n', 'Div', 0, 'Paragraph@9..11\n', undefined, { DivMark: 2 }],
    ['@foo\n:::\na\nb\n:::\n', 'Div', 0, 'LineContinuation@10..11\n', undefined, { DivMark: 2 }],
    ['a\n:::\n', 'Paragraph', 0, 'LineContinuation@1..2\n', undefined, { DivMark: 0 }],
    ['a\n \t\nb\n', 'Paragraph', 0, 'Paragraph@5..7\n'],
    ...['foo()', 'foo(1)', 'foo(1,2)', 'foo(1,2,3)', 'foo.bar(1)',
      'foo(%%a%%1,%%=b%%2)', 'foo(bar(1),2)', 'foo([1, 2], {a: 3})',
      'foo(%%a%%)', 'foo . bar ( 1 )'].map(call =>
      [`[= ${call}]\n`, 'Paragraph', 0, `CallExpr@3..${3 + call.length}\n`]),
    ...['1...2', '1+2...3*4', '-1...2', '1...-2', '(1+2)...(3+4)', '1...2**3',
      '1 < 2', '(1...2) == (1...2)', '1.5...2e3', '1 ... %%a%% 2'].map(expr =>
      [`[= ${expr}]\n`, 'Paragraph', 0, `RangeExpr@3..${3 + expr.length}\n`]),
    ...blockLeafParserCases.map(([body, node, counts]) => [body, node, 0, undefined, undefined, counts]),
    ...argumentParserCases.map(([body, counts]) => [body + '\n', body.startsWith('- ') ? 'BulletList' : 'Paragraph', 0,
      `InlineCommand@${body.startsWith('- ') ? 2 : 0}..${body.length}\n`, undefined, counts])
  ];
  for (const [sample, node, cells, chosen, slots, counts] of parserCases) {
    const samplePath = join(work, 'sample.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^File@0\\.\\.${Buffer.byteLength(sample)}$`, 'm'),
      'the implementation parser must consume the same complete source');
    if (node) assert.match(parsed.stdout, new RegExp(`^ +(?:[a-z]+: )?${node}@`, 'm'));
    if (chosen) assert.ok(parsed.stdout.includes(chosen), `${chosen} was not chosen by the generated parser`);
    assert.equal([...parsed.stdout.matchAll(/cs: TableCellAndPipe@/g)].length, cells);
    if (slots !== undefined) assert.equal([...parsed.stdout.matchAll(/^ +ProseSlot@/gm)].length, slots,
      'root ADR 0351 I1/I2: every empty and nonempty prose slot occurs in the committed CST');
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count,
        `root ADR 0351 I1/I2: ${kind} must retain every argument and comment occurrence`);
    }
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

  const badDelimiterCases = ['', ':', '::', '--x', '-:x', ': -', '- -'];
  for (const delim of badDelimiterCases) {
    const samplePath = join(work, 'bad-delimiter.gm');
    writeFileSync(samplePath, `| a |\n|${delim}|\n`);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, 'root ADR 0351 I1/I2: delimiter requires a contiguous nonempty dash run');
    assert.match(parsed.stderr, /^2:\d+: expected /m);
  }

  const lexicalRejectedCases = [
    ...['.5', '1.', '1e', '1e+', '1E2'].map(value => `@set x = ${value}\n`),
    ...['A', '_a', '1a', 'a.b.c'].map(name => `[${name}]\n`),
    '[=1%%a+2]\n', '[=1%%=a+2]\n',
  ];
  for (const sample of lexicalRejectedCases) {
    const samplePath = join(work, 'bad-lexical.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1/I2: reject invalid lexical boundary ${JSON.stringify(sample)}`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }

  const compositionRejectedCases = [
    '[= .x]\n', '[= x.]\n', '[= x..y]\n', '[f:x|y\n',
    'a\\\n', 'a\\\n\nb\n', 'a\\\n# h\n', '- a\\\n b\n',
  ];
  for (const sample of compositionRejectedCases) {
    const samplePath = join(work, 'bad-composition.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1/I2: reject invalid composition ${JSON.stringify(sample)}`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }

  const argumentRejectedCases = ['[f key=x y]', '[f **[h] x]', '[f key=x *[xs]]', '[f %%=bad]',
    '[f "x]', '[f *[xs] **[h] x]', '[f **[h] *[xs]]', '[f key=]', '[f **[]]'];
  for (const body of argumentRejectedCases) {
    const samplePath = join(work, 'bad-argument-order.gm');
    writeFileSync(samplePath, body + '\n');
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1/I2: reject invalid argument order/body ${body}`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }
  const blockLeafRejectedCases = ['#bad\n', '= \n  body\n', '```\nbody\n', '``` bad=x y\n```\n'];
  for (const sample of blockLeafRejectedCases) {
    const samplePath = join(work, 'bad-block-leaf.gm');
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1/I2: reject invalid block leaf ${JSON.stringify(sample)}`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }
  const blockLeafMutations = [
    ['ParaBlockGuard', 'Paragraph <- Ind(ind) ![ \\t] !BlockStart', 'Paragraph <- Ind(ind) ![ \\t]', 'Paragraph'],
    ['ParaInlinePlus', 'Paragraph <- Ind(ind) ![ \\t] !BlockStart Inline(ind)+', 'Paragraph <- Ind(ind) ![ \\t] !BlockStart Inline(ind)*', 'Paragraph'],
    ['ParaIndentGuard', 'Paragraph <- Ind(ind) ![ \\t]', 'Paragraph <- Ind(ind)', 'Paragraph'],
    ['TermPlus', 'DefTerm <- Ind(ind) TermMark Ws HeadInline(col ind + 2)+', 'DefTerm <- Ind(ind) TermMark Ws HeadInline(col ind + 2)*', 'DefTerm'],
    ['TermIndent', 'DefTerm <- Ind(ind) TermMark Ws HeadInline(col ind + 2)+', 'DefTerm <- Ind(ind) TermMark Ws HeadInline(ind)+', 'DefTerm'],
    ['TermWs', 'DefTerm <- Ind(ind) TermMark Ws', 'DefTerm <- Ind(ind) TermMark Ws?', 'DefTerm'],
    ['CodeClosingGuard', '(!CodeClose(ind) CodeLine)*', '(CodeLine)*', 'CodeBlock'],
    ['CodeNeedLine', '(!CodeClose(ind) CodeLine)*', '(!CodeClose(ind) CodeLine)+', 'CodeBlock'],
    ['CodeClosingZero', '(CodeClose(ind))^code_close', '(CodeClose(0))^code_close', 'CodeBlock'],
    ['CodeFenceDependency', "Fence <- '```'", "Fence <- '~~~'", 'CodeBlock'],
  ];
  for (const [name, before, after, rule] of blockLeafMutations) {
    assert.ok(original.includes(before));
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, original.replace(before, after));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate the block composition proof`);
  }
  const nativeBlockLeafMutations = [
    ['ParaBlockGuard', '#bad\n', true, { Paragraph: 1, Heading: 0 }],
    ['TermPlus', '= \n  body\n', true, { DefTerm: 1 }],
    ['TermWs', '=term\n  body\n', true, { DefTerm: 1 }],
    ['CodeClosingGuard', '```\n```\n', false],
    ['CodeNeedLine', '```\n```\n', false],
    ['CodeClosingZero', '- x\n  ```\n  body\n  ```\n', false],
  ];
  for (const [name, sample, accepted, counts] of nativeBlockLeafMutations) {
    const [, before, after] = blockLeafMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-block-leaf.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted,
      `root ADR 0351 I1/I2: ${name} must change the committed block boundary: ${parsed.stderr}`);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count,
        `root ADR 0351 I1/I2: ${name} must change ${kind} occurrences`);
    }
  }
  const argumentMutations = [
    ['PosSplatGuard', "PosArg <- !'%%' !(Word Eq) !'**[' SplatArgument", "PosArg <- !'%%' !(Word Eq) SplatArgument", 'PosArg'],
    ['PosKeywordGuard', "/ !'%%' !(Word Eq) !Splat Argument", "/ !'%%' !Splat Argument", 'PosArg'],
    ['ArgsNeedComment', 'Arguments <- (Sp ArgComment)*', 'Arguments <- (Sp ArgComment)+', 'Arguments'],
    ['ArgsPosNoComments', '(Sp PosArg (Sp ArgComment)*)*', '(Sp PosArg)*', 'Arguments'],
    ['ArgsKwNoComments', '(Sp KwArg (Sp ArgComment)*)*', '(Sp KwArg)*', 'Arguments'],
    ['ArgsAllowTailPos', '(Sp KwArg (Sp ArgComment)*)* (!(Sp PosArg))^arg_order', '(Sp KwArg (Sp ArgComment)*)* (Sp PosArg)* (!(Sp PosArg))^arg_order', 'Arguments'],
    ['InlineProseZero', 'InlineCommand <- LBr Ident Arguments ProseSlots(ind)?', 'InlineCommand <- LBr Ident Arguments ProseSlots(0)?', 'InlineCommand'],
    ['InlineNoCloseSpace', 'ProseSlots(ind)? (Sp RBr)^close', 'ProseSlots(ind)? (RBr)^close', 'InlineCommand'],
    ['ArgCommentOrder', 'ArgComment <- ProofComment { () } / Comment { () }', 'ArgComment <- Comment { () } / ProofComment { () }', 'Arguments'],
    ['ArgEqDependency', "Eq <- '='", "Eq <- '=='", 'Arguments'],
  ];
  for (const [name, before, after, rule] of argumentMutations) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original, `root ADR 0351 I1/I2: ${name} must alter an argument production or dependency`);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate the argument recognition proof`);
  }
  const nativeArgumentMutations = [
    ['PosSplatGuard', '[f **[h] x]\n', true, { SplatArgument: 1, Argument: 1 }],
    ['PosKeywordGuard', '[f key=x]\n', false],
    ['ArgsAllowTailPos', '[f key=x y]\n', true, { KeywordArgument: 1, Argument: 1 }],
    ['InlineNoCloseSpace', '[f x  ]\n', false],
    ['ArgCommentOrder', '[f %%=a%% x]\n', true, { ProofComment: 0, Comment: 1 }],
    ['InlineProseZero', '- [f: a\n  b]\n', true, {}, 'SlotText@8..11 "  b"', 'Ind@8..10 "  "'],
  ];
  for (const [name, sample, accepted, counts, chosen, absent] of nativeArgumentMutations) {
    const [, before, after] = argumentMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-argument-order.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted,
      `root ADR 0351 I1/I2: ${name} must change the committed argument boundary: ${parsed.stderr}`);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count,
        `root ADR 0351 I1/I2: ${name} must change ${kind} occurrences`);
    }
    if (chosen) assert.ok(parsed.stdout.includes(chosen), `root ADR 0351 I1/I2: ${name} must change the slot text`);
    if (absent) assert.ok(!parsed.stdout.includes(absent), `root ADR 0351 I1/I2: ${name} must change indentation consumption`);
  }

  const expressionRejectedCases = ['foo(,1)', 'foo(1,)', 'foo.bar.baz(1)', 'foo(1, ,2)', 'foo(',
    '...2', '1...', '1...2...3', '1..2', '1...2..3', '1....2', '1...2<3'];
  for (const expr of expressionRejectedCases) {
    const samplePath = join(work, 'bad-expression.gm');
    writeFileSync(samplePath, `[= ${expr}]\n`);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', source, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1/I2: reject invalid call/range ${expr}`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }

  const closedAlternative = "           / AddExpr ES RangeOp ES (AddExpr)^range_end (!(ES '..'))^range_end { () }";
  const compareAlternative = '           / CompareExpr { () }';
  const expressionMutations = [
    ['CallNamespaceMany', 'CallExpr <- ExprIdent (ES Dot ES ExprIdent)?', 'CallExpr <- ExprIdent (ES Dot ES ExprIdent)*', 'CallExpr'],
    ['CallRequiredArgs', '(Expr ES (Comma ES Expr ES)*)? RParen', '(Expr ES (Comma ES Expr ES)*) RParen', 'CallExpr'],
    ['CallMoreArgs', '(Expr ES (Comma ES Expr ES)*)? RParen', '(Expr ES (Comma ES Expr ES)+)? RParen', 'CallExpr'],
    ['CallDotDependency', "Dot <- '.'", "Dot <- ':'", 'CallExpr'],
    ['RangeEndExpr', '(AddExpr)^range_end', '(Expr)^range_end', 'RangeExpr'],
    ['RangePriority', closedAlternative + '\n' + compareAlternative, compareAlternative + '\n' + closedAlternative, 'RangeExpr'],
    ['RangePrefixLabel', "(&{ False } '...')^range_end", "(&{ False } '...')^reserved", 'RangeExpr'],
    ['RangeOpDependency', "RangeOp <- '...'", "RangeOp <- '....'", 'RangeExpr'],
  ];
  for (const [name, before, after, rule] of expressionMutations) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original, `root ADR 0351 I1/I2: ${name} must alter a canonical production or dependency`);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate its recognition proof`);
  }

  const reservedRangeBody = original.match(/^ReservedRange <- ([\s\S]*?) \{ \(\) \}/m)?.[1];
  assert.equal(reservedRangeBody?.replace(/\s+/g, ' '),
    "!'...' &'..' (&{ False } '..')^reserved (ES AddExpr)? (ES (ReservedRange / RangeOp (ES AddExpr)?))*");
  const reservedRangeMutations = [
    ['ReservedExcludedGuard', "!'...'", "&'...'"],
    ['ReservedLookahead', "&'..'", "&'...'"],
    ['ReservedFalsePredicate', '&{ False }', '&{ True }'],
    ['ReservedLabel', '^reserved', '^range_end'],
    ['ReservedSuffix', '(ES AddExpr)?', '(ES AddExpr)+'],
    ['ReservedNestedPriority', 'ReservedRange / RangeOp (ES AddExpr)?', 'RangeOp (ES AddExpr)? / ReservedRange'],
  ];
  for (const [name, before, after] of reservedRangeMutations) {
    const changedBody = reservedRangeBody.replace(before, after);
    assert.notEqual(changedBody, reservedRangeBody);
    const changedPath = join(work, name + '.hpeg');
    const changed = original.replace(reservedRangeBody, changedBody);
    assert.notEqual(changed, original);
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /^unsupported ReservedRange choice /m,
      `root ADR 0351 I1/I2: ${name} must invalidate the exact generated rule proof`);
  }
  const nativeReservedPath = join(work, 'NativeReservedFalsePredicate.hpeg');
  writeFileSync(nativeReservedPath, original.replace(reservedRangeBody,
    reservedRangeBody.replace('&{ False }', '&{ True }')));
  const nativeReservedSample = join(work, 'native-reserved-range.gm');
  writeFileSync(nativeReservedSample, '[= 1..2]\n');
  const nativeReserved = spawnSync(process.env.PEG_HS ?? 'peg-hs',
    ['parse', '--format', 'cst', nativeReservedPath, nativeReservedSample],
    { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
  assert.equal(nativeReserved.status, 0, nativeReserved.stdout + nativeReserved.stderr);
  assert.match(nativeReserved.stdout, /RangeExpr@3\.\.7/,
    'root ADR 0351: changing the always-failing predicate must accept the previously rejected range');
  assert.match(nativeReserved.stdout, /TEXT@4\.\.6 \"\.\.\"/,
    'the accepted CST must contain the two reserved dots at their original span');

  const nativeExpressionMutations = [
    ['CallNamespaceMany', '[= foo.bar.baz(1)]\n', true, { CallExpr: 1, ExprIdent: 3 }],
    ['CallRequiredArgs', '[= foo()]\n', false],
    ['RangeEndExpr', '[= 1...2...3]\n', true, { RangeExpr: 3, RangeOp: 2, Number: 3 }],
    ['RangePriority', '[= 1...2]\n', false],
  ];
  for (const [name, sample, accepted, counts] of nativeExpressionMutations) {
    const [, before, after] = expressionMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-expression.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted,
      `root ADR 0351 I1/I2: ${name} must change the native boundary: ${parsed.stderr}`);
    for (const [node, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +(?:[a-z]+: )?${node}@`, 'gm'))].length, count,
        `root ADR 0351 I1/I2: ${name} must change the committed call/range CST`);
    }
  }

  const compositionMutations = [
    ['VarNeedsDot', 'VarExpr <- !Keyword ExprIdent (ES Dot ES ExprIdent)*', 'VarExpr <- !Keyword ExprIdent (ES Dot ES ExprIdent)+', 'VarExpr'],
    ['VarComma', 'VarExpr <- !Keyword ExprIdent (ES Dot ES ExprIdent)*', 'VarExpr <- !Keyword ExprIdent (ES Comma ES ExprIdent)*', 'VarExpr'],
    ['SlotsNeedMore', 'ProseSlot(ind) (Sp Pipe Sp ProseSlot(ind))*', 'ProseSlot(ind) (Sp Pipe Sp ProseSlot(ind))+', 'ProseSlots'],
    ['SlotsColon', 'ProseSlot(ind) (Sp Pipe Sp ProseSlot(ind))*', 'ProseSlot(ind) (Sp Colon Sp ProseSlot(ind))*', 'ProseSlots'],
    ['ContinuationBlank', 'LineContinuation <- Nl !BlankLine Ind(ind) !BlockStart', 'LineContinuation <- Nl Ind(ind) !BlockStart', 'LineContinuation'],
    ['ContinuationBlock', 'LineContinuation <- Nl !BlankLine Ind(ind) !BlockStart', 'LineContinuation <- Nl !BlankLine Ind(ind)', 'LineContinuation'],
    ['ContinuationIndent', 'LineContinuation <- Nl !BlankLine Ind(ind) !BlockStart', 'LineContinuation <- Nl !BlankLine Ind(0) !BlockStart', 'LineContinuation'],
    ['VarDotDependency', "Dot <- '.'", "Dot <- ','", 'VarExpr'],
    ['SlotsBodyDependency', 'ProseSlot <- SlotInline(ind)*', 'ProseSlot <- SlotInline(ind)+', 'ProseSlots'],
    ['ContinuationMarkerDependency', "/ '@!' { () }", "/ '@?' { () }", 'LineContinuation'],
    ['ContinuationSeparatorDependency', "BlockStart <- '---' Sp (Nl / !.)", "BlockStart <- '---' (Nl / !.)", 'LineContinuation'],
    ['SeparatorLineEnd', "SeparatorLine <- Ind(ind) '---' EOL", "SeparatorLine <- Ind(ind) '---' Sp", 'SeparatorLine'],
    // root ADR 0459: the ::: guard of a continuation, the ::: line and the
    // helpers that give the indentation parameter its fence bit
    ['ContinuationFence', '!BlockStart !(&{ inFence ind } DivLine)', '!BlockStart', 'LineContinuation'],
    ['ContinuationFenceAlways', '!(&{ inFence ind } DivLine)', '!(DivLine)', 'LineContinuation'],
    ['DivLineEnd', "DivLine <- ':::' Sp (Nl / !.)", "DivLine <- ':::' (Nl / !.)", 'DivLine'],
    ['ContinuationDivLineDependency', "DivLine <- ':::' Sp (Nl / !.)", "DivLine <- '::' Sp (Nl / !.)", 'LineContinuation'],
    ['HelperFenceBit', 'fenceBit = 1048576', 'fenceBit = 1024', 'Ind'],
    ['HelperColumn', 'col n = mod n fenceBit', 'col n = n', 'Ind'],
    ['HelperInFence', 'inFence n = n >= fenceBit', 'inFence n = n > fenceBit', 'LineContinuation'],
  ];
  for (const [name, before, after, rule] of compositionMutations) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original, `root ADR 0351 I1/I2: ${name} must alter a canonical production or dependency`);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate its dependent recognition proof`);
  }

  const nativeCompositionMutations = [
    ['VarNeedsDot', '[= x]\n', false],
    ['SlotsNeedMore', '[f:x]\n', false],
    ['ContinuationBlank', 'a\n\nb\n', true, { Paragraph: 1 }],
    ['ContinuationBlock', 'a\\\n# h\n', true, { Paragraph: 1, Heading: 0 }],
    ['ContinuationSeparatorDependency', 'a\n--- \n', true, { Paragraph: 1, SeparatorLine: 0 }],
    ['ContinuationFence', '@foo\n:::\na\n:::\n', true, { Paragraph: 1, DivMark: 1 }],
  ];
  for (const [name, sample, accepted, counts] of nativeCompositionMutations) {
    const [, before, after] = compositionMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-composition.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted,
      `root ADR 0351 I1/I2: ${name} must change the native boundary: ${parsed.stderr}`);
    for (const [node, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +(?:[a-z]+: )?${node}@`, 'gm'))].length, count,
        `root ADR 0351 I1/I2: ${name} must expose changed block boundaries in the committed CST`);
    }
  }

  const lexicalMutations = [
    ['NumberRequiredFraction', "Number <- [0-9]+ ('.' [0-9]+)?", "Number <- [0-9]+ ('.' [0-9]+)", 'Number'],
    ['NumberUpperExponent', "('e' [+\\-]? [0-9]+)?", "('E' [+\\-]? [0-9]+)?", 'Number'],
    ['IdentLeadingDigit', 'Ident <- [a-z]', 'Ident <- [a-z0-9]', 'Ident'],
    ['IdentNoGuard', " !('.' [a-z]) { () }", ' { () }', 'Ident'],
    ['ESNonempty', 'ES <- (Ws? ExprComment)* Ws?', 'ES <- (Ws? ExprComment)+ Ws?', 'ES'],
    ['ESNoProofComment', 'ExprComment <- ProofComment { () } / Comment { () }', 'ExprComment <- Comment { () }', 'ES'],
  ];
  for (const [name, before, after, rule] of lexicalMutations) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original, `root ADR 0351 I1/I2: ${name} must alter the canonical production`);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate its recognition proof`);
  }

  const nativeLexicalMutations = [
    ['NumberRequiredFraction', '@set x = 0\n', false, null],
    ['IdentNoGuard', '[a.b.c]\n', true, 'Word@4..6 ".c"'],
    ['ESNoProofComment', '[=%%=a%%1+2]\n', true, 'Comment@2..8 "%%=a%%"'],
  ];
  for (const [name, sample, accepted, chosen] of nativeLexicalMutations) {
    const [, before, after] = lexicalMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-lexical-boundary.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted,
      `root ADR 0351 I1/I2: ${name} must change the native boundary: ${parsed.stderr}`);
    if (chosen) assert.ok(parsed.stdout.includes(chosen),
      `root ADR 0351 I1/I2: ${name} must expose its changed committed CST path`);
  }

  const delimiterMutations = [
    ['DelimLeadingColon', "Delim <- Sp ':'? '-'+ ':'? Sp", "Delim <- Sp ':' '-'+ ':'? Sp", 'Delim'],
    ['DelimEmptyDashes', "Delim <- Sp ':'? '-'+ ':'? Sp", "Delim <- Sp ':'? '-'* ':'? Sp", 'Delim'],
    ['TableDelimiterEmpty', 'TableDelimiter <- Ind(ind) (Pipe Delim)+ Pipe Sp', 'TableDelimiter <- Ind(ind) (Pipe Delim)* Pipe Sp', 'TableDelimiter'],
    ['TableDelimiterEnd', 'TableDelimiter <- Ind(ind) (Pipe Delim)+ Pipe Sp', 'TableDelimiter <- Ind(ind) (Pipe Delim)+ Sp', 'TableDelimiter'],
  ];
  for (const [name, before, after, rule] of delimiterMutations) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original, `root ADR 0351 I1/I2: ${name} must alter the canonical production`);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1/I2: ${name} must invalidate its recognition proof`);
    if (rule === 'Delim') assert.match(rejected.stderr, /^unsupported TableDelimiter choice /m,
      'root ADR 0351 I1/I2: a changed delimiter must invalidate the dependent row proof');
  }

  const emptyRowSource = join(work, 'EmptyDelimiterRow.hpeg');
  writeFileSync(emptyRowSource, original.replace('TableDelimiter <- Ind(ind) (Pipe Delim)+ Pipe Sp',
    'TableDelimiter <- Ind(ind) (Pipe Delim)* Pipe Sp'));
  const emptyRowInput = join(work, 'empty-delimiter-row.gm');
  writeFileSync(emptyRowInput, '| a |\n|\n');
  const parseEmptyRow = grammar => spawnSync(process.env.PEG_HS ?? 'peg-hs',
    ['parse', '--format', 'cst', grammar, emptyRowInput],
    { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
  const emptyRow = parseEmptyRow(source);
  assert.notEqual(emptyRow.status, 0, 'root ADR 0351 I1/I2: an empty delimiter row must fail');
  assert.match(emptyRow.stderr, /^2:\d+: expected /m);
  const weakenedEmptyRow = parseEmptyRow(emptyRowSource);
  assert.equal(weakenedEmptyRow.status, 0, weakenedEmptyRow.stderr);
  assert.match(weakenedEmptyRow.stdout, /^ +Table@/m,
    'root ADR 0351 I1/I2: weakening plus to star must expose the native parser boundary');

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
  assert.doesNotMatch(strict.stderr, /^unsupported BlockStart .*: !NumberOpen '#'$/m);
  assert.match(strictNumberOpen.stderr, /^unsupported BlockStart .*: !NumberOpen '#'$/m,
    'the heading prefix proof depends on the exact NumberOpen grammar');
  const changedHeadingPrefix = join(work, 'ChangedHeadingPrefix.hpeg');
  const headingPrefixMutation = original.replace("/ !NumberOpen '#' {", "/ !NumberOpen '##' {");
  assert.notEqual(headingPrefixMutation, original);
  writeFileSync(changedHeadingPrefix, headingPrefixMutation);
  const strictHeadingPrefix = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedHeadingPrefix, generated], { encoding: 'utf8' });
  assert.match(strictHeadingPrefix.stderr, /^unsupported BlockStart .*: !NumberOpen '##'$/m);
  assert.match(strictNumberOpen.stderr, /unsupported NumberOpen choice 1 at /,
    'a changed required class must return to the unsupported report');
  const changedSetIdent = join(work, 'ChangedSetIdent.hpeg');
  writeFileSync(changedSetIdent, original.replace(/^SetIdent <- .*$/m,
    "SetIdent <- 'set' ![a-z] { () }"));
  const strictSetIdent = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedSetIdent, generated], { encoding: 'utf8' });
  assert.match(strictSetIdent.stderr, /unsupported SetIdent choice 1 at /,
    'a changed boundary class must return to the unsupported report');
  assert.doesNotMatch(strict.stderr, /^unsupported (Heading|TooDeep|BadBreak) choice /m,
    'the canonical throwing prefixes have all-input proofs');
  const changedTooDeep = join(work, 'ChangedTooDeep.hpeg');
  writeFileSync(changedTooDeep, original.replace(/^TooDeep <- .*$/m,
    "TooDeep <- &'#' (&{ False } '#')^changed { () }"));
  const strictTooDeep = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedTooDeep, generated], { encoding: 'utf8' });
  assert.match(strictTooDeep.stderr, /unsupported TooDeep choice 1 at /,
    'a changed lookahead label must return to the unsupported report');
  assert.match(strictTooDeep.stderr, /unsupported Heading choice 1 at /,
    'heading dispatch depends on the TooDeep diagnostic');
  const changedBadBreak = join(work, 'ChangedBadBreak.hpeg');
  writeFileSync(changedBadBreak, original.replace(/^BadBreak <- .*$/m,
    "BadBreak <- '\\\\' (&{ False })^changed { () }"));
  const strictBadBreak = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedBadBreak, generated], { encoding: 'utf8' });
  assert.match(strictBadBreak.stderr, /unsupported BadBreak choice 1 at /,
    'a changed literal label must return to the unsupported report');
  assert.match(strictBadBreak.stderr, /unsupported RowBreak choice 1 at /,
    'the table line-end error must follow the BadBreak label');
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
  const changedChain = join(work, 'ChangedChain.hpeg');
  writeFileSync(changedChain, original.replace('AddExpr ES CmpOp ES AddExpr', 'AddExpr ES CmpOp ES AddExpr?'));
  const strictChain = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedChain, generated], { encoding: 'utf8' });
  assert.match(strictChain.stderr, /^unsupported CompareExpr .*AddExpr\?$/m);
  assert.doesNotMatch(strict.stderr, /^unsupported (AddExpr|MulExpr) choice /m);
  const requiredClose = join(work, 'RequiredClose.hpeg');
  writeFileSync(requiredClose, original.replace('NumberMark NumberBody NumberMark?', 'NumberMark NumberBody NumberMark'));
  const strictShorthand = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), requiredClose, generated], { encoding: 'utf8' });
  assert.match(strictShorthand.stderr, /^unsupported NumberShorthand .*NumberBody NumberMark$/m);
  const noCommentGuard = join(work, 'NoCommentGuard.hpeg');
  writeFileSync(noCommentGuard, original.replace(/^(SlotText <- .*?) !'%%'/m, '$1'));
  const strictText = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), noCommentGuard, generated], { encoding: 'utf8' });
  assert.match(strictText.stderr, /^unsupported SlotText /m);
  const wrongComment = join(work, 'WrongComment.hpeg');
  writeFileSync(wrongComment, original.replace(/^(ProofComment <- .*?)!ParaEnd/m, '$1!EOL'));
  const strictComment = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), wrongComment, generated], { encoding: 'utf8' });
  assert.match(strictComment.stderr, /^unsupported ProofComment .*?!EOL/m);
  const wrongIndentLabel = join(work, 'WrongIndentLabel.hpeg');
  writeFileSync(wrongIndentLabel, original.replace(/^(BadIndent <- .*)\^indent/m, '$1^block'));
  const strictBadIndent = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), wrongIndentLabel, generated], { encoding: 'utf8' });
  assert.match(strictBadIndent.stderr, /^unsupported BadIndent .*\^block$/m);
  const changedIdent = join(work, 'ChangedExprIdent.hpeg');
  writeFileSync(changedIdent, original.replace('ExprIdent <- [a-zA-Z_] [a-zA-Z0-9_]*',
    'ExprIdent <- [a-zA-Z0-9_] [a-zA-Z0-9_]*'));
  const strictIdent = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedIdent, generated], { encoding: 'utf8' });
  assert.match(strictIdent.stderr, /^unsupported ExprIdent /m);
  const differentMarker = join(work, 'DifferentMarker.hpeg');
  writeFileSync(differentMarker, original.replace("OrderedMark <- '+'", "OrderedMark <- '-'"));
  const strictListMark = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), differentMarker, generated], { encoding: 'utf8' });
  assert.match(strictListMark.stderr, /^unsupported ListMark .*OrderedMark$/m);
  const optionalBlankLines = join(work, 'OptionalBlankLines.hpeg');
  writeFileSync(optionalBlankLines, original.replace('BlankLines <- BlankLine+', 'BlankLines <- BlankLine*'));
  const strictBlankLines = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), optionalBlankLines, generated], { encoding: 'utf8' });
  assert.match(strictBlankLines.stderr, /^unsupported BlankLines .*: BlankLine\*$/m);
  const changedParaEnd = join(work, 'ChangedParaEnd.hpeg');
  writeFileSync(changedParaEnd, original.replace('ParaEnd <- Nl (BlankLine / !.)', 'ParaEnd <- Nl (BlankLines / !.)'));
  const strictParaEnd = spawnSync(process.execPath,
    [join(here, 'generate.mjs'), changedParaEnd, generated], { encoding: 'utf8' });
  for (const rule of ['Rest', 'SkippedExpr']) {
    const unsupported = new RegExp('^unsupported ' + rule + ' choice ', 'm');
    assert.doesNotMatch(strict.stderr, unsupported);
    assert.match(strictParaEnd.stderr, unsupported);
  }
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
  assert.doesNotMatch(original, /^SetDeclarationStart <- /m, 'root ADR 0391 I2: no unprefixed declaration rule remains');
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
  assert.doesNotMatch(strict.stderr, /^unsupported (Block|AttributedBlock) choice /m);
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
  const repetitionSource = join(work, 'RuleRepetition.lean');
  copyFileSync(join(here, 'RuleRepetition.lean'), repetitionSource);
  const repetitionProof = spawnSync(lean, ['-o', join(work, 'RuleRepetition.olean'), repetitionSource], growthEnv);
  assert.equal(repetitionProof.status, 0, repetitionProof.stdout + repetitionProof.stderr);
  const chainProof = spawnSync(lean, [join(here, 'ReferenceSequence.lean')], growthEnv);
  assert.equal(chainProof.status, 0, chainProof.stdout + chainProof.stderr);
  const listMarkProof = spawnSync(lean, [join(here, 'ListMarkTotal.lean')], growthEnv);
  assert.equal(listMarkProof.status, 0, listMarkProof.stdout + listMarkProof.stderr);
  const boundarySource = join(work, 'LineBoundaryTotal.lean');
  copyFileSync(join(here, 'LineBoundaryTotal.lean'), boundarySource);
  const boundaryProof = spawnSync(lean, ['-o', join(work, 'LineBoundaryTotal.olean'), boundarySource], growthEnv);
  assert.equal(boundaryProof.status, 0, boundaryProof.stdout + boundaryProof.stderr);
  const commentProof = spawnSync(lean, [join(here, 'CommentTotal.lean')], growthEnv);
  assert.equal(commentProof.status, 0, commentProof.stdout + commentProof.stderr);
  const identProof = spawnSync(lean, [join(here, 'ExpressionIdentTotal.lean')], growthEnv);
  assert.equal(identProof.status, 0, identProof.stdout + identProof.stderr);
  const indentSource = join(work, 'IndentTotal.lean');
  copyFileSync(join(here, 'IndentTotal.lean'), indentSource);
  const indentProof = spawnSync(lean, ['-o', join(work, 'IndentTotal.olean'), indentSource], growthEnv);
  assert.equal(indentProof.status, 0, indentProof.stdout + indentProof.stderr);
  const delimiterProof = spawnSync(lean, [join(here, 'TableDelimiterTotal.lean')], growthEnv);
  assert.equal(delimiterProof.status, 0, delimiterProof.stdout + delimiterProof.stderr);
  const lexicalSource = join(work, 'LexicalTotal.lean');
  copyFileSync(join(here, 'LexicalTotal.lean'), lexicalSource);
  const lexicalProof = spawnSync(lean, ['-o', join(work, 'LexicalTotal.olean'), lexicalSource], growthEnv);
  assert.equal(lexicalProof.status, 0, lexicalProof.stdout + lexicalProof.stderr);
  const compositionSource = join(work, 'SyntaxComposition.lean');
  copyFileSync(join(here, 'SyntaxComposition.lean'), compositionSource);
  const compositionProof = spawnSync(lean, ['-o', join(work, 'SyntaxComposition.olean'), compositionSource], growthEnv);
  assert.equal(compositionProof.status, 0, compositionProof.stdout + compositionProof.stderr);
  const markerProof = spawnSync(lean, [join(here, 'IndentedMarkerLine.lean')], growthEnv);
  assert.equal(markerProof.status, 0, markerProof.stdout + markerProof.stderr);
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
  const prefixSource = join(work, 'PrefixBoundaryTotal.lean');
  copyFileSync(join(here, 'PrefixBoundaryTotal.lean'), prefixSource);
  const prefixBoundaryProof = spawnSync(lean, ['-o', join(work, 'PrefixBoundaryTotal.olean'), prefixSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(prefixBoundaryProof.status, 0, prefixBoundaryProof.stderr);
  const textRun = spawnSync(lean, [join(here, 'TextRunTotal.lean')], growthEnv);
  assert.equal(textRun.status, 0, textRun.stdout + textRun.stderr);
  const throwingSource = join(work, 'ThrowingPrefixTotal.lean');
  copyFileSync(join(here, 'ThrowingPrefixTotal.lean'), throwingSource);
  const throwingPrefixProof = spawnSync(lean, ['-o', join(work, 'ThrowingPrefixTotal.olean'), throwingSource],
    { cwd: work, env: { ...process.env, LEAN_PATH: work }, encoding: 'utf8' });
  assert.equal(throwingPrefixProof.status, 0, throwingPrefixProof.stderr);
  const reservedRangeSource = join(work, 'ReservedRangeTotal.lean');
  copyFileSync(join(here, 'ReservedRangeTotal.lean'), reservedRangeSource);
  const reservedRangeProof = spawnSync(lean, [reservedRangeSource], growthEnv);
  assert.equal(reservedRangeProof.status, 0, reservedRangeProof.stdout + reservedRangeProof.stderr);
  assert.doesNotMatch(reservedRangeProof.stdout, /sorryAx/,
    'root ADR 0351: the arbitrary-input theorem must not depend on sorry');
  const reservedLabelMutation = model.replace(/(name := "ReservedRange"[^\n]*?)\) "reserved"/,
    '$1) "range_end"');
  assert.notEqual(reservedLabelMutation, model);
  writeFileSync(generated, reservedLabelMutation);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const reservedRefuted = spawnSync(lean, [reservedRangeSource], growthEnv);
  assert.notEqual(reservedRefuted.status, 0,
    'root ADR 0351: changing the generated label must refute the theorem');
  assert.match(reservedRefuted.stdout + reservedRefuted.stderr, /type mismatch|unsolved goals/,
    'the counterexample must refute the theorem rather than fail to load its imports');
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const expressionSource = join(work, 'ExpressionComposition.lean');
  copyFileSync(join(here, 'ExpressionComposition.lean'), expressionSource);
  const expressionProof = spawnSync(lean, ['-o', join(work, 'ExpressionComposition.olean'), expressionSource], growthEnv);
  assert.equal(expressionProof.status, 0, expressionProof.stdout + expressionProof.stderr);
  const argumentGrammarProof = spawnSync(lean, [join(here, 'ArgumentsComposition.lean')], growthEnv);
  assert.equal(argumentGrammarProof.status, 0, argumentGrammarProof.stdout + argumentGrammarProof.stderr);
  const plusCompositionSource = join(work, 'PlusComposition.lean');
  copyFileSync(join(here, 'PlusComposition.lean'), plusCompositionSource);
  const plusCompositionProof = spawnSync(lean, ['-o', join(work, 'PlusComposition.olean'), plusCompositionSource], growthEnv);
  assert.equal(plusCompositionProof.status, 0, plusCompositionProof.stdout + plusCompositionProof.stderr);
  const blockCompositionProof = spawnSync(lean, [join(here, 'BlockComposition.lean')], growthEnv);
  assert.equal(blockCompositionProof.status, 0, blockCompositionProof.stdout + blockCompositionProof.stderr);
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
  console.log(`grammar: source and AST rules ${emittedRuleCount}/${astRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proof modules 29, negative mutations 113, implementation parser cases ${parserCases.length}, syntax-only parser cases 1, native parser counterexamples ${2 + nativeLexicalMutations.length + nativeCompositionMutations.length + nativeExpressionMutations.length + nativeArgumentMutations.length + nativeBlockLeafMutations.length}, rejected parser cases ${rejectedParserCases.length + badDelimiterCases.length + 1 + lexicalRejectedCases.length + compositionRejectedCases.length + expressionRejectedCases.length + argumentRejectedCases.length + blockLeafRejectedCases.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
