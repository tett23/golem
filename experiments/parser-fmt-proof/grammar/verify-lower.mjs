import assert from 'node:assert/strict';
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedLower, lowerCases, lowerModelProgram } from './lower-cases.mjs';

export function verifyLower({ here, work, lean, growthEnv }) {
  const compile = (name, output = false, reject = false) => {
    const file = join(work, name + '.lean');
    const result = spawnSync(lean, output ? ['-o', join(work, name + '.olean'), file] : [file], growthEnv);
    const text = result.stdout + result.stderr;
    if (reject) {
      assert.notEqual(result.status, 0, name);
      assert.match(text, /type mismatch|unsolved goals/);
      assert.doesNotMatch(text, /maximum number of heartbeats|unknown package|unknown module/);
    } else {
      assert.equal(result.status, 0, text);
      assert.doesNotMatch(text, /sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for (const name of ['KeywordLowering', 'KeywordLoweringRegression']) {
    if (join(here, name + '.lean') !== join(work, name + '.lean'))
      copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    const text = compile(name, name === 'KeywordLowering');
    if (name === 'KeywordLoweringRegression') assert.match(text, /CST keyword fields matched/);
  }
  writeFileSync(join(work, 'LowerFixtures.lean'), lowerModelProgram());
  const rows = compile('LowerFixtures').trim().split('\n').map(row => JSON.parse(row));
  assert.equal(rows.length, lowerCases.length);
  rows.forEach((row, index) => assert.deepEqual(row, expectedLower(lowerCases[index])));
  const source = readFileSync(join(here, 'KeywordLowering.lean'), 'utf8');
  const mutants = [
    ['Comment', ' || token.kind == .comment', ''],
    ['QuotedDecode', 'StringRoundTrip.unescape ((chars.drop 1).dropLast)', '((chars.drop 1).dropLast)'],
    ['WordKind', 'some (.word token.chars)', 'some (.string token.chars)'],
    ['StringKind', 'some (.string (unquote token.chars))', 'some (.word (unquote token.chars))'],
    ['Name', '(fun v => (name,v))', '(fun v => ([],v))'],
    ['Order', 'elements.filterMap lowerElement', '(elements.filterMap lowerElement).reverse'],
    ['Ignored', '| .ignored => none', '| .ignored => some ([],.word [])'],
    ['ProofComment', 'token.kind == .newline', 'token.kind == .newline || token.kind == .proofComment'],
  ];
  for (const [name, before, after] of mutants) {
    const changed = source.replace(before, after);
    assert.notEqual(changed, source);
    writeFileSync(join(work, 'WrongLower' + name + '.lean'), changed);
    compile('WrongLower' + name, false, true);
  }
  return { modules: 1, semanticMutants: mutants.length, fixtures: lowerCases.length };
}
