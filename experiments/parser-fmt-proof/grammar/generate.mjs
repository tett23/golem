import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const fragment = process.argv[2] === '--fragment';
const [input, output] = process.argv.slice(fragment ? 3 : 2);
if (!input || !output) {
  console.error('usage: node generate.mjs [--fragment] Golem.hpeg Generated.lean');
  process.exit(2);
}

const grammar = readFileSync(input, 'utf8');
const errors = [];
const peg = spawnSync(process.env.PEG_HS ?? 'peg-hs', ['lint', input], { encoding: 'utf8' });
if (peg.error || peg.status !== 0) {
  errors.push(`peg-hs: ${peg.error?.message ?? (peg.stderr || peg.stdout).trim()}`);
}
// Use the exact peg-grammar package selected by this Cabal plan.  Several
// versions can have the same package name in the store.
let ast;
try {
  const plan = JSON.parse(readFileSync(process.env.CABAL_PLAN ?? 'dist-newstyle/cache/plan.json', 'utf8'));
  const packageId = name => plan['install-plan'].find(unit => unit['pkg-name'] === name)?.id;
  const pegId = packageId('peg-grammar');
  const aesonId = packageId('aeson');
  if (!pegId || !aesonId) throw new Error('Cabal plan needs peg-grammar and aeson');
  const compiler = plan['compiler-id'];
  const store = join(process.env.CABAL_DIR ?? join(homedir(), '.cabal'), 'store');
  const packageDb = process.env.GHC_PACKAGE_DB ?? readdirSync(store)
    .filter(name => name.startsWith(compiler) && existsSync(join(store, name, 'package.db')))
    .map(name => join(store, name, 'package.db'))[0];
  if (!packageDb) throw new Error(`no package database for ${compiler}`);
  const runghc = process.env.RUNGHC ?? `runghc-${compiler.slice(4)}`;
  const exporter = fileURLToPath(new URL('./export-peg.hs', import.meta.url));
  const result = spawnSync(runghc, [
    `--ghc-arg=-package-db=${packageDb}`,
    `--ghc-arg=-package-id=${pegId}`,
    `--ghc-arg=-package-id=${aesonId}`,
    exporter,
    input
  ], { encoding: 'utf8' });
  if (result.error || result.status !== 0) throw new Error(result.error?.message ?? result.stderr.trim());
  ast = JSON.parse(result.stdout);
} catch (error) {
  errors.push(`peg-hs AST: ${error.message}`);
}
const sourceRules = [];
let activeRule = false;
for (const [lineNumber, line] of grammar.split('\n').entries()) {
  const start = line.match(/^([A-Za-z][A-Za-z0-9]*) <- (.*)$/);
  if (start) {
    sourceRules.push([start[1], start[2], lineNumber + 1]);
    activeRule = true;
  } else if (activeRule && /^\s+\S/.test(line)) {
    sourceRules[sourceRules.length - 1][1] += `\n${line}`;
  } else {
    activeRule = false;
  }
}
const names = sourceRules.map(([name]) => name);
for (const name of new Set(names)) {
  if (names.filter(other => other === name).length !== 1) errors.push(`${name}: duplicate production`);
}
// Report choices from peg-hs's AST, including branches nested under labels,
// repetition and templates. A second PEG scanner could miss syntax it does not
// understand, so the report and Lean model share this one canonical source.
function describeExpr(expr) {
  const child = () => describeExpr(expr.expr);
  switch (expr.tag) {
    case 'lit': return expr.written;
    case 'class': return expr.written;
    case 'any': return '.';
    case 'ref': return `${expr.name}${expr.args.length ? `(${expr.args.join(', ')})` : ''}`;
    case 'choice': return `(${expr.alts.map(describeItems).join(' / ')})`;
    case 'star': return `${child()}*`;
    case 'plus': return `${child()}+`;
    case 'opt': return `${child()}?`;
    case 'and': return `&${child()}`;
    case 'not': return `!${child()}`;
    case 'capture': return `$${child()}`;
    case 'label': return `${child()}^${expr.name}`;
    case 'pred': return `${expr.positive ? '&' : '!'}{${expr.source}}`;
    case 'template': return `${expr.name}<${expr.children.map(describeExpr).join(', ')}>${expr.args.length ? `(${expr.args.join(', ')})` : ''}`;
    case 'discard': return `~${child()}`;
    default: throw new Error(`unknown peg-hs expression ${expr.tag}`);
  }
}
function describeItems(items) {
  return items.map(item => `${item.bind === null ? '' : `${item.bind}:`}${describeExpr(item.expr)}`).join(' ');
}
function nestedChoices(expr, visit) {
  switch (expr.tag) {
    case 'choice':
      if (expr.alts.length > 1 && !expr.alts.every(items =>
          items.length === 1 && items[0].bind === null && items[0].expr.tag === 'ref') &&
          !provedNlEofChoice(expr) &&
          !provedLiteralNlEofChoice(expr) && !provedClassLookaheadOrEof(expr))
        expr.alts.filter(items => !provedEscapeItems(items) && !provedReservedOrdinary(items)).forEach(visit);
      expr.alts.flat().forEach(item => nestedChoices(item.expr, visit));
      break;
    case 'star': case 'plus': case 'opt': case 'and': case 'not':
    case 'capture': case 'label': case 'discard':
      nestedChoices(expr.expr, visit);
      break;
    case 'template':
      expr.children.forEach(child => nestedChoices(child, visit));
      break;
    case 'lit': case 'class': case 'any': case 'ref': case 'pred':
      break;
    default: throw new Error(`unknown peg-hs expression ${expr.tag}`);
  }
}

