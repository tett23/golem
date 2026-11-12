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
  for (const [index, [input, expectedComments = [], expectedStructure]] of Array.from(cases()).entries()) {
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
      assert.deepEqual(positions(), expectedComments);
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
