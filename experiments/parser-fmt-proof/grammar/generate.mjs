import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';

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
const sourceRules = [];
let activeRule = false;
for (const line of grammar.split('\n')) {
  const start = line.match(/^([A-Za-z][A-Za-z0-9]*) <- (.*)$/);
  if (start) {
    sourceRules.push([start[1], start[2]]);
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
// Preserve every ordered-choice branch, including choices in nested groups.
// Quotes, character classes and semantic actions do not contain PEG choices.
function choices(rhs) {
  const branches = [];
  const stack = [{ start: 0, slashes: [] }];
  let quote = false;
  let charClass = false;
  let actionDepth = 0;
  let escaped = false;
  for (let i = 0; i < rhs.length; i++) {
    const char = rhs[i];
    if (quote || charClass) {
      if (escaped) escaped = false;
      else if (char === '\\') escaped = true;
      else if ((quote && char === "'") || (charClass && char === ']')) {
        quote = false;
        charClass = false;
      }
    } else if (actionDepth) {
      if (char === '{') actionDepth++;
      if (char === '}') actionDepth--;
    } else if (char === "'") {
      quote = true;
    } else if (char === '[') {
      charClass = true;
    } else if (char === '{') {
      actionDepth = 1;
    } else if (char === '(') {
      stack.push({ start: i + 1, slashes: [] });
    } else if (char === ')') {
      const group = stack.pop();
      if (!group || stack.length === 0) throw new Error(`unbalanced PEG group in ${rhs}`);
      if (group.slashes.length) {
        const boundaries = [group.start, ...group.slashes.map(index => index + 1), i];
        for (let j = 0; j + 1 < boundaries.length; j++) {
          const end = j < group.slashes.length ? group.slashes[j] : boundaries[j + 1];
          branches.push(rhs.slice(boundaries[j], end).replace(/\s+/g, ' ').trim());
        }
      }
    } else if (char === '/') {
      stack[stack.length - 1].slashes.push(i);
    }
  }
  if (quote || charClass || actionDepth || stack.length !== 1) throw new Error(`unclosed PEG term in ${rhs}`);
  const root = stack[0];
  if (root.slashes.length) {
    const boundaries = [0, ...root.slashes.map(index => index + 1), rhs.length];
    for (let j = 0; j + 1 < boundaries.length; j++) {
      const end = j < root.slashes.length ? root.slashes[j] : boundaries[j + 1];
      branches.push(rhs.slice(boundaries[j], end).replace(/\s+/g, ' ').trim());
    }
  } else {
    branches.push(rhs.replace(/\s+/g, ' ').trim());
  }
  return branches;
}

if (!fragment) {
  for (const [name, rhs] of sourceRules) {
    if (name === 'StringLit') continue;
    if (name === 'Word') {
      const normalized = rhs.replaceAll(' { () }', '').replace(/\s+/g, ' ').trim();
      const special = normalized.indexOf(' / ');
      if (special >= 0) errors.push(`unsupported Word choice 1: ${normalized.slice(0, special)}`);
      continue;
    }
    try {
      choices(rhs).forEach((choice, index) => errors.push(`unsupported ${name} choice ${index + 1}: ${choice}`));
    } catch (error) {
      errors.push(`unsupported ${name} choice ?: ${error.message}`);
    }
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
if (alternatives.length !== 2 || !alternatives.includes(escape) || !alternatives.includes(ordinary)) {
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
for (const [name, rhs] of Object.entries(productions)) {
  if (!shapes[name].includes(rhs)) errors.push(`${name}: unsupported production ${JSON.stringify(rhs)}`);
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exit(1);
}

const sha = createHash('sha256').update(grammar).digest('hex');
const leanString = value => JSON.stringify(value).replaceAll('\\u2028', '\\u2028').replaceAll('\\u2029', '\\u2029');
writeFileSync(output, [
  'namespace Generated',
  `def sourceSha256 : String := ${leanString(sha)}`,
  `def stringLitEscapeFirst : Bool := ${alternatives[0] === escape}`,
  `def wordForbidden : List Char := ${leanString(forbidden?.join('') ?? '').replace(/^/, '(').replace(/$/, ').toList')}`,
  'def sourceRules : List (String × String) := [',
  ...sourceRules.map(([name, rhs]) => `  (${leanString(name)}, ${leanString(rhs)}),`),
  ']',
  ...Object.entries(productions).map(([name, rhs]) => `def ${name[0].toLowerCase() + name.slice(1)}Production : String := ${leanString(rhs)}`),
  'end Generated',
  ''
].join('\n'));