function rule(name) {
  const lines = grammar.split('\n');
  const starts = lines.flatMap((line, index) => line.startsWith(`${name} <- `) ? [index] : []);
  if (starts.length !== 1) {
    errors.push(`${name}: expected one production, found ${starts.length}`);
    return '';
  }
  const first = starts[0];
  const body = [lines[first].slice(name.length + 4)];
  for (let i = first + 1; i < lines.length && /^\s+\S/.test(lines[i]); i++) {
    body.push(lines[i].trim());
  }
  return body.join(' ').replaceAll(' { () }', '').replace(/\s+/g, ' ').trim();
}

const string = rule('StringLit');
const quoted = /^'"' \((.*)\)\* '"'$/;
const match = string.match(quoted);
const alternatives = match?.[1].split(' / ') ?? [];
const escape = String.raw`'\\' .`;
const ordinary = String.raw`!["\n] .`;
const stringSupported = alternatives.length === 2 && alternatives.includes(escape) && alternatives.includes(ordinary);
if (!stringSupported) {
  errors.push(`StringLit: unsupported alternatives ${JSON.stringify(alternatives.length ? alternatives : string)}`);
}

const ident = rule('Ident');
const word = rule('Word');
const args = rule('Arguments');
const argValue = rule('ArgValue');
const keyword = rule('KeywordArgument');
function forbiddenChars(source) {
  const begin = source.indexOf('![');
  if (begin < 0) return null;
  const chars = [];
  let escaped = false;
  for (let i = begin + 2; i < source.length; i++) {
    const char = source[i];
    if (escaped) {
      chars.push({ t: '\t', n: '\n', r: '\r' }[char] ?? char);
      escaped = false;
    } else if (char === '\\') {
      escaped = true;
    } else if (char === ']') {
      return chars;
    } else {
      chars.push(char);
    }
  }
  return null;
}
const wordChoice = word.lastIndexOf(' / ');
const ordinaryWord = wordChoice < 0 ? word : word.slice(wordChoice + 3);
const forbidden = forbiddenChars(ordinaryWord);
if (!forbidden) errors.push(`Word: unsupported character class ${JSON.stringify(word)}`);
const productions = { Ident: ident, Word: word, Arguments: args, ArgValue: argValue, KeywordArgument: keyword };
const shapes = {
  Ident: ["[a-z] [a-z0-9\\-]* ('.' [a-z] [a-z0-9\\-]*)? !('.' [a-z])"],
  Word: [
    '(![ \\t\\n\\]:|=\\["\\\\] .)+',
    '\'%%=\' (![ \\t\\n\\]:|\\["\\\\] .)* / (![ \\t\\n\\]:|=\\["\\\\] .)+'
  ],
  Arguments: [
    '(Sp PosArg)* (Sp KwArg)* (!(Sp PosArg))^arg_order',
    '(Sp ArgComment)* (Sp PosArg (Sp ArgComment)*)* (Sp KwArg (Sp ArgComment)*)* (!(Sp PosArg))^arg_order'
  ],
  ArgValue: ['StringLit / ExprCtx / ReservedBracket / InlineCommand(0) / Word'],
  KeywordArgument: ['Word Eq ArgValue']
};
// PegModelTest.generated_word_special and generated_word_ordinary_total cover
// both outcomes for every input of this exact canonical Word production.
const wordAst = ast?.rules.find(rule => rule.name === 'Word');
const wordFullyProved = word === shapes.Word[1] &&
  wordAst?.params.length === 0 && wordAst.templateParams.length === 0 &&
  wordAst.alts.length === 2 && wordAst.alts.every(alt =>
    alt.action?.trim() === '()' && alt.constructor === null &&
    alt.items.every(item => item.bind === null));
// PegModelTest.generated_mul_choice_total covers the guarded operators and
// the slash fallback on every input, including ** and %% boundaries.
const mulOpAst = ast?.rules.find(rule => rule.name === 'MulOp');
const mulOpFullyProved = rule('MulOp') === "'*' !'*' / '/' / '%' !'%'" &&
  mulOpAst?.params.length === 0 && mulOpAst.templateParams.length === 0 &&
  mulOpAst.alts.length === 3 && mulOpAst.alts.every(alt =>
    alt.action?.trim() === '()' && alt.constructor === null &&
    alt.items.every(item => item.bind === null));
