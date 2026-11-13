import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { bodies, listingCases, nestedInlineCases, orderedSubsets, withoutPositions } from './corpus.mjs';

const [bound = '1', only = 'all', depth = '0'] = process.argv.slice(2);
const limit = Number(bound);
assert.ok(Number.isSafeInteger(limit) && limit >= 0);
const nesting = Number(depth);
assert.ok(Number.isSafeInteger(nesting) && nesting >= 0);
const dir = mkdtempSync(join(tmpdir(), 'golem-round-trip-'));
const file = join(dir, 'source.gm');
const started = performance.now();
let tested = 0;

function* cases() {
  yield [''];
  for (const word of bodies(limit)) {
    if (word) yield [word + '\n'];
  }
  for (const word of ['เก', 'لا', 'می‌روم', 'SrcSpan {first}', 'before @2..4 after']) yield [word + '\n'];
  const pair = index => [[index, '"%%甲%%"'], [index, '"%%乙%%"']];
  yield ['[f "x"%%甲%%%%乙%%key=y]\n', pair(3)];
  yield ['[= 1+%%注%%2]\n', [[3, '"%%注%%"']]];
  for (const listing of listingCases()) {
    yield [listing, listing.includes('%%') ? pair(6) : []];
  }
  for (const nested of nestedInlineCases(nesting)) yield [nested];
  yield ['鰍\\ \n', [], /Paragraph \[Text "鰍", Escaped ' '\]/u];
  // CodeBlock <- Fence Lang? Arguments ... . Check the parser's chosen
  // node, optional language and ordered arguments against the input.
  for (const lang of ['', 'hs']) {
    for (const keys of orderedSubsets(['k', 'm', 'n'])) {
      const fields = keys.map(key => ' ' + key + '="' + key + '"').join('');
      const expectedKeys = keys.map(key => 'Keyword \\("' + key + '"\\) \\(StringLit "' + key + '"\\)');
      const language = lang ? '\\(?Just "hs"\\)?' : 'Nothing';
      const inline = '\\[' + expectedKeys.join(', ') + '\\]';
      const vertical = expectedKeys.map(entry => '- ' + entry).join('\\s+');
      const argumentsPattern = vertical ? '(?:' + inline + '|' + vertical + ')' : inline;
      const ast = new RegExp('CodeBlock\\s+' + language + '\\s+' + argumentsPattern + '\\s+\\["x"\\]');
      yield ['```' + lang + fields + '\nx\n```\n', [], ast];
    }
  }
  yield ['鰍%%甲%%%%=乙%%𠮷%%=丙%%%%丁%%末\n',
    [[1, '"%%甲%%"'], [1, '"%%=乙%%"'], [2, '"%%=丙%%"'], [2, '"%%丁%%"']]];

  for (let level = 1; level <= 6; level++) {
    const mark = '#'.repeat(level) + ' ';
    yield [mark + '\n', [], new RegExp('Heading ' + level + ' \\[\\]')];
    yield [mark + '甲\n', [], new RegExp('Heading ' + level + ' \\[Text "甲"\\]')];
    yield [mark + '%%注%%乙\n', [[1, '"%%注%%"']],
      new RegExp('Heading ' + level + ' \\[Text "乙"\\]')];
  }
  yield [String.raw`[f "a\"b" "\\" "" "x\y"]` + '\n', [],
    /Positional \(StringLit "a\\"b"\)\s+- Positional \(StringLit "\\\\"\)\s+- Positional \(StringLit ""\)\s+- Positional \(StringLit "xy"\)/u];
  yield ['[= 8-3-2*4/2]\n', [],
    /EBinary\s+Sub\s+EBinary Sub \(ENat 8\) \(ENat 3\)\s+EBinary Div \(EBinary Mul \(ENat 2\) \(ENat 4\)\) \(ENat 2\)/u];
  yield ['- x\n  - y\n    - z\n', [],
    /BulletList\s+- - Paragraph \[Text "x"\]\s+- BulletList\s+- - Paragraph \[Text "y"\]\s+- BulletList \[\[Paragraph \[Text "z"\]\]\]/u];
  yield ['a\n \t\nb\n \t', [], /fileBlocks = \[Paragraph \[Text "a"\], Paragraph \[Text "b"\]\]/u];
  yield ['\n\n', [], /fileBlocks = \[\]/u];
  yield ['\n \t\n\na\n\n\n', [], /fileBlocks = \[Paragraph \[Text "a"\]\]/u];
  yield ['\t\n \n \t', [], /fileBlocks = \[\]/u];
  for (const [outer, inner, parent, child] of [
    ['-', '+', 'BulletList', 'OrderedList'], ['+', '-', 'OrderedList', 'BulletList'],
  ]) {
    const input = outer + ' x\n  ' + inner + ' a\n  ' + inner + ' b\n';
    const shape = parent + '\\s+- - Paragraph \\[Text "x"\\]\\s+- ' + child +
      '\\s+\\[\\[Paragraph \\[Text "a"\\]\\], \\[Paragraph \\[Text "b"\\]\\]\\]';
    yield [input, [], new RegExp(shape)];
  }
  yield ['[= _A09.x2+Z_]\n', [],
    /EBinary Add \(EVar \["_A09", "x2"\]\) \(EVar \["Z_"\]\)/u];
  yield ['- x\n   p\n\ny\n', [],
    /BulletList \[\[Paragraph \[Text "x", SoftBreak, Text " p"\]\]\]\s+- Paragraph \[Text "y"\]/u];
  for (const opening of ['%%', '%%=']) {
    const comment = opening + 'open\nclose%%';
    yield ['a' + comment + 'b\n', [[1, JSON.stringify(comment)]]];
  }
  // Formatting inserts a KText space before the slot and cell separators.
  yield ['a%z##12##b%%note%%c\n[f: x##3##|y%%n%%z]\n\n|a##4##|b%%c%%d|\n|---|---|\n|u|v|\n',
    [[5, '"%%note%%"'], [15, '"%%n%%"'], [24, '"%%c%%"']],
    /Text "a%z".*NumberShorthand "##12##".*Text "bc".*Command.*\[\[Text "x", NumberShorthand "##3##"\], \[Text "yz"\]\].*Table.*\[\[Text "a", NumberShorthand "##4##"\], \[Text "bd"\]\]/su,
    [[5, '"%%note%%"'], [16, '"%%n%%"'], [26, '"%%c%%"']]];
  yield ['a##1\n', [], /Paragraph \[Text "a", NumberShorthand "##1"\]/u];
  yield ['a##1#b\n', [], /Paragraph \[Text "a", NumberShorthand "##1", Text "#b"\]/u];
  yield ['a##x\n', [], /Paragraph \[Text "a##x"\]/u];
  yield ['a##１\n', [], /Paragraph \[Text "a##１"\]/u];
  yield ['a##1%%n%%b\n', [[3, '"%%n%%"']], /Paragraph \[Text "a", NumberShorthand "##1", Text "b"\]/u];
  yield ['[= -(2+3)**2<30]\n', [],
    /EBinary\s+OpLt\s+EUnary\s+Negate\s+EBinary Pow \(EBinary Add \(ENat 2\) \(ENat 3\)\) \(ENat 2\)\s+ENat 30/u];
  yield ['[= 8-3-2*6/3]\n', [],
    /EBinary\s+Sub\s+EBinary Sub \(ENat 8\) \(ENat 3\)\s+EBinary Div \(EBinary Mul \(ENat 2\) \(ENat 6\)\) \(ENat 3\)/u];
  yield ['[f *[xs] **[h]]\n', [],
    /SplatPositional \(EVar \["xs"\]\), SplatKeyword \(EVar \["h"\]\)/u];
  yield ['||x|\n|---|---|\n|y||\n', [],
    /Table \[AlignDefault, AlignDefault\] \[\[\], \[Text "x"\]\] \[\[\[Text "y"\], \[\]\]\]/u];
  yield ['[= {aa: 1, "bb": 2}]\n', [],
    /EHash \[\("aa", ENat 1\), \("bb", ENat 2\)\]/u];
  yield ['a\\\nb\n', [], /Paragraph \[Text "a", HardBreak, Text "b"\]/u];
  yield ['[f answer=ok]\n', [], /Keyword \("answer"\) \(Word "ok"\)/u];
}

// Compare each comment's text and its position in the non-trivia token
// sequence. Token widths may change when fmt separates adjacent arguments.
function comments(cst) {
  const found = [];
  let index = 0;
  for (const line of cst.split('\n')) {
    const token = /^\s*(K\w+)@\d+\.\.\d+ (.*)$/.exec(line);
    if (!token) continue;
    if (token[1] === 'KComment' || token[1] === 'KProofComment') {
      assert.equal(token[1], token[2].startsWith('"%%=') ? 'KProofComment' : 'KComment');
      found.push([index, token[2]]);
    } else if (!['KWhitespace', 'KNewline'].includes(token[1])) index++;
  }
  return found;
}

function run(...args) {
  return execFileSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

try {
  for (const [index, [input, expectedComments = [], expectedStructure, formattedComments = expectedComments]] of Array.from(cases()).entries()) {
    if (only !== 'all' && Number(only) !== index) continue;
    tested++;
    writeFileSync(file, input);
    try {
      const ast = () => withoutPositions(run('inspect', file, '--as', 'ast'));
      const positions = () => comments(run('inspect', file, '--as', 'cst'));
      const expectedAst = ast();
      if (expectedStructure) assert.match(expectedAst, expectedStructure);
      if (input.startsWith('@listing ')) {
        assert.match(expectedAst, /BlockCommand\s+\(?"listing"/u);
        assert.match(expectedAst, /Positional \(Word "x\.hs"\)/u);
        const keywords = [...expectedAst.matchAll(/Keyword \("([^"]+)"\) \(Word "([^"]+)"\)/gu)];
        const expected = input.trim().split(' ').filter(part => part.includes('='));
        assert.deepEqual(keywords.map(([, name, value]) => name + '=' + value), expected);
        assert.equal([...expectedAst.matchAll(/\bKeyword\b/gu)].length, expected.length);
      }
      assert.deepEqual(positions(), expectedComments);
      run('fmt', file);
      assert.equal(ast(), expectedAst);
      assert.deepEqual(positions(), formattedComments);
      const first = readFileSync(file);
      run('fmt', file);
      assert.deepEqual(readFileSync(file), first);
    } catch (error) {
      const path = join(process.env.ROUND_TRIP_FAILURES || 'round-trip-failures', 'manuscript-' + index);
      mkdirSync(path, { recursive: true });
      writeFileSync(join(path, 'original.gm'), input);
      writeFileSync(join(path, 'result.gm'), readFileSync(file));
      writeFileSync(join(path, 'reproduce.txt'), `node experiments/parser-fmt-proof/manuscripts/check.mjs ${bound} ${index}${nesting ? ` ${nesting}` : ''}\n`);
      writeFileSync(join(path, 'error.txt'), error.message + '\n');
      console.error(index, error.message);
      process.exitCode = 1;
    }
  }
  assert.ok(tested);
  console.log(`${tested} cases at cluster bound ${limit} and nesting depth ${nesting} in ${((performance.now()-started)/1000).toFixed(2)} seconds`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
