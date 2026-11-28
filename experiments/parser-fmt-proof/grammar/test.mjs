import assert from 'node:assert/strict';
import { verifyQuoted } from './verify-quoted.mjs';
import { verifyMixed } from './verify-mixed.mjs';
import { verifyLower } from './verify-lower.mjs';
import { verifyWrapper } from './verify-wrapper.mjs';
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
  assert.ok(!strict.stderr.split('\n').some(line =>
    line.startsWith('unsupported ReservedBracketBody choice ') &&
    line.endsWith(String.raw`'%%' (!'%%' ![\n] .)* '%%'`)),
  'root ADR 0351 I1, I2: the reserved bracket comment branch needs an arbitrary-input proof');
  assert.doesNotMatch(strict.stderr, /^unsupported (BulletList|OrderedList) choice /m,
    'root ADR 0351 I1, I2: list wrappers need arbitrary-input recognition composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (DefList|DefGroup|DefBody) choice /m,
    'root ADR 0351 I1, I2: definition list wrappers require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (Blocks|ItemTail|DivBlocks) choice /m,
    'root ADR 0351 I1, I2: repeated block sequences require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported File choice /m,
    'root ADR 0351 I1, I2: file boundaries require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (CommandBody|GroupBody) choice /m,
    'root ADR 0351 I1, I2: command body dispatch requires arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (ListItem|Div) choice /m,
    'root ADR 0351 I1, I2: list items and fenced blocks require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (SkippedReserved|ReservedBracketBody) choice /m,
    'root ADR 0351 I1, I2: recovery dispatch and nested-body composition require arbitrary-input proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (TableRow|BlockCommand) choice /m,
    'root ADR 0351 I1, I2: inert captures in rows and command alternatives require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported (Table|TableBodyRow) choice /m,
    'root ADR 0351 I1, I2: table headers, captured widths and row guards require arbitrary-input composition proofs');
  assert.doesNotMatch(strict.stderr, /^unsupported BlockGroup choice /m,
    'root ADR 0351 I1, I2: command groups require captured Boolean values and the last-command guard');
  assert.ok(baselineUnsupported === 0, 'the full grammar model must not regress in unsupported choices');
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
    ['= first\n  one\n= second\n  two\n', 'DefList', { DefList: 1, DefGroup: 2, DefBody: 2 }],
    ['= first\n  one\n\n= second\n  two\n', 'DefList', { DefList: 1, DefGroup: 2, DefBody: 2 }],
    ['= term\n  one\n=:\n  two\n', 'DefList', { DefGroup: 1, DefBody: 2 }],
    ['= term\n  one\n\n=:\n  two\n', 'DefList', { DefGroup: 1, DefBody: 2 }],
    ['- lead\n  = term\n    鰍𠮷\n', 'BulletList', { DefList: 1, DefGroup: 1, DefBody: 1 }],
    ['```\n```\n', 'CodeBlock', { CodeBlock: 1, CodeLine: 0 }],
    ['```hs key=x\nbody\n```\n', 'CodeBlock', { CodeBlock: 1, CodeLine: 1 }],
    ['- x\n  ```\n  body\n  ```\n', 'BulletList', { CodeBlock: 1, CodeLine: 1 }],
  ];
  const listItemParserCases = [
    ['- lead\n', 'BulletList', { ListItem: 1 }],
    ['+ lead\n', 'OrderedList', { ListItem: 1 }],
    ['- one\n  more\n', 'BulletList', { ListItem: 1, Paragraph: 0 }],
    ['+ one\n\n  more\n\nout\n', 'OrderedList', { ListItem: 1, Paragraph: 2 }],
    ['- 鰍𠮷\n\n- กำ\n', 'BulletList', { ListItem: 2 }],
    ['- a', 'BulletList', { ListItem: 1 }],
    ['+ a', 'OrderedList', { ListItem: 1 }],
    ['- one\n  # title\n', 'BulletList', { ListItem: 1, Heading: 1 }],
    ['-a\n', 'Paragraph', { ListItem: 0 }],
  ];
  const divParserCases = [
    ['@style body align=center\n:::\n:::\n', { Div: 1, DivMark: 2, Paragraph: 0 }],
    ['@style body align=center\n:::\none\n:::', { Div: 1, DivMark: 2, Paragraph: 1 }],
    ['@style body align=center\n:::\n- lead\n\none\n:::\n', { Div: 1, DivMark: 2, ListItem: 1, Paragraph: 1 }],
    ['@style body align=center\n:::\n@style body align=center\none\n:::\n', { Div: 1, DivMark: 2, GroupBody: 2 }],
    ['@style body align=center\n:::\n鰍𠮷\n\nกำ\n:::\n', { Div: 1, DivMark: 2, Paragraph: 2 }],
    ['@style body align=center\n:::\none\n\n\n:::\n\nout\n', { Div: 1, DivMark: 2, Paragraph: 2 }],
    ['- lead\n  @style body align=center\n  :::\n  one\n  :::\n', { Div: 1, DivMark: 2, ListItem: 1 }],
  ];
  const unclosedFenceSyntax = '@style body align=center\n:::\none\n';
  const emptyItemRejectedCases = ['- \n', '+ \n'];
  const groupBodyParserCases = [
    ['@style body align=center\none\n', { GroupBody: 1, Paragraph: 1, Div: 0 }],
    ['@style body align=center\n# Title\n', { GroupBody: 1, Heading: 1, Paragraph: 0 }],
    ['@style body align=center\n- lead\n', { GroupBody: 1, BulletList: 1 }],
    ['@style body align=center\n:::\n:::\n', { GroupBody: 1, Div: 1, Paragraph: 0 }],
    ['@style body align=center\n:::\none\n\ntwo\n\n:::\nout\n', { GroupBody: 1, Div: 1, Paragraph: 3 }],
    ['@style body align=center\n@style body align=center\none\n', { GroupBody: 1, Paragraph: 1 }],
    ['@style body align=center\n::x\n', { GroupBody: 1, Paragraph: 1, Div: 0 }],
  ];
  // A single indented block remains a valid body (root ADR 0473).
  const singleIndentedBody = '@style body align=center\n  one\n';
  // Multiple indented blocks remain recognizable only for G02290 diagnostics.
  const legacyBodyParserCases = [
    ['@style body align=center\n  one\n\n  two\n', { CommandBody: 1, GroupBody: 0, Paragraph: 2 }],
  ];
  const fileParserCases = [
    ['', undefined, {}], ['\n\n', undefined, {}],
    ['one\n', 'Paragraph', { Paragraph: 1 }],
    ['\n\none\n\n', 'Paragraph', { Paragraph: 1 }],
    ['one\n\ntwo\n\n', 'Paragraph', { Paragraph: 2 }],
    ['\n鰍𠮷\n\nกำ\n\n', 'Paragraph', { Paragraph: 2 }],
  ];
  const blockSequenceParserCases = [
    ['one\n\ntwo\n\nthree\n', 'Paragraph', { Paragraph: 3 }],
    ['- lead\n', 'BulletList', { BulletList: 1, ListItem: 1, Paragraph: 0 }],
    ['- lead\n  # heading\n', 'BulletList', { BulletList: 1, Heading: 1 }],
    ['- lead\n\n  鰍𠮷\n\n  กำ\n\nout\n', 'BulletList', { BulletList: 1, Paragraph: 3 }],
    ['@style body align=center\n:::\n:::\n', 'Div', { DivBlocks: 1, DivMark: 2, Paragraph: 0 }],
    ['@style body align=center\n:::\none\n\ntwo\n\n:::\nout\n', 'Div', { DivBlocks: 1, DivMark: 2, Paragraph: 3 }],
  ];
  const listParserCases = [
    ['- a\n', 'BulletList', { BulletList: 1, ListItem: 1 }],
    ['- 鰍\n\n- 𠮷\n- กำ\n', 'BulletList', { BulletList: 1, ListItem: 3 }],
    ['+ a\n', 'OrderedList', { OrderedList: 1, ListItem: 1 }],
    ['+ 鰍\n\n+ 𠮷\n+ กำ\n', 'OrderedList', { OrderedList: 1, ListItem: 3 }],
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
    ...listItemParserCases.map(([sample, node, counts]) => [sample, node, 0, undefined, undefined, counts]),
    ...divParserCases.map(([sample, counts]) => [sample, 'Div', 0, undefined, undefined, counts]),
    [singleIndentedBody, 'CommandBody', 0, undefined, undefined, { GroupBody: 0, Paragraph: 1 }],
    ...groupBodyParserCases.map(([sample, counts]) => [sample, 'GroupBody', 0, undefined, undefined, counts]),
    ...fileParserCases.map(([sample, node, counts]) => [sample, node, 0, undefined, undefined, counts]),
    ...blockSequenceParserCases.map(([sample, node, counts]) => [sample, node, 0, undefined, undefined, counts]),
    ...listParserCases.map(([body, node, counts]) => [body, node, 0, undefined, undefined, counts]),
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
  for (const [sample, counts] of legacyBodyParserCases) {
    const input = join(work, 'legacy-body.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', source, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^File@0\\.\\.${Buffer.byteLength(sample)}$`, 'm'));
    for (const [kind, count] of Object.entries(counts)) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +(?:[a-z]+: )?${kind}@`, 'gm'))].length, count);
    }
  }
  // The grammar keeps an unclosed Div for G01030; this is not a valid CLI manuscript.
  const unclosedFenceInput = join(work, 'unclosed-fence.gm');
  writeFileSync(unclosedFenceInput, unclosedFenceSyntax);
  const unclosedFence = spawnSync(process.env.PEG_HS ?? 'peg-hs',
    ['parse', '--format', 'cst', source, unclosedFenceInput],
    { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
  assert.equal(unclosedFence.status, 0, unclosedFence.stderr);
  assert.match(unclosedFence.stdout, new RegExp(`^File@0\.\.${Buffer.byteLength(unclosedFenceSyntax)}$`, 'm'));
  assert.equal([...unclosedFence.stdout.matchAll(/^ +Div@/gm)].length, 1);
  assert.equal([...unclosedFence.stdout.matchAll(/^ +DivMark@/gm)].length, 1);
  for (const sample of emptyItemRejectedCases) {
    const input = join(work, 'empty-item.gm');
    writeFileSync(input, sample);
    const rejected = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', source, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /^\d+:\d+: expected /m);
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
  const listItemShape = 'ListItem <- Ind(ind) ListMark(ordered) Ws Inline(col ind + 2)+ (Nl / !.) ItemTail(col ind + 2)';
  const divShape = 'Div <- Ind(ind) DivMark Sp (Nl / !.) DivBlocks(fenced ind) (BlankLines? Ind(ind) DivMark Sp (Nl / !.))?';
  const blockRemainderMutations = [
    ['InlineStar', 'ListItem', listItemShape, listItemShape.replace('Inline(col ind + 2)+', 'Inline(col ind + 2)*')],
    ['OptionalSpace', 'ListItem', listItemShape, listItemShape.replace(' Ws ', ' Sp ')],
    ['WrongOrder', 'ListItem', listItemShape, listItemShape.replace('ListMark(ordered)', 'ListMark(0)')],
    ['InlineIndent', 'ListItem', listItemShape, listItemShape.replace('Inline(col ind + 2)', 'Inline(col ind + 3)')],
    ['ItemNewline', 'ListItem', listItemShape, listItemShape.replace('(Nl / !.)', 'Nl')],
    ['TailIndent', 'ListItem', listItemShape, listItemShape.replace('ItemTail(col ind + 2)', 'ItemTail(ind)')],
    ['DivOpenIndent', 'Div', divShape, divShape.replace('Ind(ind)', 'Ind(col ind + 1)')],
    ['DivCloseRequired', 'Div', divShape, divShape.slice(0, -1)],
    ['DivNewline', 'Div', divShape, divShape.replaceAll('(Nl / !.)', 'Nl')],
    ['DivCloseIndent', 'Div', divShape, divShape.replace('BlankLines? Ind(ind)', 'BlankLines? Ind(col ind + 1)')],
    ['DivBodyScope', 'Div', divShape, divShape.replace('DivBlocks(fenced ind)', 'DivBlocks(ind)')],
    ['DivOpenMark', 'Div', divShape, divShape.replace('DivMark', 'DivLine')],
  ];
  for (const [name, rule, before, after] of blockRemainderMutations) {
    assert.ok(original.includes(before));
    assert.notEqual(before, after);
    const grammar = join(work, name + '.hpeg');
    writeFileSync(grammar, original.replace(before, after));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1, I2: ${name} must invalidate the complete item/fence composition`);
  }
  const nativeBlockRemainderMutations = [
    ['InlineStar', '- \n', true, { BulletList: 1, ListItem: 1 }],
    ['OptionalSpace', '-a\n', true, { BulletList: 1, ListItem: 1, Paragraph: 0 }],
    ['WrongOrder', '+ lead\n', false],
    ['ItemNewline', '- a', false],
    ['DivOpenIndent', divParserCases[1][0], true, { Div: 0, DivMark: 0 }],
    ['DivCloseRequired', unclosedFenceSyntax, true, { Div: 0, DivMark: 0 }],
    ['DivNewline', divParserCases[1][0], true, { Div: 1, DivMark: 1, Paragraph: 2 }],
    ['DivCloseIndent', divParserCases[5][0], true, { Div: 1, DivMark: 1, Paragraph: 3 }],
  ];
  for (const [name, sample, accepted, counts] of nativeBlockRemainderMutations) {
    const [, , before, after] = blockRemainderMutations.find(([key]) => key === name);
    const grammar = join(work, 'Native' + name + '.hpeg');
    const input = join(work, 'native-block-remainder.gm');
    writeFileSync(grammar, original.replace(before, after));
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, `root ADR 0351 I1, I2: ${name}: ${parsed.stderr}`);
    if (!accepted) assert.match(parsed.stderr, /^\d+:\d+: expected /m);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count);
    }
  }
  const commandShape = String.raw`CommandBody <- &(Ind(col ind + 2) ![ \t] !BlankLine .) Blocks(col ind + 2)`;
  const groupShape = String.raw`GroupBody <- Div(ind) { () }
           / &(Ind(ind) !BlockCommandStart ![ \t] !BlankLine) AttributedBlock(ind) { () }`;
  const reversedGroup = String.raw`GroupBody <- &(Ind(ind) !BlockCommandStart ![ \t] !BlankLine) AttributedBlock(ind) { () }
           / Div(ind) { () }`;
  const bodyDispatchMutations = [
    ['CommandGuard', 'CommandBody', commandShape, commandShape.replace('&(', '!(')],
    ['CommandIndent', 'CommandBody', commandShape, commandShape.replaceAll('col ind + 2', 'col ind + 3')],
    ['CommandSingle', 'CommandBody', commandShape, commandShape.replace('Blocks(col ind + 2)', 'Block(col ind + 2)')],
    ['CommandSpace', 'CommandBody', commandShape, commandShape.replace(String.raw`![ \t] `, '')],
    ['CommandBlank', 'CommandBody', commandShape, commandShape.replace('!BlankLine ', '')],
    ['GroupOrder', 'GroupBody', groupShape, reversedGroup],
    ['GroupGuard', 'GroupBody', groupShape, groupShape.replace('!BlockCommandStart', '&BlockCommandStart')],
    ['GroupIndent', 'GroupBody', groupShape, groupShape.replace('Ind(ind)', 'Ind(col ind + 1)')],
    ['GroupAttributed', 'GroupBody', groupShape, groupShape.replace('AttributedBlock(ind)', 'AttributedBlock(col ind + 1)')],
    ['GroupFenced', 'GroupBody', groupShape, groupShape.replace('Div(ind)', 'Div(col ind + 1)')],
  ];
  for (const [name, rule, before, after] of bodyDispatchMutations) {
    assert.ok(original.includes(before));
    assert.notEqual(before, after);
    const grammar = join(work, name + '.hpeg');
    writeFileSync(grammar, original.replace(before, after));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1, I2: ${name} must invalidate the exact body-dispatch composition`);
  }
  const nativeBodyDispatchMutations = [
    ['CommandGuard', legacyBodyParserCases[0][0], false],
    ['CommandSingle', legacyBodyParserCases[0][0], false],
    ['GroupOrder', groupBodyParserCases[4][0], true, { GroupBody: 1, Div: 0, Paragraph: 3 }],
    ['GroupGuard', groupBodyParserCases[0][0], true, { GroupBody: 0, Paragraph: 1 }],
    ['GroupAttributed', groupBodyParserCases[0][0], true, { GroupBody: 0, Paragraph: 1 }],
    ['GroupFenced', groupBodyParserCases[4][0], true, { GroupBody: 1, Div: 0, Paragraph: 3 }],
  ];
  for (const [name, sample, accepted, counts] of nativeBodyDispatchMutations) {
    const [, , before, after] = bodyDispatchMutations.find(([key]) => key === name);
    const grammar = join(work, 'Native' + name + '.hpeg');
    const input = join(work, 'native-body-dispatch.gm');
    writeFileSync(grammar, original.replace(before, after));
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, `root ADR 0351 I1, I2: ${name}: ${parsed.stderr}`);
    if (!accepted) assert.match(parsed.stderr, /^\d+:\d+: expected /m);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +(?:[a-z]+: )?${kind}@`, 'gm'))].length, count);
    }
  }
  const fileShape = 'File <- BlankLines? (&. Blocks(0) BlankLines?)?';
  const fileMutations = [
    ['LeadingRequired', fileShape.replace('BlankLines?', 'BlankLines')],
    ['BodyRequired', fileShape.replace('BlankLines?)?', 'BlankLines?)')],
    ['GuardReverse', fileShape.replace('&.', '!.')],
    ['IndentChanged', fileShape.replace('Blocks(0)', 'Blocks(1)')],
    ['TrailingRequired', fileShape.replace('Blocks(0) BlankLines?', 'Blocks(0) BlankLines')],
  ];
  for (const [name, changed] of fileMutations) {
    assert.ok(original.includes(fileShape));
    assert.notEqual(fileShape, changed);
    const grammar = join(work, 'File' + name + '.hpeg');
    writeFileSync(grammar, original.replace(fileShape, changed));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, /^unsupported File choice /m,
      `root ADR 0351 I1, I2: ${name} must invalidate the complete File composition`);
  }
  const nativeFileMutations = [
    ['LeadingRequired', 'one\n'], ['BodyRequired', ''],
    ['GuardReverse', 'one\n'], ['TrailingRequired', 'one\n'],
  ];
  for (const [name, sample] of nativeFileMutations) {
    const [, changed] = fileMutations.find(([key]) => key === name);
    const grammar = join(work, 'NativeFile' + name + '.hpeg');
    const input = join(work, 'native-file.gm');
    writeFileSync(grammar, original.replace(fileShape, changed));
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0, `root ADR 0351 I1, I2: File${name} must reject its boundary input`);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }
  const blockSequenceShapes = [
    ['Blocks', 'Block(ind) (BlankLines? &(Ind(ind) !BlankLine .) Block(ind))*'],
    ['ItemTail', '(BlankLines? &(Ind(ind) ![ \\t] !BlankLine .) Block(ind))*'],
    ['DivBlocks', '(BlankLines? !(Ind(ind) DivLine) &(Ind(ind) ![ \\t] !BlankLine .) Block(ind))*'],
  ];
  const blockSequenceMutations = [];
  for (const [rule, shape] of blockSequenceShapes) {
    const before = `${rule} <- ${shape}`;
    const changes = [
      ['NeedsMore', shape.replace(')*', ')+')],
      ['BlankRequired', shape.replace('BlankLines?', 'BlankLines')],
      ['Guard', rule === 'DivBlocks' ? shape.replace('!(Ind(ind) DivLine) ', '') : shape.replace('&(', '!(')],
      ['Reference', rule === 'Blocks' ? shape.replace('Block(ind)', 'Paragraph(ind)') : shape.replace('Ind(ind)', 'Ind(col ind + 1)')],
    ];
    for (const [name, changed] of changes) {
      const after = `${rule} <- ${changed}`;
      assert.ok(original.includes(before));
      assert.notEqual(before, after);
      const grammar = join(work, rule + name + '.hpeg');
      writeFileSync(grammar, original.replace(before, after));
      const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
      assert.notEqual(rejected.status, 0);
      assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
        `root ADR 0351 I1, I2: ${rule + name} must invalidate the guarded repetition proof`);
      blockSequenceMutations.push([rule + name, before, after]);
    }
  }
  const nativeBlockSequenceMutations = [
    ['BlocksNeedsMore', 'one\n', false],
    ['ItemTailNeedsMore', '- lead\n', false],
    ['DivBlocksNeedsMore', '@style body align=center\n:::\n:::\n', true, { DivBlocks: 0, DivMark: 0 }],
    ['DivBlocksGuard', '@style body align=center\n:::\none\n:::\nout\n', true, { DivMark: 1 }],
  ];
  for (const [name, sample, accepted, counts] of nativeBlockSequenceMutations) {
    const [, before, after] = blockSequenceMutations.find(([key]) => key === name);
    const grammar = join(work, 'Native' + name + '.hpeg');
    const input = join(work, 'native-block-sequence.gm');
    writeFileSync(grammar, original.replace(before, after));
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, `root ADR 0351 I1, I2: ${name}: ${parsed.stderr}`);
    if (!accepted) assert.match(parsed.stderr, /^\d+:\d+: expected /m);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count);
    }
  }
  // Expose only CST presentation metadata for the inline helpers. The
  // committed rule bodies and recognition order remain byte-identical.
  const tracedGrammar = join(work, 'TracedBlockSequences.hpeg');
  const tracedSource = original.replace(/^%inline (?:Blocks|ItemTail)\n/gm, '');
  assert.notEqual(tracedSource, original);
  writeFileSync(tracedGrammar, tracedSource);
  function flattenBlockSequenceTrace(cst) {
    const removed = [];
    return cst.trimEnd().split('\n').flatMap(line => {
      const indent = line.match(/^ */)[0].length;
      while (removed.length && removed.at(-1) >= indent) removed.pop();
      if (/^ +(?:Blocks|ItemTail)@/.test(line)) { removed.push(indent); return []; }
      return [line.slice(removed.length * 2)];
    }).join('\n') + '\n';
  }
  for (const [sample] of blockSequenceParserCases) {
    const input = join(work, 'trace-block-sequence.gm');
    writeFileSync(input, sample);
    const opts = { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } };
    const ordinary = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', source, input], opts);
    const traced = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', tracedGrammar, input], opts);
    assert.equal(ordinary.status, 0, ordinary.stderr);
    assert.equal(traced.status, 0, traced.stderr);
    assert.match(traced.stdout, /^ +Blocks@/m);
    if (sample.startsWith('-')) assert.match(traced.stdout, /^ +ItemTail@/m);
    assert.equal(flattenBlockSequenceTrace(traced.stdout), ordinary.stdout,
      'root ADR 0351 I1, I2: exposing inline CST helpers must preserve their children and input ranges');
  }
  const listMutations = [];
  for (const [rule, ordered] of [['BulletList', '0'], ['OrderedList', '1']]) {
    const canonical = `${rule} <- ListItem(ind, ${ordered}) (BlankLines? ListItem(ind, ${ordered}))*`;
    listMutations.push(
      [`${rule}NeedsMore`, canonical, canonical.replace(')*', ')+'), rule],
      [`${rule}BlankRequired`, canonical, canonical.replace('BlankLines?', 'BlankLines'), rule],
      [`${rule}FirstKind`, canonical, canonical.replace(`ListItem(ind, ${ordered})`, `ListItem(ind, ${ordered === '0' ? '1' : '0'})`), rule],
      [`${rule}RepeatedKind`, canonical, canonical.replace(`(BlankLines? ListItem(ind, ${ordered}))`, `(BlankLines? ListItem(ind, ${ordered === '0' ? '1' : '0'}))`), rule],
    );
  }
  for (const [name, before, after, rule] of listMutations) {
    assert.ok(original.includes(before));
    assert.notEqual(before, after);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, original.replace(before, after));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
      `root ADR 0351 I1, I2: ${name} must return the actual list wrapper to deferred choices`);
  }
  const nativeListMutations = [
    ['BulletListNeedsMore', '- a\n', false],
    ['OrderedListNeedsMore', '+ a\n', false],
    ['BulletListBlankRequired', '- a\n- b\n', true, { BulletList: 2 }],
    ['OrderedListBlankRequired', '+ a\n+ b\n', true, { OrderedList: 2 }],
  ];
  for (const [name, sample, accepted, counts] of nativeListMutations) {
    const [, before, after] = listMutations.find(([mutationName]) => mutationName === name);
    const changedPath = join(work, 'Native' + name + '.hpeg');
    const samplePath = join(work, 'native-list.gm');
    writeFileSync(changedPath, original.replace(before, after));
    writeFileSync(samplePath, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', changedPath, samplePath],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, `root ADR 0351 I1, I2: ${name}: ${parsed.stderr}`);
    if (!accepted) assert.match(parsed.stderr, /^\d+:\d+: expected /m);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count);
    }
  }
  const definitionShapes = [
    ['DefList', "DefGroup(ind) (BlankLines? &(Ind(ind) '=' [ \\t]) DefGroup(ind))*"],
    ['DefGroup', 'DefTerm(ind)+ DefBody(ind) (BlankLines? DefNew(ind) DefBody(ind))*'],
    ['DefBody', '&(Ind(col ind + 2) ![ \\t] !BlankLine .) Block(col ind + 2) (BlankLines? &(Ind(col ind + 2) ![ \\t] !BlankLine .) Block(col ind + 2))*'],
  ];
  const definitionMutations = [];
  for (const [rule, shape] of definitionShapes) {
    const before = `${rule} <- ${shape}`;
    const changes = rule === 'DefList' ? [
      ['NeedsMore', shape.replace(')*', ')+')],
      ['BlankRequired', shape.replace('BlankLines?', 'BlankLines')],
      ['GuardNegative', shape.replace('&(', '!(')],
      ['FirstGroup', shape.replace('DefGroup(ind)', 'DefTerm(ind)')],
    ] : rule === 'DefGroup' ? [
      ['TermsOptional', shape.replace('DefTerm(ind)+', 'DefTerm(ind)*')],
      ['NeedsMore', shape.replace(')*', ')+')],
      ['NewMarker', shape.replace('DefNew(ind)', 'NewDefMark')],
      ['FirstBody', shape.replace('DefBody(ind)', 'Block(ind)')],
    ] : [
      ['NeedsMore', shape.replace(')*', ')+')],
      ['GuardNegative', shape.replace('&(', '!(')],
      ['IndentMismatch', shape.replace('col ind + 2', 'col ind + 1')],
      ['RepeatedBlock', shape.replace(/Block\(col ind \+ 2\)\)\*$/, 'Paragraph(col ind + 2))*')],
    ];
    for (const [name, changedShape] of changes) {
      const after = `${rule} <- ${changedShape}`;
      assert.ok(original.includes(before));
      assert.notEqual(before, after);
      const path = join(work, rule + name + '.hpeg');
      writeFileSync(path, original.replace(before, after));
      const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), path, generated], { encoding: 'utf8' });
      assert.notEqual(rejected.status, 0);
      assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'),
        `root ADR 0351 I1, I2: ${rule + name} must invalidate the canonical composition proof`);
      definitionMutations.push([rule + name, before, after]);
    }
  }
  const nativeDefinitionMutations = [
    ['DefListNeedsMore', '= term\n  body\n', false],
    ['DefListBlankRequired', '= first\n  one\n= second\n  two\n', true, { DefList: 2 }],
    ['DefGroupFirstBody', '= term\n  body\n', false],
    ['DefBodyGuardNegative', '= term\n  body\n', false],
  ];
  for (const [name, sample, accepted, counts] of nativeDefinitionMutations) {
    const [, before, after] = definitionMutations.find(([key]) => key === name);
    const grammar = join(work, 'Native' + name + '.hpeg');
    const input = join(work, 'native-definition.gm');
    writeFileSync(grammar, original.replace(before, after));
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, `root ADR 0351 I1, I2: ${name}: ${parsed.stderr}`);
    if (!accepted) assert.match(parsed.stderr, /^\d+:\d+: expected /m);
    for (const [kind, count] of Object.entries(counts ?? {})) {
      assert.equal([...parsed.stdout.matchAll(new RegExp(`^ +${kind}@`, 'gm'))].length, count);
    }
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

  const reservedComment = String.raw`'%%' (!'%%' ![\n] .)* '%%'`;
  assert.ok(original.includes(reservedComment));
  const reservedCommentMutations = [
    ['ReservedCommentOpening', reservedComment.replace(/^'%%'/, "'%'")],
    ['ReservedCommentGuard', reservedComment.replace("!'%%'", "&'%%'")],
    ['ReservedCommentNewline', reservedComment.replace(String.raw`![\n]`, String.raw`[\n]`)],
    ['ReservedCommentRepetition', reservedComment.replace(')*', ')+')],
    ['ReservedCommentClosing', reservedComment.replace(/'%%'$/, "'%'")],
    ['ReservedCommentCharacter', reservedComment.replace(' .)', " 'x')")],
  ];
  for (const [name, changedBranch] of reservedCommentMutations) {
    assert.notEqual(changedBranch, reservedComment);
    const changedPath = join(work, name + '.hpeg');
    writeFileSync(changedPath, original.replace(reservedComment, changedBranch));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), changedPath, generated], { encoding: 'utf8' });
    assert.notEqual(rejected.status, 0);
    assert.ok(rejected.stderr.split('\n').some(line =>
      line.startsWith('unsupported ReservedBracketBody choice ') && line.endsWith(changedBranch)),
    `root ADR 0351 I1/I2: ${name} must invalidate the complete comment branch proof`);
  }
  // Expose the actual existing rule, without replacing it with a handwritten
  // recovery grammar. These are entry-rule CST checks, not valid manuscripts.
  const nativeBodyGrammar = original.replace('%syntax\n', '%syntax\n%entry ReservedBracketBody\n%entry SkippedReserved\n');
  assert.notEqual(nativeBodyGrammar, original);
  const nativeBodyPath = join(work, 'NativeReservedBody.hpeg');
  writeFileSync(nativeBodyPath, nativeBodyGrammar);
  const nativeBodySamples = ['%%%%', '%%]text%%', '%%]字%%'];
  for (const sample of nativeBodySamples) {
    const input = join(work, 'native-reserved-body.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--entry', 'ReservedBracketBody', '--format', 'cst', nativeBodyPath, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stdout + parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^ReservedBracketBody@0\\.\\.${Buffer.byteLength(sample)}$`, 'm'));
  }
  const nativeBodyMutated = join(work, 'NativeReservedBodyMutated.hpeg');
  writeFileSync(nativeBodyMutated, nativeBodyGrammar.replace(reservedComment,
    reservedComment.replace("!'%%'", "&'%%'")));
  const nativeBodyCounterexample = join(work, 'native-reserved-body-counterexample.gm');
  writeFileSync(nativeBodyCounterexample, '%%]text%%');
  const nativeBodyRejected = spawnSync(process.env.PEG_HS ?? 'peg-hs',
    ['parse', '--entry', 'ReservedBracketBody', '--format', 'cst', nativeBodyMutated, nativeBodyCounterexample],
    { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
  assert.notEqual(nativeBodyRejected.status, 0,
    'root ADR 0351: reversing the comment guard must reject the complete recovered body with an internal closing bracket');
  assert.match(nativeBodyRejected.stdout + nativeBodyRejected.stderr, /^1:3: expected /m,
    'the native counterexample must fail at the internal bracket, not while compiling the parser');

  // Both entries expose committed recovery rules, not replacement grammars.
  // Expected suffixes are model fixtures; entry success additionally needs EOF.
  const recoveryFixtures = [
    ['[!a]', ''], ['[!a[b]c]', ''], ['[!%%]text%%]', ''], ['[!鰍𠮷]', ''],
    [String.raw`[!\]x]`, ''], ['[!]', ''], ['[!', ''], ['@!', ''], ['@!abc', ''], ['@!กำ', ''], ['..', ''],
    ['', null], ['@!a\n', '\n'], ['[!abc', 'abc'], ['...', '.'],
  ];
  const nestedBodyCases = [
    ['', 1], ['abc', 1], ['a[b]c', 2], ['[a[b]c]d', 3],
    ['%%]text%%', 1], [String.raw`\]x`, 1], ['鰍𠮷[กำ]', 2],
  ];
  const bodyEntryRejectedCases = ['\n', ']', '['];
  for (const [sample, suffix] of recoveryFixtures) {
    const input = join(work, 'recovery-entry.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--entry', 'SkippedReserved', '--format', 'cst', nativeBodyPath, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, suffix === '', parsed.stdout + parsed.stderr);
    if (suffix === '') assert.match(parsed.stdout, new RegExp(`^SkippedReserved@0\\.\\.${Buffer.byteLength(sample)}$`, 'm'));
    else assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }
  for (const [sample, count] of nestedBodyCases) {
    const input = join(work, 'nested-body.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--entry', 'ReservedBracketBody', '--format', 'cst', nativeBodyPath, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status, 0, parsed.stderr);
    assert.match(parsed.stdout, new RegExp(`^ReservedBracketBody@0\\.\\.${Buffer.byteLength(sample)}$`, 'm'));
    assert.equal([...parsed.stdout.matchAll(/^(?: +)?ReservedBracketBody@/gm)].length, count);
  }
  for (const sample of bodyEntryRejectedCases) {
    const input = join(work, 'rejected-body-entry.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs',
      ['parse', '--entry', 'ReservedBracketBody', '--format', 'cst', nativeBodyPath, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(parsed.status, 0);
    assert.match(parsed.stderr, /^\d+:\d+: expected /m);
  }
  const recoveryShape = String.raw`SkippedReserved <- '[!' ReservedBracketBody ']' { () }
                 / '[!' { () }
                 / '@!' (![\n] .)* { () }
                 / '..' { () }`;
  const recoveryReversed = String.raw`SkippedReserved <- '[!' { () }
                 / '[!' ReservedBracketBody ']' { () }
                 / '@!' (![\n] .)* { () }
                 / '..' { () }`;
  const recoveryMutations = [
    ['RecoveryOpen', recoveryShape.replace("'[!' Reserved", "'[?' Reserved"), '[!a]'],
    ['RecoveryClose', recoveryShape.replace("ReservedBracketBody ']'", "ReservedBracketBody '}'"), '[!a]'],
    ['RecoveryPrefix', recoveryShape.replace("\n                 / '[!' { () }", ''), '[!'],
    ['RecoveryOrder', recoveryReversed, '[!a]'],
    ['RecoveryLinePlus', recoveryShape.replace(')*', ')+'), '@!'],
    ['RecoveryLineGuard', recoveryShape.replace(String.raw`![\n]`, String.raw`&[\n]`), '@!abc'],
    ['RecoveryLineChar', recoveryShape.replace(String.raw`![\n] .`, String.raw`![\n] 'X'`), '@!abc'],
    ['RecoveryRange', recoveryShape.replace("/ '..'", "/ '...'"), '..'],
  ];
  const bodyShape = original.slice(original.indexOf('ReservedBracketBody <-'));
  assert.ok(bodyShape.startsWith('ReservedBracketBody <-'));
  const reorderedBodyLines = bodyShape.split('\n');
  const commentIndex = reorderedBodyLines.findIndex(line => line.includes("/ '%%'"));
  const plainIndex = reorderedBodyLines.findIndex(line => line.includes(String.raw`/ ![\[\]\\\n]`));
  assert.ok(commentIndex >= 0 && plainIndex >= 0);
  [reorderedBodyLines[commentIndex], reorderedBodyLines[plainIndex]] = [reorderedBodyLines[plainIndex], reorderedBodyLines[commentIndex]];
  const bodyCompositionMutations = [
    ['BodyPlus', bodyShape.replace(')* { () }', ')+ { () }'), ''],
    ['BodyEscape', bodyShape.replace(String.raw`'\\' ![\n] .`, String.raw`'\\' &[\n] .`), String.raw`\a`],
    ['BodyOpen', bodyShape.replace("'[' ReservedBracketBody", "'{' ReservedBracketBody"), '[a]'],
    ['BodyClose', bodyShape.replace("ReservedBracketBody ']'", "ReservedBracketBody '}'"), '[a]'],
    ['BodyReference', bodyShape.replace("'[' ReservedBracketBody ']'", "'[' Word ']'"), '[a[b]]'],
    ['BodyPlainGuard', bodyShape.replace(String.raw`![\[\]\\\n]`, String.raw`&[\[\]\\\n]`), 'abc'],
    ['BodyPlainChar', bodyShape.replace(String.raw`![\[\]\\\n] .`, String.raw`![\[\]\\\n] 'X'`), 'abc'],
    ['BodyOrder', reorderedBodyLines.join('\n'), '%%]text%%'],
  ];
  for (const [rule, before, mutations] of [
    ['SkippedReserved', recoveryShape, recoveryMutations],
    ['ReservedBracketBody', bodyShape, bodyCompositionMutations],
  ]) {
    for (const [name, after, sample] of mutations) {
      assert.ok(original.includes(before));
      assert.notEqual(before, after);
      const grammar = join(work, name + '.hpeg');
      writeFileSync(grammar, original.replace(before, after));
      const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
      assert.notEqual(rejected.status, 0);
      assert.match(rejected.stderr, new RegExp(`^unsupported ${rule} choice `, 'm'));
      writeFileSync(grammar, nativeBodyGrammar.replace(before, after));
      const input = join(work, 'native-recovery-counterexample.gm');
      writeFileSync(input, sample);
      const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', rule, '--format', 'cst', grammar, input],
        { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
      assert.notEqual(parsed.status, 0, `root ADR 0351: ${name} must reject its native entry counterexample`);
      assert.match(parsed.stderr, /^\d+:\d+: expected /m,
        'recovery mutation must fail on input, not while compiling its grammar');
    }
  }
  const recoveryModelCases = [
    ...recoveryFixtures.map(([sample, suffix]) => ['SkippedReserved', sample, suffix]),
    ...nestedBodyCases.map(([sample]) => ['ReservedBracketBody', sample, '']),
    ...bodyEntryRejectedCases.map(sample => ['ReservedBracketBody', sample, sample]),
  ];
  // Expose the actual parameterized rule through argument-only entry wrappers.
  // Native AST output observes the existing length-cs action independently.
  const tableRowEntryGrammar = original.replace('%syntax\n', '%syntax\n%entry RowZeroProbe\n%entry RowTwoProbe\n') +
    '\nRowZeroProbe :: Int\nRowZeroProbe <- n:TableRow(0) { n }\nRowTwoProbe :: Int\nRowTwoProbe <- n:TableRow(2) { n }\n';
  const tableRowEntryPath = join(work, 'TableRowEntry.hpeg');
  writeFileSync(tableRowEntryPath, tableRowEntryGrammar);
  const tableRowCases = [
    ['|a|', 0, 1, ''], ['|a|b|', 0, 2, ''], ['||', 0, 1, ''],
    ['| a | b | c |', 0, 3, ''], ['|鰍𠮷|กำ|', 0, 2, ''], ['|a|  ', 0, 1, ''],
    ['  |a|b|', 2, 2, ''], ['|a|\n', 0, null, '\n'], ['|a', 0, null, null],
    ['|a|\\', 0, null, 'label: hard_break'], ['', 0, null, null],
  ];
  for (const [sample, ind, count] of tableRowCases) {
    const input = join(work, 'table-row-entry.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', ind === 2 ? 'RowTwoProbe' : 'RowZeroProbe',
      '--format', 'ast', tableRowEntryPath, input], { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    if (count === null) {
      assert.notEqual(parsed.status, 0, sample + parsed.stdout);
      assert.match(parsed.stderr + parsed.stdout, /^\d+:\d+: expected/m);
    } else {
      assert.equal(parsed.status, 0, sample + parsed.stderr);
      assert.equal(parsed.stdout.trim(), String(count), 'the native length-cs action retains the number of cells');
    }
  }
  const tableRowShape = 'TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Sp RowBreak? { length cs }';
  assert.ok(original.includes(tableRowShape));
  const tableRowMutations = [
    ['AllowEmpty', 'TableRow <- Ind(ind) cs:TableCellAndPipe* Pipe Sp RowBreak? { length cs }', '|', '0'],
    ['Indent', 'TableRow <- Ind(ind + 1) cs:TableCellAndPipe+ Pipe Sp RowBreak? { length cs }', '|a|', null],
    ['Cells', 'TableRow <- Ind(ind) cs:(TableCellAndPipe / Pipe)+ Pipe Sp RowBreak? { length cs }', '|a|', null],
    ['Closing', 'TableRow <- Ind(ind) cs:TableCellAndPipe+ Ws Sp RowBreak? { length cs }', '|a|', null],
    ['Space', 'TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Ws RowBreak? { length cs }', '|a|', null],
    ['Break', 'TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Sp RowBreak { length cs }', '|a|', null],
    ['Count', 'TableRow <- Ind(ind) cs:TableCellAndPipe+ Pipe Sp RowBreak? { 0 }', '|a|b|', '0'],
  ];
  for (const [name, replacement, sample, count] of tableRowMutations) {
    const grammar = join(work, `ChangedTableRow${name}.hpeg`);
    writeFileSync(grammar, original.replace(tableRowShape, replacement));
    const strictMutation = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.match(strictMutation.stderr, /^unsupported TableRow choice /m);
    writeFileSync(grammar, tableRowEntryGrammar.replace(tableRowShape, replacement));
    const input = join(work, 'table-row-counterexample.gm');
    writeFileSync(input, sample);
    const nativeMutation = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', 'RowZeroProbe', '--format', 'ast', grammar, input], { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    if (count === null) {
      assert.notEqual(nativeMutation.status, 0, name + nativeMutation.stdout);
      assert.match(nativeMutation.stderr + nativeMutation.stdout, /^\d+:\d+: expected/m);
    } else {
      assert.equal(nativeMutation.status, 0, name + nativeMutation.stderr);
      assert.equal(nativeMutation.stdout.trim(), count);
    }
  }
  const commandEntryGrammar = original.replace('%syntax\n', '%syntax\n%entry CommandZeroProbe\n%entry CommandTwoProbe\n') +
    '\nCommandZeroProbe :: Bool\nCommandZeroProbe <- b:BlockCommand(0) { b }\nCommandTwoProbe :: Bool\nCommandTwoProbe <- b:BlockCommand(2) { b }\n';
  const commandEntryPath = join(work, 'CommandEntry.hpeg');
  writeFileSync(commandEntryPath, commandEntryGrammar);
  const commandRecognitionCases = [
    ['@set scale = 12\n', 0, 'False', ''], ['@set scale = 12', 0, 'False', ''],
    ['@style body align=center\n', 0, 'False', ''], ['@style body align=center', 0, 'False', ''],
    ['@style body align=center\n  one\n', 0, 'True', ''],
    ['  @style body align=center\n    鰍𠮷\n', 2, 'True', ''], ['@setx 12\n', 0, 'False', ''],
    ['@style body align=center\none\n', 0, null, 'one\n'], ['@set = 12\n', 0, null, null], ['@', 0, null, null],
  ];
  for (const [sample, ind, value] of commandRecognitionCases) {
    const input = join(work, 'command-entry.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', ind === 2 ? 'CommandTwoProbe' : 'CommandZeroProbe',
      '--format', 'ast', commandEntryPath, input], { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    if (value === null) {
      assert.notEqual(parsed.status, 0, sample + parsed.stdout);
      assert.match(parsed.stderr + parsed.stdout, /^\d+:\d+: expected/m);
    } else {
      assert.equal(parsed.status, 0, sample + parsed.stderr);
      assert.equal(parsed.stdout.trim(), value, 'the native command Bool distinguishes an indented body');
    }
  }
  const commandFirst = 'BlockCommand <- Ind(ind) At SetIdent Ws SetName Sp Eq ExprBody (Nl / !.) { False }';
  const commandSecond = '              / Ind(ind) At Ident Arguments Sp (Nl / !.) b:CommandBody(ind)? { maybe False (const True) b }';
  assert.ok(original.includes(commandFirst) && original.includes(commandSecond));
  const commandRecognitionMutations = [
    ['Indent', commandSecond.replace('Ind(ind)', 'Ind(ind + 1)'), '@style body align=center\n'],
    ['Identifier', commandSecond.replace('At Ident', 'At SetIdent'), '@style body align=center\n'],
    ['End', commandSecond.replace('(Nl / !.)', 'Nl'), '@style body align=center'],
    ['BodyIndent', commandSecond.replace('CommandBody(ind)', 'CommandBody(col ind + 1)'), '@style body align=center\n  one\n'],
    ['RequiredBody', commandSecond.replace('b:CommandBody(ind)? { maybe False (const True) b }', 'b:CommandBody(ind) { True }'), '@style body align=center\n'],
  ];
  for (const [name, changed, sample] of commandRecognitionMutations) {
    const grammar = join(work, `ChangedCommandRecognition${name}.hpeg`);
    writeFileSync(grammar, original.replace(commandSecond, changed));
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.match(rejected.stderr, /^unsupported BlockCommand choice /m);
    writeFileSync(grammar, commandEntryGrammar.replace(commandSecond, changed));
    const input = join(work, 'command-counterexample.gm');
    writeFileSync(input, sample);
    const native = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', 'CommandZeroProbe', '--format', 'ast', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(native.status, 0, name + native.stdout);
    assert.match(native.stderr + native.stdout, /^\d+:\d+: expected/m);
  }
  for (const [before, after] of [
    ['SetIdent Ws SetName', 'SetIdent Sp SetName'], ['Sp Eq ExprBody', 'Sp Eq Number'],
    ['{ False }', '{ True }'],
  ]) {
    const grammar = join(work, 'ChangedCommandSet.hpeg');
    writeFileSync(grammar, original.replace(commandFirst, commandFirst.replace(before, after)));
    const mutation = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.match(mutation.stderr, /^unsupported BlockCommand choice /m);
  }
  const groupEntryGrammar = original.replace('%syntax\n', '%syntax\n%entry GroupZeroProbe\n%entry GroupTwoProbe\n') +
    '\nGroupZeroProbe :: ()\nGroupZeroProbe <- BlockGroup(0) { () }\nGroupTwoProbe :: ()\nGroupTwoProbe <- BlockGroup(2) { () }\n';
  const groupEntryPath = join(work, 'GroupEntry.hpeg');
  writeFileSync(groupEntryPath, groupEntryGrammar);
  const groupCases = [
    ['@set scale = 12\none\n', 0, true, ''],
    ['@style body align=center\n  one\n', 0, true, ''],
    ['@style body align=center\n  one\ntwo\n', 0, false, 'two\n'],
    ['@style body align=center\n@style body align=center\n:::  \none\n:::\n', 0, true, ''],
    ['@set scale = 12\n@style body align=center\none\n', 0, true, ''],
    ['  @style body align=center\n    鰍𠮷\n', 2, true, ''],
    ['', 0, false, null], ['one\n', 0, false, null],
  ];
  for (const [sample, ind, accepted] of groupCases) {
    const input = join(work, 'group-entry.gm');
    writeFileSync(input, sample);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', ind === 2 ? 'GroupTwoProbe' : 'GroupZeroProbe',
      '--format', 'ast', groupEntryPath, input], { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, sample + parsed.stderr);
    if (accepted) assert.equal(parsed.stdout.trim(), '()');
    else assert.match(parsed.stderr + parsed.stdout, /^\d+:\d+: expected/m);
  }
  const groupProduction = 'cs:BlockCommand(ind)+ (&{ not (or (take 1 (reverse cs))) } GroupBody(ind))?';
  const groupGrammarMutations = [
    ['cs:BlockCommand(ind)+', 'cs:BlockCommand(ind)*'],
    ['cs:BlockCommand(ind)+', 'cs:BlockCommand(0)+'],
    ['not (or (take 1 (reverse cs)))', 'True'],
    ['not (or (take 1 (reverse cs)))', 'or (take 1 (reverse cs))'],
    ['GroupBody(ind)', 'GroupBody(col ind + 1)'],
    ['))?', '))+'],
  ];
  for (const [before, after] of groupGrammarMutations) {
    const changed = original.replace(groupProduction, groupProduction.replace(before, after));
    assert.notEqual(changed, original);
    const input = join(work, 'ChangedGroup.hpeg');
    writeFileSync(input, changed);
    const rejected = spawnSync(process.execPath, [join(here, 'generate.mjs'), input, generated], { encoding: 'utf8' });
    assert.match(rejected.stderr, /^unsupported BlockGroup choice /m);
  }

  const tableCompositionEntry = original.replace('%syntax\n', '%syntax\n%entry TableZeroProbe\n%entry BodyOneProbe\n%entry BodyTwoProbe\n') +
    '\nTableZeroProbe :: ()\nTableZeroProbe <- Table(0) { () }\nBodyOneProbe :: ()\nBodyOneProbe <- TableBodyRow(0,1) { () }\nBodyTwoProbe :: ()\nBodyTwoProbe <- TableBodyRow(0,2) { () }\n';
  const tableCompositionPath = join(work, 'TableCompositionEntry.hpeg');
  writeFileSync(tableCompositionPath, tableCompositionEntry);
  const tableCompositionCases = [
    ['TableZeroProbe', 'Table', 0, '|a|\n|-|', true, null],
    ['TableZeroProbe', 'Table', 0, '|a|\n|-|\n|b|', true, null],
    ['TableZeroProbe', 'Table', 0, '|a|b|\n|-|-|\n|鰍|กำ|', true, null],
    ['TableZeroProbe', 'Table', 0, '|a|b|\n|-|-|\n|c|', false, 'label: table_cells'],
    ['TableZeroProbe', 'Table', 0, '|a|\n|b|', false, 'label: table_delimiter'],
    ['BodyOneProbe', 'TableBodyRow', 1, '\n|a|', true, null],
    ['BodyOneProbe', 'TableBodyRow', 1, '\n|a|b|', false, 'label: table_cells'],
    ['BodyTwoProbe', 'TableBodyRow', 2, '\n|a|b|', true, null],
    ['BodyTwoProbe', 'TableBodyRow', 2, '\n|a|', false, 'label: table_cells'],
    ['BodyOneProbe', 'TableBodyRow', 1, '|a|', false, null],
  ];
  for (const [entry, , , source, accepted] of tableCompositionCases) {
    const input = join(work, 'table-composition-entry.gm');
    writeFileSync(input, source);
    const parsed = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', entry, '--format', 'ast', tableCompositionPath, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(parsed.status === 0, accepted, source + parsed.stderr);
    if (accepted) assert.equal(parsed.stdout.trim(), '()');
    else assert.match(parsed.stderr + parsed.stdout, /^\d+:\d+: expected/m);
  }
  const tableHead = 'Table <- h:TableRow(ind) Nl (TableDelimiter(ind))^table_delimiter';
  const tableTail = '         TableBodyRow(ind, h)* (!(Nl Ind(ind) Pipe))^table_row (Nl / !.) { () }';
  const tableBody = 'TableBodyRow <- Nl r:TableRow(ind) (&{ r == h })^table_cells { () }';
  const tableCompositionMutations = [
    ['HeaderNewline', tableHead, tableHead.replace(' Nl ', ' Sp '), 'TableZeroProbe', '|a|\n|-|', false],
    ['OneRow', tableTail, tableTail.replace('TableBodyRow(ind, h)*', 'TableBodyRow(ind, h)+'), 'TableZeroProbe', '|a|\n|-|', false],
    ['Width', tableTail, tableTail.replace('TableBodyRow(ind, h)', 'TableBodyRow(ind, h + 1)'), 'TableZeroProbe', '|a|\n|-|\n|b|', false],
    ['FinalNewline', tableTail, tableTail.replace('(Nl / !.)', 'Nl'), 'TableZeroProbe', '|a|\n|-|', false],
    ['CellGuard', tableBody, tableBody.replace('r == h', 'True'), 'BodyOneProbe', '\n|a|b|', true],
    ['BodyNewline', tableBody, tableBody.replace(' <- Nl ', ' <- Nl? '), 'BodyOneProbe', '|a|', true],
    ['BodyIndent', tableBody, tableBody.replace('TableRow(ind)', 'TableRow(col ind + 1)'), 'BodyOneProbe', '\n|a|', false],
  ];
  for (const [name, before, after, entry, source, accepted] of tableCompositionMutations) {
    assert.ok(original.includes(before));
    const grammar = join(work, `ChangedTableComposition${name}.hpeg`);
    writeFileSync(grammar, original.replace(before, after));
    const strictMutation = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.match(strictMutation.stderr, /^unsupported (Table|TableBodyRow) choice /m);
    writeFileSync(grammar, tableCompositionEntry.replace(before, after));
    const input = join(work, 'table-composition-counterexample.gm');
    writeFileSync(input, source);
    const native = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['parse', '--entry', entry, '--format', 'ast', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.equal(native.status === 0, accepted, name + native.stderr);
    if (accepted) assert.equal(native.stdout.trim(), '()');
    else assert.match(native.stderr + native.stdout, /^\d+:\d+: expected/m);
  }
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
  const reservedCommentSource = join(work, 'ReservedCommentTotal.lean');
  copyFileSync(join(here, 'ReservedCommentTotal.lean'), reservedCommentSource);
  const reservedCommentProof = spawnSync(lean, [reservedCommentSource], growthEnv);
  assert.equal(reservedCommentProof.status, 0, reservedCommentProof.stdout + reservedCommentProof.stderr);
  assert.doesNotMatch(reservedCommentProof.stdout + reservedCommentProof.stderr, /sorryAx|declaration uses 'sorry'/,
    'root ADR 0351: the arbitrary-input comment proof must not have a proof hole');
  const reservedCommentModelMutation = model.replace(
    /(name := "ReservedBracketBody"[^\n]*?)\.notPred \(\.lit "%%"/, '$1.andPred (.lit "%%"');
  assert.notEqual(reservedCommentModelMutation, model);
  writeFileSync(generated, reservedCommentModelMutation);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const reservedCommentRefuted = spawnSync(lean, [reservedCommentSource], growthEnv);
  assert.notEqual(reservedCommentRefuted.status, 0);
  assert.match(reservedCommentRefuted.stdout + reservedCommentRefuted.stderr, /type mismatch|unsolved goals/,
    'the changed actual AST must refute the proof, not its imports');
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
  const unboundSequenceSource = join(work, 'UnboundSequenceTotal.lean');
  const unboundSequenceCanonical = readFileSync(join(here, 'UnboundSequenceTotal.lean'), 'utf8');
  writeFileSync(unboundSequenceSource, unboundSequenceCanonical);
  const unboundSequenceProof = spawnSync(lean, ['-o', join(work, 'UnboundSequenceTotal.olean'), unboundSequenceSource], growthEnv);
  assert.equal(unboundSequenceProof.status, 0, unboundSequenceProof.stdout + unboundSequenceProof.stderr);
  assert.doesNotMatch(unboundSequenceProof.stdout + unboundSequenceProof.stderr, /sorryAx|declaration uses 'sorry'/);
  const droppedTail = unboundSequenceCanonical.replace('follow read items rest', '.ok (some rest)');
  assert.notEqual(droppedTail, unboundSequenceCanonical);
  writeFileSync(unboundSequenceSource, droppedTail);
  const brokenUnboundSequence = spawnSync(lean, [unboundSequenceSource], growthEnv);
  assert.notEqual(brokenUnboundSequence.status, 0);
  assert.match(brokenUnboundSequence.stdout + brokenUnboundSequence.stderr, /type mismatch|unsolved goals/);
  writeFileSync(unboundSequenceSource, unboundSequenceCanonical);
  const recoverySources = ['RecoveryDispatchTotal', 'ReservedBodyCompositionTotal'].map(name => join(work, name + '.lean'));
  for (const source of recoverySources) {
    copyFileSync(join(here, source.slice(source.lastIndexOf('/') + 1)), source);
    const proof = spawnSync(lean, [source], growthEnv);
    assert.equal(proof.status, 0, proof.stdout + proof.stderr);
    assert.doesNotMatch(proof.stdout + proof.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  for (const [rule, before, after] of [
    ['SkippedReserved', '.lit "[!" "\'[!\'", .ref', '.lit "[?" "\'[?\'", .ref'],
    ['SkippedReserved', '.lit "]" "\']\'"', '.lit "}" "\'}\'"'],
    ['SkippedReserved', '.star', '.plus'],
    ['SkippedReserved', null, null],
    ['ReservedBracketBody', '.star', '.plus'],
    ['ReservedBracketBody', '.ref "ReservedBracketBody" []', '.ref "Word" []'],
    ['ReservedBracketBody', '.lit "[" "\'[\'"', '.lit "{" "\'{\'"'],
    ['ReservedBracketBody', '.lit "]" "\']\'"', '.lit "}" "\'}\'"'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      if (before !== null) {
        assert.ok(line.includes(before));
        return line.replace(before, after);
      }
      const swapped = line.replace(/alts := \[(\{.*?\}), (\{.*?\}), (\{.*\})\] \}/, 'alts := [$2, $1, $3] }');
      assert.notEqual(swapped, line);
      return swapped;
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const target = recoverySources[rule === 'SkippedReserved' ? 0 : 1];
    const refuted = spawnSync(lean, [target], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'changed actual recovery AST must refute its theorem, not imports');
  }
  const recoveryMetadataControls = ['SkippedReserved', 'ReservedBracketBody'];
  for (const rule of recoveryMetadataControls) {
    const changed = model.split('\n').map(line => line.includes(`name := "${rule}"`)
      ? line.replaceAll(/line := (\d+)/g, (_, value) => `line := ${Number(value) + 17}`)
        .replaceAll('some " () "', 'some "  ()  "') : line).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const target = recoverySources[rule === 'SkippedReserved' ? 0 : 1];
    const preserved = spawnSync(lean, [target], growthEnv);
    assert.equal(preserved.status, 0, preserved.stdout + preserved.stderr);
    assert.doesNotMatch(preserved.stdout + preserved.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const recoveryFixtureSource = join(work, 'RecoveryNativeFixtures.lean');
  const fixtureItems = recoveryModelCases.map(([rule, sample, suffix]) =>
    `(${JSON.stringify(rule)}, ${JSON.stringify(sample)}, ${suffix === null ? 'none' : 'some ' + JSON.stringify(suffix)})`).join(',\n    ');
  writeFileSync(recoveryFixtureSource, `import PegModelTest
open PegModel
#eval do
  let fixtures : List (String × String × Option String) := [${fixtureItems}]
  for (rule, source, expected) in fixtures do
    let got := recognizeEnv Generated.pegGrammar [] 256 (.ref rule []) source.toList
    let agrees := match got, expected with
      | .ok none, none => true
      | .ok (some rest), some suffix => rest == suffix.toList
      | _, _ => false
    unless agrees do throw (IO.userError s!"recovery fixture mismatch {repr source}: {repr got}")
  IO.println s!"model/native recovery fixtures: {fixtures.length} outcomes matched"
`);
  const recoveryFixtureCheck = spawnSync(lean, [recoveryFixtureSource], growthEnv);
  assert.equal(recoveryFixtureCheck.status, 0, recoveryFixtureCheck.stdout + recoveryFixtureCheck.stderr);
  assert.match(recoveryFixtureCheck.stdout, new RegExp(`model/native recovery fixtures: ${recoveryModelCases.length} outcomes matched`));
  const inertSource = join(work, 'InertCaptureSequenceTotal.lean');
  const inertCanonical = readFileSync(join(here, 'InertCaptureSequenceTotal.lean'), 'utf8');
  writeFileSync(inertSource, inertCanonical);
  const inertProof = spawnSync(lean, ['-o', join(work, 'InertCaptureSequenceTotal.olean'), inertSource], growthEnv);
  assert.equal(inertProof.status, 0, inertProof.stdout + inertProof.stderr);
  assert.doesNotMatch(inertProof.stdout + inertProof.stderr, /sorryAx|declaration uses 'sorry'/);
  const bindingLeak = inertCanonical.replace('| .ok none => pure (some (next, scope))', '| .ok none => pure (some (next, ("ghost", 0) :: scope))');
  assert.notEqual(bindingLeak, inertCanonical);
  writeFileSync(inertSource, bindingLeak);
  const brokenInert = spawnSync(lean, [inertSource], growthEnv);
  assert.notEqual(brokenInert.status, 0);
  assert.match(brokenInert.stdout + brokenInert.stderr, /type mismatch|unsolved goals/);
  writeFileSync(inertSource, inertCanonical);
  const captureSources = ['TableRowCompositionTotal', 'CommandRecognitionTotal'].map(name => join(work, name + '.lean'));
  for (const source of captureSources) {
    copyFileSync(join(here, source.slice(source.lastIndexOf('/') + 1)), source);
    const proof = spawnSync(lean, [source], growthEnv);
    assert.equal(proof.status, 0, proof.stdout + proof.stderr);
    assert.doesNotMatch(proof.stdout + proof.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  for (const [rule, before, after] of [
    ['TableRow', '.plus', '.star'], ['TableRow', '.ref "Ind" ["ind"]', '.ref "Ind" ["col ind + 1"]'],
    ['TableRow', '.ref "Pipe" []', '.ref "Sp" []'], ['TableRow', '.ref "TableCellAndPipe" []', '.ref "Pipe" []'],
    ['TableRow', 'length cs', '0'], ['BlockCommand', '.ref "SetIdent" []', '.ref "Ident" []'],
    ['BlockCommand', '.ref "Ws" []', '.ref "Sp" []'], ['BlockCommand', '.ref "ExprBody" []', '.ref "Number" []'],
    ['BlockCommand', null, null], ['BlockCommand', '.opt (.ref "CommandBody" ["ind"])', '.star (.ref "CommandBody" ["ind"])'],
    ['BlockCommand', 'maybe False (const True) b', 'False'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      if (before !== null) {
        assert.ok(line.includes(before));
        return line.replace(before, after);
      }
      const swapped = line.replace(/alts := \[(\{.*?\}), (\{.*\})\] \}/, 'alts := [$2, $1] }');
      assert.notEqual(swapped, line);
      return swapped;
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const target = captureSources[rule === 'TableRow' ? 0 : 1];
    const refuted = spawnSync(lean, [target], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/);
  }
  const captureMetadataControls = ['TableRow', 'BlockCommand'];
  for (const rule of captureMetadataControls) {
    const changed = model.split('\n').map(line => line.includes(`name := "${rule}"`)
      ? line.replace(/line := (\d+)/g, (_, n) => `line := ${Number(n) + 17}`) : line).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const target = captureSources[rule === 'TableRow' ? 0 : 1];
    const kept = spawnSync(lean, [target], growthEnv);
    assert.equal(kept.status, 0, kept.stdout + kept.stderr);
    assert.doesNotMatch(kept.stdout + kept.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const captureFixtureCases = [
    ...tableRowCases.map(([source, ind, , suffix]) => ['TableRow', ind, source, suffix === 'label: hard_break' ? null : suffix, suffix === 'label: hard_break' ? suffix : null]),
    ...commandRecognitionCases.map(([source, ind, , suffix]) => ['BlockCommand', ind, source, suffix, null]),
  ];
  const captureFixtureSource = join(work, 'CaptureNativeFixtures.lean');
  const captureFixtureItems = captureFixtureCases.map(([rule, ind, source, suffix, error]) =>
    `(${JSON.stringify(rule)}, ${ind}, ${JSON.stringify(source)}, ${suffix === null ? 'none' : 'some ' + JSON.stringify(suffix)}, ${error === null ? 'none' : 'some ' + JSON.stringify(error)})`).join(',\n    ');
  writeFileSync(captureFixtureSource, `import PegModelTest
open PegModel
#eval do
  let fixtures : List (String × Nat × String × Option String × Option String) := [${captureFixtureItems}]
  for (rule, ind, source, suffix, error) in fixtures do
    let got := recognizeEnv Generated.pegGrammar [("ind",ind)] 256 (.ref rule ["ind"]) source.toList
    let agrees := match got, suffix, error with
      | .error reason, _, some expected => reason == expected
      | .ok none, none, none => true
      | .ok (some rest), some expected, none => rest == expected.toList
      | _, _, _ => false
    unless agrees do throw (IO.userError s!"capture fixture mismatch {repr source}: {repr got}")
  IO.println s!"model/native capture fixtures: {fixtures.length} outcomes matched"
`);
  const captureFixtureCheck = spawnSync(lean, [captureFixtureSource], growthEnv);
  assert.equal(captureFixtureCheck.status, 0, captureFixtureCheck.stdout + captureFixtureCheck.stderr);
  assert.match(captureFixtureCheck.stdout, new RegExp(`model/native capture fixtures: ${captureFixtureCases.length} outcomes matched`));
  function compileTableCapture(name, output = false) {
    const args = output ? ['-o', join(work, name + '.olean'), join(work, name + '.lean')] : [join(work, name + '.lean')];
    const result = spawnSync(lean, args, growthEnv);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.doesNotMatch(result.stdout + result.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  function refuteTableCapture(name) {
    const result = spawnSync(lean, [join(work, name + '.lean')], growthEnv);
    assert.notEqual(result.status, 0);
    assert.match(result.stdout + result.stderr, /type mismatch|unsolved goals/);
  }
  for (const name of ['CapturedSequenceTotal', 'CapturedValueTotal', 'TableCompositionTotal']) {
    copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    compileTableCapture(name, true);
  }
  const capturedSequenceFile = join(work, 'CapturedSequenceTotal.lean');
  const capturedSequenceCanonical = readFileSync(capturedSequenceFile, 'utf8');
  const capturedScopeLeak = capturedSequenceCanonical.replace('follow parse bound ((name,value)::scope) items rest', 'follow parse bound scope items rest');
  assert.notEqual(capturedScopeLeak, capturedSequenceCanonical);
  writeFileSync(capturedSequenceFile, capturedScopeLeak);
  refuteTableCapture('CapturedSequenceTotal');
  writeFileSync(capturedSequenceFile, capturedSequenceCanonical);
  const capturedValueFile = join(work, 'CapturedValueTotal.lean');
  const capturedValueCanonical = readFileSync(capturedValueFile, 'utf8');
  const capturedCountLeak = capturedValueCanonical.replace('count + 1', 'count');
  assert.notEqual(capturedCountLeak, capturedValueCanonical);
  writeFileSync(capturedValueFile, capturedCountLeak);
  compileTableCapture('CapturedValueTotal', true);
  refuteTableCapture('TableCompositionTotal');
  writeFileSync(capturedValueFile, capturedValueCanonical);
  compileTableCapture('CapturedValueTotal', true);
  for (const [rule, before, after] of [
    ['Table', '.ref "TableRow" ["ind"]', '.ref "TableRow" ["col ind + 1"]'],
    ['Table', '.ref "Nl" []', '.ref "Sp" []'], ['Table', '.star', '.plus'],
    ['Table', '.ref "TableBodyRow" ["ind", "h"]', '.ref "TableBodyRow" ["ind", "h + 1"]'],
    ['Table', '.notPred (.choice', '.andPred (.choice'],
    ['Table', '.label (.choice [[.ref "TableDelimiter" ["ind"]]]) "table_delimiter"', '.notPred (.choice [[.ref "TableDelimiter" ["ind"]]])'],
    ['TableBodyRow', '.ref "Nl" []', '.opt (.ref "Nl" [])'],
    ['TableBodyRow', '.ref "TableRow" ["ind"]', '.ref "TableRow" ["col ind + 1"]'],
    ['TableBodyRow', ' r == h ', ' True '], ['TableBodyRow', '"table_cells"', '"table_row"'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    refuteTableCapture('TableCompositionTotal');
  }
  const tableMetadataControls = ['Table', 'TableBodyRow'];
  for (const rule of tableMetadataControls) {
    const changed = model.split('\n').map(line => line.includes(`name := "${rule}"`)
      ? line.replace(/line := (\d+)/g, (_, n) => `line := ${Number(n) + 17}`).replaceAll(' () ', '  ()  ') : line).join('\n');
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    compileTableCapture('TableCompositionTotal');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const tableFixtureSource = join(work, 'TableNativeFixtures.lean');
  const tableFixtureItems = tableCompositionCases.map(([, rule, h, source, accepted, error]) =>
    `(${JSON.stringify(rule)}, ${h}, ${JSON.stringify(source)}, ${accepted}, ${error === null ? 'none' : 'some ' + JSON.stringify(error)})`).join(',\n    ');
  writeFileSync(tableFixtureSource, `import PegModelTest
open PegModel
#eval do
  let fixtures : List (String × Nat × String × Bool × Option String) := [${tableFixtureItems}]
  for (rule, h, source, accepted, error) in fixtures do
    let env := if rule == "Table" then [("ind",0)] else [("ind",0),("h",h)]
    let args := if rule == "Table" then ["ind"] else ["ind","h"]
    let got := recognizeEnv Generated.pegGrammar env 512 (.ref rule args) source.toList
    let agrees := match got, accepted, error with
      | .ok (some []), true, none => true
      | .error reason, false, some expected => reason == expected
      | .ok none, false, none => true
      | _, _, _ => false
    unless agrees do throw (IO.userError s!"table fixture mismatch {repr source}: {repr got}")
  IO.println s!"model/native table fixtures: {fixtures.length} outcomes matched"
`);
  const tableFixtureCheck = spawnSync(lean, [tableFixtureSource], growthEnv);
  assert.equal(tableFixtureCheck.status, 0, tableFixtureCheck.stdout + tableFixtureCheck.stderr);
  assert.match(tableFixtureCheck.stdout, new RegExp(`model/native table fixtures: ${tableCompositionCases.length} outcomes matched`));
  // The old standalone check did not write the imported module artifact.
  compileTableCapture('CommandRecognitionTotal', true);
  const booleanProofModules = ["StructuralCoherence","OptionalBoolTotal","ChoicePayloadTotal","PayloadSequenceTotal","CommandBoolProjectionTotal","BoolRepetitionTotal","CommandCollectionTotal","GenericBoolPayloadTotal","LastBoolGuardTotal","CoreWalkerCoherence","CorePayloadCoherence","CachedPayloadCoherence","GroupOptionalTotal","BlockGroupCompositionTotal"];
  for (const name of booleanProofModules) {
    copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    compileTableCapture(name, true);
  }
  for (const [before, after] of [
    ['.bind (some "cs") (.plus', '.bind (some "cs") (.star'],
    ['.ref "BlockCommand" ["ind"]', '.ref "BlockCommand" ["0"]'],
    [' not (or (take 1 (reverse cs))) ', ' True '],
    ['.semanticPred true', '.semanticPred false'],
    ['.ref "GroupBody" ["ind"]', '.ref "GroupBody" ["col ind + 1"]'],
    ['.opt (.choice', '.plus (.choice'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes('name := "BlockGroup"')) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    refuteTableCapture('BlockGroupCompositionTotal');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const groupMetadataControls = ['BlockGroup'];
  for (const rule of groupMetadataControls) {
    const changed = model.split('\n').map(line => line.includes('name := "' + rule + '"')
      ? line.replace(/line := (\d+)/g, (_, n) => 'line := ' + (Number(n) + 17)).replaceAll(' () ', '  ()  ') : line).join('\n');
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    compileTableCapture('BlockGroupCompositionTotal');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const wholeFixtureSource = join(work, 'WholeParserCorpus.lean');
  const wholeFixtureItems = parserCases.map(([source]) => JSON.stringify(source)).join(',\n');
  writeFileSync(wholeFixtureSource, 'import Generated\nopen PegModel\n#eval do\n' +
    '  let sources : List String := [' + wholeFixtureItems + ']\n' +
    '  for source in sources do\n' +
    '    let got := recognizeStart Generated.pegGrammar 512 source.toList\n' +
    '    let agrees := match got with | .ok (some []) => true | _ => false\n' +
    '    unless agrees do throw (IO.userError s!"whole parser mismatch {repr source}: {repr got}")\n' +
    '  IO.println s!"whole model/native parser corpus: {sources.length} accepted inputs matched"\n');
  const wholeFixtureCheck = spawnSync(lean, [wholeFixtureSource], growthEnv);
  assert.equal(wholeFixtureCheck.status, 0, wholeFixtureCheck.stdout + wholeFixtureCheck.stderr);
  assert.match(wholeFixtureCheck.stdout, new RegExp('whole model/native parser corpus: ' + parserCases.length + ' accepted inputs matched'));
  const groupFixtureSource = join(work, 'GroupNativeFixtures.lean');
  const groupFixtureItems = groupCases.map(([source, ind, , suffix]) =>
    '(' + JSON.stringify(source) + ', ' + ind + ', ' + (suffix === null ? 'none' : 'some ' + JSON.stringify(suffix)) + ')').join(',\n');
  writeFileSync(groupFixtureSource, 'import BlockGroupCompositionTotal\nopen PegModel\n#eval do\n' +
    '  let fixtures : List (String × Nat × Option String) := [' + groupFixtureItems + ']\n' +
    '  for (source, ind, suffix) in fixtures do\n' +
    '    let got := recognizeEnv Generated.pegGrammar [("ind",ind)] 512 (.ref "BlockGroup" ["ind"]) source.toList\n' +
    '    let agrees := match got, suffix with\n' +
    '      | .ok none, none => true\n      | .ok (some rest), some expected => rest == expected.toList\n      | _, _ => false\n' +
    '    unless agrees do throw (IO.userError s!"group mismatch {repr source}: {repr got}")\n' +
    '  IO.println s!"model/native group fixtures: {fixtures.length} outcomes matched"\n');
  const groupFixtureCheck = spawnSync(lean, [groupFixtureSource], growthEnv);
  assert.equal(groupFixtureCheck.status, 0, groupFixtureCheck.stdout + groupFixtureCheck.stderr);
  assert.match(groupFixtureCheck.stdout, /model\/native group fixtures: 8 outcomes matched/);
  const quotedChecks = verifyQuoted({ here, work, generated, model, original, lean, growthEnv });
  const mixedChecks = verifyMixed({ here, work, lean, growthEnv });
  const lowerChecks = verifyLower({ here, work, lean, growthEnv });
  const wrapperChecks = verifyWrapper({ here, work, lean, growthEnv, model, original });
  const blockRemainderSource = join(work, 'BlockRemainderTotal.lean');
  copyFileSync(join(here, 'BlockRemainderTotal.lean'), blockRemainderSource);
  const blockRemainderProof = spawnSync(lean, [blockRemainderSource], growthEnv);
  assert.equal(blockRemainderProof.status, 0, blockRemainderProof.stdout + blockRemainderProof.stderr);
  assert.doesNotMatch(blockRemainderProof.stdout + blockRemainderProof.stderr, /sorryAx|declaration uses 'sorry'/);
  for (const [rule, before, after] of [
    ['ListItem', '.plus', '.star'],
    ['ListItem', '.ref "ListMark" ["ordered"]', '.ref "ListMark" ["0"]'],
    ['ListItem', '.ref "Ws" []', '.ref "Sp" []'],
    ['ListItem', '.ref "ItemTail" ["col ind + 2"]', '.ref "ItemTail" ["col ind + 3"]'],
    ['Div', '.ref "Ind" ["ind"]', '.ref "Ind" ["col ind + 1"]'],
    ['Div', '.ref "DivBlocks" ["fenced ind"]', '.ref "DivBlocks" ["ind"]'],
    ['Div', '.ref "DivMark" []', '.ref "DivLine" []'],
    ['Div', '.opt (.choice [[.opt (.ref "BlankLines" [])', '.plus (.choice [[.opt (.ref "BlankLines" [])'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const refuted = spawnSync(lean, [blockRemainderSource], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'root ADR 0351 I1, I2: changed actual item/fence must refute the theorem, not imports');
  }
  const metadataOnlyAstControls = ['ListItem', 'Div'];
  for (const rule of metadataOnlyAstControls) {
    const changed = model.split('\n').map(line => line.includes(`name := "${rule}"`)
      ? line.replaceAll(/line := (\d+)/g, (_, value) => `line := ${Number(value) + 17}`)
        .replace('some " () "', 'some "  ()  "') : line).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const preserved = spawnSync(lean, [blockRemainderSource], growthEnv);
    assert.equal(preserved.status, 0, preserved.stdout + preserved.stderr);
    assert.doesNotMatch(preserved.stdout + preserved.stderr, /sorryAx|declaration uses 'sorry'/);
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const listCompositionSource = join(work, 'ListCompositionTotal.lean');
  copyFileSync(join(here, 'ListCompositionTotal.lean'), listCompositionSource);
  const listCompositionProof = spawnSync(lean, ['-o', join(work, 'ListCompositionTotal.olean'), listCompositionSource], growthEnv);
  assert.equal(listCompositionProof.status, 0, listCompositionProof.stdout + listCompositionProof.stderr);
  assert.doesNotMatch(listCompositionProof.stdout + listCompositionProof.stderr, /sorryAx|declaration uses 'sorry'/);
  const listModelMutation = model.replace(/(name := "BulletList"[^\n]*?\.ref "ListItem" \["ind", )"0"/, '$1"1"');
  assert.notEqual(listModelMutation, model);
  writeFileSync(generated, listModelMutation);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const listRefuted = spawnSync(lean, [listCompositionSource], growthEnv);
  assert.notEqual(listRefuted.status, 0);
  assert.match(listRefuted.stdout + listRefuted.stderr, /type mismatch|unsolved goals/,
    'root ADR 0351 I1, I2: actual generated list-kind mutation must refute the theorem, not imports');
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const fileCompositionSource = join(work, 'FileCompositionTotal.lean');
  copyFileSync(join(here, 'FileCompositionTotal.lean'), fileCompositionSource);
  const fileCompositionProof = spawnSync(lean, [fileCompositionSource], growthEnv);
  assert.equal(fileCompositionProof.status, 0, fileCompositionProof.stdout + fileCompositionProof.stderr);
  assert.doesNotMatch(fileCompositionProof.stdout + fileCompositionProof.stderr, /sorryAx|declaration uses 'sorry'/);
  for (const [before, after] of [
    ['.opt (.ref "BlankLines" [])', '.ref "BlankLines" []'],
    ['.andPred (.any)', '.notPred (.any)'],
    ['.ref "Blocks" ["0"]', '.ref "Blocks" ["1"]'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes('name := "File"')) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const refuted = spawnSync(lean, [fileCompositionSource], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'root ADR 0351 I1, I2: changed generated File must refute the theorem, not imports');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const blockSequenceSource = join(work, 'BlockSequenceTotal.lean');
  copyFileSync(join(here, 'BlockSequenceTotal.lean'), blockSequenceSource);
  const blockSequenceProof = spawnSync(lean, [blockSequenceSource], growthEnv);
  assert.equal(blockSequenceProof.status, 0, blockSequenceProof.stdout + blockSequenceProof.stderr);
  assert.doesNotMatch(blockSequenceProof.stdout + blockSequenceProof.stderr, /sorryAx|declaration uses 'sorry'/);
  for (const [rule, before, after] of [
    ['Blocks', '.ref "Block" ["ind"]', '.ref "Paragraph" ["ind"]'],
    ['ItemTail', '.star', '.plus'],
    ['DivBlocks', '.notPred', '.andPred'],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const refuted = spawnSync(lean, [blockSequenceSource], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'root ADR 0351 I1, I2: changed generated block sequence must refute its theorem, not imports');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const definitionCompositionSource = join(work, 'DefinitionCompositionTotal.lean');
  copyFileSync(join(here, 'DefinitionCompositionTotal.lean'), definitionCompositionSource);
  const definitionProof = spawnSync(lean, ['-o', join(work, 'DefinitionCompositionTotal.olean'), definitionCompositionSource], growthEnv);
  assert.equal(definitionProof.status, 0, definitionProof.stdout + definitionProof.stderr);
  assert.doesNotMatch(definitionProof.stdout + definitionProof.stderr, /sorryAx|declaration uses 'sorry'/);
  for (const [rule, before, after] of [
    ['DefList', '.ref "DefGroup" ["ind"]', '.ref "DefTerm" ["ind"]'],
    ['DefGroup', '.plus (.ref "DefTerm" ["ind"])', '.star (.ref "DefTerm" ["ind"])'],
    ['DefBody', '.andPred', '.notPred'],
  ]) {
    const astChanged = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      assert.ok(line.includes(before));
      return line.replace(before, after);
    }).join('\n');
    assert.notEqual(astChanged, model);
    writeFileSync(generated, astChanged);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const refuted = spawnSync(lean, [definitionCompositionSource], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'root ADR 0351 I1, I2: changing the generated definition AST must refute the theorem, not its imports');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
  const bodyDispatchSource = join(work, 'BodyDispatchTotal.lean');
  copyFileSync(join(here, 'BodyDispatchTotal.lean'), bodyDispatchSource);
  const bodyDispatchProof = spawnSync(lean, [bodyDispatchSource], growthEnv);
  assert.equal(bodyDispatchProof.status, 0, bodyDispatchProof.stdout + bodyDispatchProof.stderr);
  assert.doesNotMatch(bodyDispatchProof.stdout + bodyDispatchProof.stderr, /sorryAx|declaration uses 'sorry'/);
  for (const [rule, before, after] of [
    ['CommandBody', '.andPred', '.notPred'],
    ['CommandBody', '.ref "Blocks" ["col ind + 2"]', '.ref "Block" ["col ind + 2"]'],
    ['GroupBody', '.ref "Div" ["ind"]', '.ref "Div" ["col ind + 1"]'],
    ['GroupBody', '.notPred (.ref "BlockCommandStart" [])', '.andPred (.ref "BlockCommandStart" [])'],
    ['GroupBody', null, null],
  ]) {
    const changed = model.split('\n').map(line => {
      if (!line.includes(`name := "${rule}"`)) return line;
      if (before !== null) {
        assert.ok(line.includes(before));
        return line.replace(before, after);
      }
      const swapped = line.replace(/alts := \[(\{.*?\}), (\{.*?\})\] \}/, 'alts := [$2, $1] }');
      assert.notEqual(swapped, line);
      return swapped;
    }).join('\n');
    assert.notEqual(changed, model);
    writeFileSync(generated, changed);
    execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
    const refuted = spawnSync(lean, [bodyDispatchSource], growthEnv);
    assert.notEqual(refuted.status, 0);
    assert.match(refuted.stdout + refuted.stderr, /type mismatch|unsolved goals/,
      'root ADR 0351 I1, I2: changed actual body dispatch must refute the theorem, not imports');
  }
  writeFileSync(generated, model);
  execFileSync(lean, ['-o', join(work, 'Generated.olean'), generated], growthEnv);
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
  console.log(`grammar: source and AST rules ${emittedRuleCount}/${astRuleCount}/${sourceRuleCount}, unsupported choices ${unsupportedChoices}, positive proof modules ${45 + booleanProofModules.length + quotedChecks.modules + mixedChecks.modules + lowerChecks.modules + wrapperChecks.modules}, negative mutations ${285 + quotedChecks.semanticMutants + quotedChecks.sourceMutants + quotedChecks.astMutants + mixedChecks.semanticMutants + lowerChecks.semanticMutants + wrapperChecks.semanticMutants + wrapperChecks.metadataMutants}, metadata-only AST controls ${metadataOnlyAstControls.length + recoveryMetadataControls.length + captureMetadataControls.length + tableMetadataControls.length + groupMetadataControls.length + quotedChecks.metadataControls}, implementation parser cases ${parserCases.length}, model/native whole-file fixtures ${parserCases.length}, syntax-only parser cases 1, native legacy-body syntax cases ${legacyBodyParserCases.length}, native unclosed-fence syntax cases 1, native reserved-body entry cases ${nativeBodySamples.length}, native recovery-entry cases ${recoveryFixtures.length + nestedBodyCases.length}, model/native recovery fixtures ${recoveryModelCases.length}, native table-row entries ${tableRowCases.length}, native command entries ${commandRecognitionCases.length}, model/native capture fixtures ${captureFixtureCases.length}, model/native table fixtures ${tableCompositionCases.length}, model/native group fixtures ${groupCases.length}, model/native quoted fixtures ${quotedChecks.fixtures}, model/native mixed fixtures ${mixedChecks.fixtures}, model/native lowered CST fixtures ${lowerChecks.fixtures}, model/native raw CST fixtures ${wrapperChecks.fixtures}, native CST shape counterexamples ${wrapperChecks.nativeShapeCounterexamples}, native block-sequence traces ${blockSequenceParserCases.length}, native parser counterexamples ${quotedChecks.nativeCounterexamples + 3 + tableCompositionMutations.length + tableRowMutations.length + commandRecognitionMutations.length + recoveryMutations.length + bodyCompositionMutations.length + nativeBlockRemainderMutations.length + nativeBodyDispatchMutations.length + nativeFileMutations.length + nativeListMutations.length + nativeDefinitionMutations.length + nativeBlockSequenceMutations.length + nativeLexicalMutations.length + nativeCompositionMutations.length + nativeExpressionMutations.length + nativeArgumentMutations.length + nativeBlockLeafMutations.length}, rejected parser cases ${groupCases.filter(([, , accepted]) => !accepted).length + tableCompositionCases.filter(([, , , , accepted]) => !accepted).length + tableRowCases.filter(([, , count]) => count === null).length + commandRecognitionCases.filter(([, , value]) => value === null).length + recoveryFixtures.filter(([, suffix]) => suffix !== "").length + bodyEntryRejectedCases.length + emptyItemRejectedCases.length + rejectedParserCases.length + badDelimiterCases.length + 1 + lexicalRejectedCases.length + compositionRejectedCases.length + expressionRejectedCases.length + argumentRejectedCases.length + blockLeafRejectedCases.length}`);
} finally {
  rmSync(work, { recursive: true, force: true });
}