// PegModelTest.generated_keyword_total covers all ordered keyword literals
// followed by the identifier-character boundary check.
const keywordAst = ast?.rules.find(rule => rule.name === 'Keyword');
const keywordFullyProved = rule('Keyword') === "('true' / 'false' / 'nil') ![a-z0-9_]" &&
  keywordAst?.params.length === 0 && keywordAst.templateParams.length === 0 &&
  keywordAst.alts.length === 1 && keywordAst.alts[0].items.length === 2 &&
  keywordAst.alts[0].items.every(item => item.bind === null) &&
  keywordAst.alts[0].action?.trim() === '()' && keywordAst.alts[0].constructor === null;
// PegModelTest.generated_block_command_start proves the @ + lowercase
// branch and preserves the actual SetDeclarationStart fallback result.
const blockCommandStartAst = ast?.rules.find(rule => rule.name === 'BlockCommandStart');
const blockCommandStartFullyProved = rule('BlockCommandStart') === "'@' [a-z] / SetDeclarationStart" &&
  blockCommandStartAst?.params.length === 0 && blockCommandStartAst.templateParams.length === 0 &&
  blockCommandStartAst.alts.length === 2 && blockCommandStartAst.alts.every(alt =>
    alt.action?.trim() === '()' && alt.constructor === null &&
    alt.items.every(item => item.bind === null));
// PegModelTest.generated_skip_all proves that .* consumes every input to EOF.
const skipAllAst = ast?.rules.find(rule => rule.name === 'SkipAll');
const skipAllFullyProved = rule('SkipAll') === '.*' &&
  skipAllAst?.params.length === 0 && skipAllAst.templateParams.length === 0 &&
  skipAllAst.alts.length === 1 && skipAllAst.alts[0].items.length === 1 &&
  skipAllAst.alts[0].items[0].bind === null &&
  skipAllAst.alts[0].action?.trim() === '()' && skipAllAst.alts[0].constructor === null;
// PegModelTest.generated_skip_line proves consumption up to the next newline.
const skipLineAst = ast?.rules.find(rule => rule.name === 'SkipLine');
const skipLineFullyProved = rule('SkipLine') === String.raw`(![\n] .)*` &&
  skipLineAst?.params.length === 0 && skipLineAst.templateParams.length === 0 &&
  skipLineAst.alts.length === 1 && skipLineAst.alts[0].items.length === 1 &&
  skipLineAst.alts[0].items[0].bind === null &&
  skipLineAst.alts[0].action?.trim() === '()' && skipLineAst.alts[0].constructor === null;
// PegModelTest.generated_code_line composes the scan with a required Nl.
const codeLineAst = ast?.rules.find(rule => rule.name === 'CodeLine');
const codeLineFullyProved = rule('CodeLine') === String.raw`(![\n] .)* Nl` &&
  codeLineAst?.params.length === 0 && codeLineAst.templateParams.length === 0 &&
  codeLineAst.alts.length === 1 && codeLineAst.alts[0].items.length === 2 &&
  codeLineAst.alts[0].items.every(item => item.bind === null) &&
  codeLineAst.alts[0].action?.trim() === '()' && codeLineAst.alts[0].constructor === null;
// ReservedBracketTotal.generated_reserved_total proves the canonical reference
// for every input: [! throws the reserved label; every other prefix misses.
const reservedBracketAst = ast?.rules.find(rule => rule.name === 'ReservedBracket');
const reservedBracketFullyProved = rule('ReservedBracket') === "&'[!' (&{ False } '[!')^reserved" &&
  reservedBracketAst?.params.length === 0 && reservedBracketAst.templateParams.length === 0 &&
  reservedBracketAst.alts.length === 1 && reservedBracketAst.alts[0].items.length === 2 &&
  reservedBracketAst.alts[0].items.every(item => item.bind === null) &&
  reservedBracketAst.alts[0].action?.trim() === '()' &&
  reservedBracketAst.alts[0].constructor === null;
// PrefixBoundaryTotal proves these two canonical references for every input.
// The same two-item theorem handles both a required class and a boundary class.
const numberOpenAst = ast?.rules.find(rule => rule.name === 'NumberOpen');
const numberOpenFullyProved = rule('NumberOpen') === "'##' [0-9]" &&
  numberOpenAst?.params.length === 0 && numberOpenAst.templateParams.length === 0 &&
  numberOpenAst.alts.length === 1 && numberOpenAst.alts[0].items.length === 2 &&
  numberOpenAst.alts[0].items.every(item => item.bind === null) &&
  numberOpenAst.alts[0].action?.trim() === '()' && numberOpenAst.alts[0].constructor === null;
const setIdentAst = ast?.rules.find(rule => rule.name === 'SetIdent');
const setIdentFullyProved = rule('SetIdent') === String.raw`'set' ![a-z0-9\-]` &&
  setIdentAst?.params.length === 0 && setIdentAst.templateParams.length === 0 &&
  setIdentAst.alts.length === 1 && setIdentAst.alts[0].items.length === 2 &&
  setIdentAst.alts[0].items.every(item => item.bind === null) &&
  setIdentAst.alts[0].action?.trim() === '()' && setIdentAst.alts[0].constructor === null;
