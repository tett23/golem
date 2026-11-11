import { readFileSync, writeFileSync } from 'node:fs';

const [grammarPath, outputPath] = process.argv.slice(2);
const grammar = readFileSync(grammarPath, 'utf8');
function rhs(name) {
  const candidates = grammar.split('\n').filter(line => line.startsWith(name + ' <- '));
  if (candidates.length !== 1) throw new Error('Expected one rule for ' + name);
  return candidates[0].slice((name + ' <- ').length).replace(/ \{ \(\) \}$/, '');
}
const string = rhs('StringLit');
const outer = /^'"' \((.*)\)\* '"'$/;
if (!outer.test(string)) throw new Error('Unsupported StringLit: ' + string);
const choices = string.match(outer)[1].split(' / ');
const escape = String.raw`'\\' .`;
const char = String.raw`!["\n] .`;
if (choices.length !== 2 || !choices.includes(escape) || !choices.includes(char)) {
  throw new Error('Unsupported StringLit alternatives: ' + choices);
}
writeFileSync(outputPath, [
  'namespace Generated',
  'def stringLitEscapeFirst : Bool := ' + (choices[0] === escape),
  'end Generated', ''
].join('\n'));
