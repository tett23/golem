import assert from 'node:assert/strict';
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedToken, tokenCases, tokenModelProgram } from './token-cases.mjs';
export function verifyToken({ here, work, lean, growthEnv }) {
  const compile = (name, output = false, reject = false) => {
    const file = join(work, name + '.lean');
    const result = spawnSync(lean, output ? ['-o', join(work, name + '.olean'), file] : [file], growthEnv);
    const text = result.stdout + result.stderr;
    if (reject) {
      assert.notEqual(result.status, 0, name);
      assert.match(text, /type mismatch|unsolved goals/);
      assert.doesNotMatch(text, /maximum number of heartbeats|unknown package|unknown module|invalid field|unknown identifier|unknown constant|invalid dotted identifier|unexpected token|unterminated|failed to synthesize/);
    } else {
      assert.equal(result.status, 0, text);
      assert.doesNotMatch(text, /sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for (const name of ['TokenLowering', 'TokenLoweringRegression']) {
    if (join(here,name + '.lean') !== join(work,name + '.lean'))
      copyFileSync(join(here,name + '.lean'),join(work,name + '.lean'));
    const result = compile(name, name !== 'TokenLoweringRegression');
    if (name === 'TokenLoweringRegression') assert.match(result, /raw token to AST decoded string matched/);
  }
  writeFileSync(join(work,'TokenFixtures.lean'),tokenModelProgram());
  const rows = compile('TokenFixtures').trim().split('\n').map(row => JSON.parse(row));
  assert.equal(rows.length,tokenCases.length);
  rows.forEach((row,index) => assert.deepEqual(row,expectedToken(tokenCases[index])));
  const source = readFileSync(join(here,'TokenLowering.lean'),'utf8');
  const mutants = [
    ['WordKind','some ⟨.word,chars⟩','some ⟨.quoted,chars⟩'],
    ['QuotedKind','some ⟨.quoted,chars⟩','some ⟨.word,chars⟩'],
    ['EqValue','some ⟨.equals,chars⟩','some ⟨.word,chars⟩'],
    ['Suffix','(pair.1,value pair.2)','([],value pair.2)'],
    ['NoValue','(pair.1,value pair.2)','(pair.1,none)'],
    ['Reverse','elements.filterMap','elements.reverse.filterMap'],
    ['DropFirst','elements.filterMap','(elements.drop 1).filterMap'],
  ];
  for (const [name,before,after] of mutants) {
    const changed=source.replace(before,after);
    assert.notEqual(changed,source);
    writeFileSync(join(work,'WrongToken'+name+'.lean'),changed);
    compile('WrongToken'+name,false,true);
  }
  return { modules:1,semanticMutants:mutants.length,fixtures:tokenCases.length };
}