// ThrowingPrefixTotal proves both lookahead-then-label and
// literal-then-label errors for every input. ReservedBracket shares the former.
const tooDeepAst = ast?.rules.find(rule => rule.name === 'TooDeep');
const tooDeepFullyProved = rule('TooDeep') === "&'#' (&{ False } '#')^heading_level" &&
  tooDeepAst?.params.length === 0 && tooDeepAst.templateParams.length === 0 &&
  tooDeepAst.alts.length === 1 && tooDeepAst.alts[0].items.length === 2 &&
  tooDeepAst.alts[0].items.every(item => item.bind === null) &&
  tooDeepAst.alts[0].action?.trim() === '()' && tooDeepAst.alts[0].constructor === null;
const badBreakAst = ast?.rules.find(rule => rule.name === 'BadBreak');
const badBreakFullyProved = rule('BadBreak') === String.raw`'\\' (&{ False })^hard_break` &&
  badBreakAst?.params.length === 0 && badBreakAst.templateParams.length === 0 &&
  badBreakAst.alts.length === 1 && badBreakAst.alts[0].items.length === 2 &&
  badBreakAst.alts[0].items.every(item => item.bind === null) &&
  badBreakAst.alts[0].action?.trim() === '()' && badBreakAst.alts[0].constructor === null;
const literalRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 &&
  rule.alts.length === 1 && rule.alts[0].items.length === 1 &&
  rule.alts[0].items[0].bind === null && rule.alts[0].items[0].expr.tag === 'lit' &&
  rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null);
const literalNames = new Set(literalRules.map(rule => rule.name));
const badBracketAst = ast?.rules.find(rule => rule.name === 'BadBracket');
const badBracketFullyProved = rule('BadBracket') === '&LBr (&{ False } LBr)^bracket' &&
  rule('LBr') === "'['" && literalNames.has('LBr') && badBracketAst?.params.length === 0 &&
  badBracketAst.templateParams.length === 0 && badBracketAst.alts.length === 1 &&
  badBracketAst.alts[0].items.length === 2 &&
  badBracketAst.alts[0].items.every(item => item.bind === null) &&
  badBracketAst.alts[0].action?.trim() === '()' && badBracketAst.alts[0].constructor === null;
// EscapeTotal.literal_not_class_any proves the three-item sequence for any
// literal and class. Its generated_reserved_body_escape_shape ties the nested
// ReservedBracketBody branch to the exported canonical AST.
function provedEscapeItems(items) {
  return items.length === 3 && items.every(item => item.bind === null) &&
    items[0].expr.tag === 'lit' && items[1].expr.tag === 'not' &&
    items[1].expr.expr.tag === 'class' && items[2].expr.tag === 'any';
}
const backslashAst = ast?.rules.find(rule => rule.name === 'Backslash');
const backslashFullyProved = rule('Backslash') === String.raw`'\\' &'\n'` &&
  backslashAst?.params.length === 0 && backslashAst.templateParams.length === 0 &&
  backslashAst.alts.length === 1 && backslashAst.alts[0].items.length === 2 &&
  backslashAst.alts[0].items.every(item => item.bind === null) &&
  backslashAst.alts[0].action?.trim() === '()' && backslashAst.alts[0].constructor === null;
function provedReservedOrdinary(items) {
  return items.length === 2 && items.every(item => item.bind === null) &&
    items[0].expr.tag === 'not' && items[0].expr.expr.tag === 'class' &&
    items[0].expr.expr.written === String.raw`[\[\]\\\n]` && items[1].expr.tag === 'any';
}
const escapeAst = ast?.rules.find(rule => rule.name === 'Escape');
const escapeFullyProved = rule('Escape') === String.raw`'\\' ![\n] .` &&
  escapeAst?.params.length === 0 && escapeAst.templateParams.length === 0 &&
  escapeAst.alts.length === 1 && provedEscapeItems(escapeAst.alts[0].items) &&
  escapeAst.alts[0].action?.trim() === '()' && escapeAst.alts[0].constructor === null;
const classPlusRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 &&
  rule.alts.length === 1 && rule.alts[0].items.length === 1 &&
  rule.alts[0].items[0].bind === null && rule.alts[0].items[0].expr.tag === 'plus' &&
  rule.alts[0].items[0].expr.expr.tag === 'class' &&
  rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null);
const classPlusNames = new Set(classPlusRules.map(rule => rule.name));
const optionalRefRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 &&
  rule.alts.length === 1 && rule.alts[0].items.length === 1 &&
  rule.alts[0].items[0].bind === null && rule.alts[0].items[0].expr.tag === 'opt' &&
  rule.alts[0].items[0].expr.expr.tag === 'ref' &&
  rule.alts[0].items[0].expr.expr.args.length === 0 &&
  classPlusNames.has(rule.alts[0].items[0].expr.expr.name) &&
  rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null);
