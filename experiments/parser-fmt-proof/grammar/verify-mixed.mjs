import assert from 'node:assert/strict';
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedMixed, mixedCases, mixedModelProgram } from './mixed-cases.mjs';

export function verifyMixed({ here, work, lean, growthEnv }) {
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
  const proofModules = ['MixedKeywords', 'MixedCanonical'];
  for (const name of proofModules) {
    if (join(here, name + '.lean') !== join(work, name + '.lean'))
      copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    compile(name, true);
  }
  if (join(here, 'MixedRegression.lean') !== join(work, 'MixedRegression.lean'))
    copyFileSync(join(here, 'MixedRegression.lean'), join(work, 'MixedRegression.lean'));
  compile('MixedRegression');
  writeFileSync(join(work, 'MixedFixtures.lean'), mixedModelProgram());
  const rows = compile('MixedFixtures').trim().split('\n').map(row => JSON.parse(row));
  assert.equal(rows.length, mixedCases.length);
  rows.forEach((row, index) => assert.deepEqual(row, expectedMixed(mixedCases[index])));
  const source = readFileSync(join(here, 'MixedKeywords.lean'), 'utf8');
  const mutants = [
    ['WordKind', 'some (.word value,after)', 'some (.string value,after)'],
    ['StringKind', '.string (StringRoundTrip.unescape spelling)', '.word (StringRoundTrip.unescape spelling)'],
    ['StringDecode', '.string (StringRoundTrip.unescape spelling)', '.string spelling'],
    ['Name', 'some ((name,value)::values)', 'some (([],value)::values)'],
    ['Tail', 'some ((name,value)::values)', 'some [(name,value)]'],
  ];
  for (const [name, before, after] of mutants) {
    const changed = source.replace(before, after);
    assert.notEqual(changed, source);
    writeFileSync(join(work, 'WrongMixed' + name + '.lean'), changed);
    compile('WrongMixed' + name, false, true);
  }
  return { modules: proofModules.length, semanticMutants: mutants.length, fixtures: mixedCases.length };
}
