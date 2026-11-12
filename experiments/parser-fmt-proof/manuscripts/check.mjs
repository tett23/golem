import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { performance } from 'node:perf_hooks';
import { bodies, listingCases, withoutPositions } from './corpus.mjs';

const [bound = '1', only] = process.argv.slice(2);
const limit = Number(bound);
assert.ok(Number.isSafeInteger(limit) && limit >= 0);
const dir = mkdtempSync(join(tmpdir(), 'golem-round-trip-'));
const file = join(dir, 'source.gm');
const started = performance.now();
let tested = 0;

function* cases() {
  yield '';
  for (const word of bodies(limit)) {
    if (word) yield word + '\n';
  }
  for (const word of ['เก', 'لا', 'می‌روم', 'SrcSpan {first}', 'before @2..4 after']) yield word + '\n';
  yield '[f "x"%%甲%%%%乙%%key=y]\n';
  yield '[= 1+%%注%%2]\n';
  yield* listingCases();
}

// Compare each comment's text and its position in the non-trivia token
// sequence. Token widths may change when fmt separates adjacent arguments.
function comments(cst) {
  const found = [];
  let index = 0;
  for (const line of cst.split('\n')) {
    const token = /^\s*(K\w+)@\d+\.\.\d+ (.*)$/.exec(line);
    if (!token) continue;
    if (token[1] === 'KComment') found.push([index, token[2]]);
    else if (!['KWhitespace', 'KNewline'].includes(token[1])) index++;
  }
  return found;
}

function run(...args) {
  return execFileSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
}

try {
  for (const [index, input] of Array.from(cases()).entries()) {
    if (only !== undefined && Number(only) !== index) continue;
    tested++;
    writeFileSync(file, input);
    try {
      const ast = () => withoutPositions(run('inspect', file, '--as', 'ast'));
      const positions = () => comments(run('inspect', file, '--as', 'cst'));
      const expectedAst = ast();
      const expectedComments = positions();
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
      writeFileSync(join(path, 'reproduce.txt'), `node experiments/parser-fmt-proof/manuscripts/check.mjs ${bound} ${index}\n`);
      writeFileSync(join(path, 'error.txt'), error.message + '\n');
      console.error(index, error.message);
      process.exitCode = 1;
    }
  }
  assert.ok(tested);
  console.log(`${tested} cases at cluster bound ${limit} in ${((performance.now()-started)/1000).toFixed(2)} seconds`);
} finally {
  rmSync(dir, { recursive: true, force: true });
}