const optionalRefNames = new Set(optionalRefRules.map(rule => rule.name));
const aliasRules = (ast?.rules ?? []).filter(rule =>
  stringSupported && rule.params.length === 0 && rule.templateParams.length === 0 &&
  rule.alts.length === 1 && rule.alts[0].items.length === 1 &&
  rule.alts[0].items[0].bind === null && rule.alts[0].items[0].expr.tag === 'ref' &&
  rule.alts[0].items[0].expr.name === 'StringLit' &&
  rule.alts[0].items[0].expr.args.length === 0 &&
  rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null);
const orderedLiteralRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 && rule.alts.length > 1 &&
  rule.alts.every(alt => alt.items.length === 1 && alt.items[0].bind === null &&
    alt.items[0].expr.tag === 'lit' && alt.action?.trim() === '()' && alt.constructor === null));
const orderedLiteralNames = new Set(orderedLiteralRules.map(rule => rule.name));
// PegModelTest.interpreted_ref_choices proves first success/error for any
// ordered list of single references. Referenced productions are checked on
// their own and are not discharged by this classifier.
const orderedRefRules = (ast?.rules ?? []).filter(rule =>
  rule.templateParams.length === 0 && rule.alts.length > 0 &&
  rule.alts.every(alt => alt.items.length === 1 && alt.items[0].bind === null &&
    alt.items[0].expr.tag === 'ref' && alt.action?.trim() === '()' && alt.constructor === null));
const orderedRefNames = new Set(orderedRefRules.map(rule => rule.name));
// PegModelTest.generated_newline_or_eof proves this exact choice for any
// parameter environment. The enclosing alternatives still need proofs.
function provedNlEofChoice(expr) {
  if (!literalNames.has('Nl') || expr.tag !== 'choice' || expr.alts.length !== 2 ||
      expr.alts.some(items => items.length !== 1)) return false;
  const [[nl], [eof]] = expr.alts;
  return nl?.bind === null && nl.expr.tag === 'ref' && nl.expr.name === 'Nl' && nl.expr.args.length === 0 &&
    eof?.bind === null && eof.expr.tag === 'not' && eof.expr.expr.tag === 'any';
}
// PegModelTest.newline_or_eof covers this direct literal form in RowBreak.
function provedLiteralNlEofChoice(expr) {
  if (expr.tag !== 'choice' || expr.alts.length !== 2 ||
      expr.alts.some(items => items.length !== 1)) return false;
  const [[nl], [eof]] = expr.alts;
  return nl?.bind === null && nl.expr.tag === 'lit' && nl.expr.value === '\n' &&
    nl.expr.written === "'\\n'" && eof?.bind === null && eof.expr.tag === 'not' &&
    eof.expr.expr.tag === 'any';
}
// PegModelTest.class_lookahead_or_eof covers any character class in this form.
function provedClassLookaheadOrEof(expr) {
  if (expr.tag !== 'choice' || expr.alts.length !== 2 ||
      expr.alts.some(items => items.length !== 1)) return false;
  const [[hit], [eof]] = expr.alts;
  return hit?.bind === null && hit.expr.tag === 'and' && hit.expr.expr.tag === 'class' &&
    eof?.bind === null && eof.expr.tag === 'not' && eof.expr.expr.tag === 'any';
}
const lineLeavesProved = classPlusNames.has('Ws') && rule('Ws') === '[ \\t]+' &&
  literalNames.has('Nl') && rule('Nl') === "'\\n'";
const blankRule = ast?.rules.find(rule => rule.name === 'BlankLine');
const blankLineProved = lineLeavesProved && blankRule?.params.length === 0 && blankRule.templateParams.length === 0 &&
  blankRule.alts.length === 2 && blankRule.alts.every(alt => alt.action?.trim() === '()' && alt.constructor === null) &&
  describeItems(blankRule.alts[0].items) === 'Ws? Nl' && describeItems(blankRule.alts[1].items) === 'Ws !.';
const paraRule = ast?.rules.find(rule => rule.name === 'ParaEnd');
const paraEndProved = blankLineProved && paraRule?.params.length === 0 && paraRule.templateParams.length === 0 &&
  paraRule.alts.length === 2 && paraRule.alts.every(alt => alt.action?.trim() === '()' && alt.constructor === null) &&
  describeItems(paraRule.alts[0].items) === 'Nl (BlankLine / !.)' && describeItems(paraRule.alts[1].items) === '!.';
const spUsesWs = optionalRefNames.has('Sp') && rule('Sp') === 'Ws?';
const listMarkersProved = literalNames.has('BulletMark') && rule('BulletMark') === "'-'" &&
  literalNames.has('OrderedMark') && rule('OrderedMark') === "'+'";
