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
      if (expr.alts.length > 1) expr.alts.forEach(visit);
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
const literalRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 &&
  rule.alts.length === 1 && rule.alts[0].items.length === 1 &&
  rule.alts[0].items[0].bind === null && rule.alts[0].items[0].expr.tag === 'lit' &&
  rule.alts[0].action?.trim() === '()' && rule.alts[0].constructor === null);
const literalNames = new Set(literalRules.map(rule => rule.name));
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
const aliasNames = new Set(aliasRules.map(rule => rule.name));
const orderedLiteralRules = (ast?.rules ?? []).filter(rule =>
  rule.params.length === 0 && rule.templateParams.length === 0 && rule.alts.length > 1 &&
  rule.alts.every(alt => alt.items.length === 1 && alt.items[0].bind === null &&
    alt.items[0].expr.tag === 'lit' && alt.action?.trim() === '()' && alt.constructor === null));
const orderedLiteralNames = new Set(orderedLiteralRules.map(rule => rule.name));
if (!fragment && ast) {
  for (const rule of ast.rules) {
    if (rule.name === 'StringLit' && stringSupported && rule.alts.length === 1) continue;
    if (literalNames.has(rule.name)) continue;
    if (classPlusNames.has(rule.name)) continue;
    if (optionalRefNames.has(rule.name)) continue;
    if (aliasNames.has(rule.name)) continue;
    if (orderedLiteralNames.has(rule.name)) continue;
    let index = 0;
    const report = (items, line) => {
      index++;
      errors.push(`unsupported ${rule.name} choice ${index} at ${input}:${line}: ${describeItems(items)}`);
    };
    for (const [rootIndex, alt] of rule.alts.entries()) {
      if (!(rule.name === 'Word' && shapes.Word.includes(word) && rootIndex === rule.alts.length - 1)) {
        report(alt.items, alt.line);
      }
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