const indentRule = ast?.rules.find(rule => rule.name === 'Ind');
const indentFullyProved = indentRule?.params.length === 1 && indentRule.params[0] === 'n' &&
  indentRule.templateParams.length === 0 && indentRule.alts.length === 2 &&
  describeItems(indentRule.alts[0].items) === '&{ n == 0 }' &&
  describeItems(indentRule.alts[1].items) === "' ' Ind(n - 1)" &&
  indentRule.alts.every(alt => alt.action?.trim() === '()' && alt.constructor === null);
const textRuns = new Map([
  ['Text', "(![\\[\\\\\\n] !'%%' !NumberOpen .)+"],
  ['NumberBody', "(![#\\n\\[\\]|\\\\] !'%%' .)+"],
  ['SlotText', "(![\\[\\\\\\n|\\]] !'%%' !NumberOpen .)+"],
  ['CellText', "(![\\[\\\\\\n|] !'%%' !NumberOpen .)+"],
]);
function singleUnitRuleMatches(rule, expected) {
  return rule?.params.length === 0 && rule.templateParams.length === 0 && rule.alts.length === 1 &&
    rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null &&
    describeItems(rule.alts[0].items) === expected;
}
const numberBodyProved = singleUnitRuleMatches(ast?.rules.find(r => r.name === 'NumberBody'), textRuns.get('NumberBody'));
const attributedBranches = ['Heading', 'BulletList', 'OrderedList', 'DefList', 'Table', 'CodeBlock', 'Paragraph'];
const blockBranches = ['BadIndent', 'OrphanDef', 'ReservedBlock', 'BlockGroup', ...attributedBranches];
const blockDispatch = new Map([
  ['AttributedBlock', '(' + attributedBranches.map(name => name + '(ind)').join(' / ') + ')'],
  ['Block', '(' + blockBranches.map(name => name + '(ind)').join(' / ') + ')^block'],
]);
const indentedLabels = new Map([
  ['BadIndent', 'Ind(ind) &[ \\t] (&{ False } [ \\t])^indent'],
  ['OrphanDef', "Ind(ind) &'=:' (&{ False } '=:')^def_orphan"],
  ['ReservedBlock', "Ind(ind) &'@!' (&{ False } '@!')^reserved"],
]);
if (!fragment && ast) {
  for (const rule of ast.rules) {
    if (lineLeavesProved && rule.params.length === 0 && rule.templateParams.length === 0 &&
        rule.alts.every(alt => alt.action?.trim() === '()' && alt.constructor === null)) {
      if (rule.name === 'BlankLine' && blankLineProved) continue;
      if (rule.name === 'BlankLines' && blankLineProved && rule.alts.length === 1 &&
          describeItems(rule.alts[0].items) === 'BlankLine+') continue;
      if (rule.name === 'ParaEnd' && paraEndProved) continue;
      if ((rule.name === 'Comment' || rule.name === 'ProofComment') && paraEndProved && rule.alts.length === 1) {
        const opening = rule.name === 'Comment' ? "'%%'" : "'%%='";
        if (describeItems(rule.alts[0].items) === opening + " (!'%%' !ParaEnd .)* ('%%')^comment_close") continue;
      }
      if (rule.name === 'EOL' && spUsesWs &&
          rule.alts.length === 1 && describeItems(rule.alts[0].items) === 'Sp (Nl / !.)') continue;
    }
    if (textRuns.has(rule.name) && (rule.name === 'NumberBody' || numberOpenFullyProved) &&
        singleUnitRuleMatches(rule, textRuns.get(rule.name))) continue;
    if (rule.name === 'NumberShorthand' && numberOpenFullyProved && numberBodyProved &&
        singleUnitRuleMatches(ast.rules.find(r => r.name === 'NumberMark'), "'##'") &&
        singleUnitRuleMatches(rule, '&NumberOpen NumberMark NumberBody NumberMark?')) continue;
    if (rule.name === 'ExprIdent' && rule.params.length === 0 && rule.templateParams.length === 0 &&
        rule.alts.length === 1 && rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null &&
        describeItems(rule.alts[0].items) === '[a-zA-Z_] [a-zA-Z0-9_]*') continue;
    if (rule.name === 'ListMark' && listMarkersProved && rule.params.length === 1 && rule.params[0] === 'ordered' &&
        rule.templateParams.length === 0 && rule.alts.length === 2 &&
        rule.alts.every(alt => alt.action?.trim() === '()' && alt.constructor === null) &&
        describeItems(rule.alts[0].items) === '&{ ordered == 0 } BulletMark' &&
        describeItems(rule.alts[1].items) === '&{ ordered == 1 } OrderedMark') continue;
    if (blockDispatch.has(rule.name) && rule.params.length === 1 && rule.params[0] === 'ind' &&
        rule.templateParams.length === 0 && rule.alts.length === 1 && rule.alts[0].action?.trim() === '()' &&
        rule.alts[0].constructor === null && describeItems(rule.alts[0].items) === blockDispatch.get(rule.name)) continue;
    if (indentedLabels.has(rule.name) && rule.params.length === 1 && rule.params[0] === 'ind' &&
        rule.templateParams.length === 0 && rule.alts.length === 1 && rule.alts[0].action?.trim() === '()' &&
        rule.alts[0].constructor === null && describeItems(rule.alts[0].items) === indentedLabels.get(rule.name) &&
        indentFullyProved) continue;
    if (rule.name === 'Ind' && indentFullyProved) continue;
    if (rule.name === 'StringLit' && stringSupported && alternatives[0] === escape &&
        rule.params.length === 0 && rule.templateParams.length === 0 && rule.alts.length === 1 &&
        describeItems(rule.alts[0].items) === string && rule.alts[0].action?.trim() === '()' &&
        rule.alts[0].constructor === null) continue;
    if (wordFullyProved && rule.name === 'Word') continue;
    if (mulOpFullyProved && rule.name === 'MulOp') continue;
    if (keywordFullyProved && rule.name === 'Keyword') continue;
    if (blockCommandStartFullyProved && rule.name === 'BlockCommandStart') continue;
    if (skipAllFullyProved && rule.name === 'SkipAll') continue;
    if (skipLineFullyProved && rule.name === 'SkipLine') continue;
    if (codeLineFullyProved && rule.name === 'CodeLine') continue;
    if (reservedBracketFullyProved && rule.name === 'ReservedBracket') continue;
    if (numberOpenFullyProved && rule.name === 'NumberOpen') continue;
    if (setIdentFullyProved && rule.name === 'SetIdent') continue;
    if (tooDeepFullyProved && rule.name === 'TooDeep') continue;
    if (badBreakFullyProved && rule.name === 'BadBreak') continue;
    if (badBracketFullyProved && rule.name === 'BadBracket') continue;
    if (backslashFullyProved && rule.name === 'Backslash') continue;
    if (escapeFullyProved && rule.name === 'Escape') continue;
    if (literalNames.has(rule.name)) continue;
    if (classPlusNames.has(rule.name)) continue;
    if (optionalRefNames.has(rule.name)) continue;
    if (orderedLiteralNames.has(rule.name)) continue;
    if (orderedRefNames.has(rule.name)) continue;
    let index = 0;
    const report = (items, line) => {
      index++;
      errors.push(`unsupported ${rule.name} choice ${index} at ${input}:${line}: ${describeItems(items)}`);
    };
    for (const alt of rule.alts) {
      if (rule.name === 'RangeExpr' && rule.params.length === 0 && rule.templateParams.length === 0 &&
          alt === rule.alts[0] && alt.action?.trim() === '()' && alt.constructor === null &&
          describeItems(alt.items) === "&'...' (&{ False } '...')^range_end") continue;
      // ReferenceSequence.sequence proves propagation of success, failure and errors.
      // Direct left recursion uses seed growth in place of this sequence.
      if (rule.params.length === 0 && rule.templateParams.length === 0 &&
          alt.action?.trim() === '()' && alt.constructor === null && alt.items.length > 0 &&
          alt.items.every(item => item.bind === null && item.expr.tag === 'ref' && item.expr.args.length === 0) &&
          alt.items[0].expr.name !== rule.name) continue;
      // PrefixBoundaryTotal.marker_sequence covers both forms for any literal and class.
      if (rule.name === 'BlockStart' && rule.params.length === 0 && rule.templateParams.length === 0 &&
          alt.action?.trim() === '()' && alt.constructor === null &&
          alt.items.every(item => item.bind === null) && alt.items[0]?.expr.tag === 'lit' &&
          (alt.items.length === 1 || (alt.items.length === 2 && alt.items[1].expr.tag === 'class'))) continue;
      if (rule.name === 'SkippedReserved' && alt === rule.alts[2] &&
          rule.params.length === 0 && rule.templateParams.length === 0 &&
          describeItems(alt.items) === "'@!' (![\\n] .)*" &&
          alt.action?.trim() === '()' && alt.constructor === null) continue;
      // generated_skipped_literal_shapes identifies these alternatives;
      // sequence_literal_total gives their result for every input suffix.
      if (rule.name === 'SkippedReserved' && rule.params.length === 0 &&
          rule.templateParams.length === 0 && alt.items.length === 1 &&
          alt.items[0].bind === null && alt.items[0].expr.tag === 'lit' &&
          ((alt === rule.alts[1] && alt.items[0].expr.written === "'[!'") ||
           (alt === rule.alts[3] && alt.items[0].expr.written === "'..'")) &&
          alt.action?.trim() === '()' && alt.constructor === null) continue;
      report(alt.items, alt.line);
    }
    for (const alt of rule.alts) {
      for (const item of alt.items) {
        nestedChoices(item.expr, items => report(items, items[0]?.line ?? item.line));
      }
    }
  }
}
for (const [name, rhs] of Object.entries(productions)) {
  if (!shapes[name].includes(rhs)) errors.push(`${name}: unsupported production ${JSON.stringify(rhs)}`);
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}

const sha = createHash('sha256').update(grammar).digest('hex');
const leanString = value => JSON.stringify(value).replaceAll('\\u2028', '\\u2028').replaceAll('\\u2029', '\\u2029');
const leanList = (values, emit) => `[${values.map(emit).join(', ')}]`;
const leanOpt = value => value === null ? 'none' : `some ${leanString(value)}`;
function leanExpr(expr) {
  const child = () => leanExpr(expr.expr);
  switch (expr.tag) {
    case 'lit': return `.lit ${leanString(expr.value)} ${leanString(expr.written)}`;
    case 'class': return `.charClass ${leanList(expr.ranges, ([lo, hi]) => `(${lo}, ${hi})`)} ${leanString(expr.written)}`;
    case 'any': return '.any';
    case 'ref': return `.ref ${leanString(expr.name)} ${leanList(expr.args, leanString)}`;
    case 'choice': return `.choice ${leanList(expr.alts, alt => leanList(alt, leanItem))}`;
    case 'star': return `.star (${child()})`;
    case 'plus': return `.plus (${child()})`;
    case 'opt': return `.opt (${child()})`;
    case 'and': return `.andPred (${child()})`;
    case 'not': return `.notPred (${child()})`;
    case 'capture': return `.capture (${child()})`;
    case 'label': return `.label (${child()}) ${leanString(expr.name)}`;
    case 'pred': return `.semanticPred ${expr.positive} ${leanString(expr.source)}`;
    case 'template': return `.template ${leanString(expr.name)} ${leanList(expr.children, leanExpr)} ${leanList(expr.args, leanString)}`;
    case 'discard': return `.discard (${child()})`;
    default: throw new Error(`unknown peg-hs expression ${expr.tag}`);
  }
}
function leanItem(item) {
  const child = leanExpr(item.expr);
  return item.bind === null ? child : `.bind (some ${leanString(item.bind)}) (${child})`;
}
const pegRules = ast.rules.map((rule, index) => `private def pegRule${index} : PegModel.Rule := { name := ${leanString(rule.name)}, line := ${rule.line}, params := ${leanList(rule.params, leanString)}, templateParams := ${leanList(rule.templateParams, leanString)}, resultType := ${leanString(rule.type)}, alts := ${leanList(rule.alts, alt => `{ line := ${alt.line}, items := ${leanList(alt.items, leanItem)}, action := ${leanOpt(alt.action)}, constructor := ${leanOpt(alt.constructor)} }`)} }`);
writeFileSync(output, [
  'import PegModel',
  'namespace Generated',
  `def sourceSha256 : String := ${leanString(sha)}`,
  `def stringLitEscapeFirst : Bool := ${alternatives[0] === escape}`,
  `def wordForbidden : List Char := ${leanString(forbidden?.join('') ?? '').replace(/^/, '(').replace(/$/, ').toList')}`,
  `def literalProductions : List (String × String × String) := ${leanList(literalRules, rule => `(${leanString(rule.name)}, ${leanString(rule.alts[0].items[0].expr.value)}, ${leanString(rule.alts[0].items[0].expr.written)})`)}`,
  `def classPlusProductions : List (String × List (Nat × Nat) × String) := ${leanList(classPlusRules, rule => { const cls = rule.alts[0].items[0].expr.expr; return `(${leanString(rule.name)}, ${leanList(cls.ranges, ([lo, hi]) => `(${lo}, ${hi})`)}, ${leanString(cls.written)})`; })}`,
  `def optionalRefProductions : List (String × String) := ${leanList(optionalRefRules, rule => `(${leanString(rule.name)}, ${leanString(rule.alts[0].items[0].expr.expr.name)})`)}`,
  `def aliasProductions : List (String × String) := ${leanList(aliasRules, rule => `(${leanString(rule.name)}, ${leanString(rule.alts[0].items[0].expr.name)})`)}`,
  `def orderedLiteralProductions : List (String × List (String × String)) := ${leanList(orderedLiteralRules, rule => `(${leanString(rule.name)}, ${leanList(rule.alts, alt => `(${leanString(alt.items[0].expr.value)}, ${leanString(alt.items[0].expr.written)})`)})`)}`,
  'def sourceRules : List (String × String) := [',
  ...sourceRules.map(([name, rhs]) => `  (${leanString(name)}, ${leanString(rhs)}),`),
  ']',
  ...Object.entries(productions).map(([name, rhs]) => `def ${name[0].toLowerCase() + name.slice(1)}Production : String := ${leanString(rhs)}`),
  ...pegRules,
  `def pegRules : List PegModel.Rule := [${ast.rules.map((_, index) => `pegRule${index}`).join(', ')}]`,
  `def pegGrammar : PegModel.Grammar := { start := ${leanString(ast.start)}, tokens := ${leanList(ast.tokens, leanString)}, trivia := ${leanList(ast.trivia, leanString)}, inline := ${leanList(ast.inline, leanString)}, rules := pegRules }`,
  'end Generated',
  ''
].join('\n'));
