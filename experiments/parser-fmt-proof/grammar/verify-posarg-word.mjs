import assert from 'node:assert/strict';
import {copyFileSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {posargWordCases,posargWordModelProgram,expectedPosargWord} from './posarg-word-cases.mjs';

export function verifyPosargWord({here,work,lean,growthEnv}) {
  const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals|tactic 'change' failed/)=>{
    const result=spawnSync(lean,output?['-o',join(work,name+'.olean'),join(work,name+'.lean')]:[join(work,name+'.lean')],
      {...growthEnv,cwd:work});
    const text=result.stdout+result.stderr;
    if(reject){
      assert.notEqual(result.status,0,name);assert.match(text,pattern);
      assert.doesNotMatch(text,/maximum number of heartbeats|unknown package|unknown module|invalid field|unknown identifier|unknown constant|unexpected token|unterminated|failed to synthesize/);
    }else{
      assert.equal(result.status,0,text);assert.doesNotMatch(text,/sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for(const name of ['PosArgWord','PosArgWordBoundary']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const output=compile(name,name==='PosArgWord');
    if(name==='PosArgWordBoundary')assert.match(output,/12 space-delimited word captures, ASTs and recognizer results agree/);
  }
  writeFileSync(join(work,'PosArgWordFixtures.lean'),posargWordModelProgram());
  const rows=compile('PosArgWordFixtures').trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,posargWordCases.length);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedPosargWord(posargWordCases[index])));
  const source=readFileSync(join(here,'PosArgTrace.lean'),'utf8');
  const boundary=readFileSync(join(here,'PosArgWordBoundary.lean'),'utf8');
  assert.equal(boundary.split('#eval').length,2);
  writeFileSync(join(work,'PosArgWordRuntime.lean'),'import PosArgTrace\nopen PegModel CstWrapper\n#eval'+boundary.split('#eval')[1]);
  const mutants=[
    ['WrongDispatch','name == "Argument"','name == "ArgValue"'],
    ['WrongWrapper','KeywordTrace.finish grammar "PosArg"','KeywordTrace.finish grammar "Argument"'],
    ['CapturedGuard','(fun result => result.map fun rest => (rest,[]))','(fun result => result.map fun rest => (rest,[Element.token "Guard" []]))'],
  ];
  for(const [name,before,after] of mutants) {
    const changed=source.replace(before,after);assert.notEqual(changed,source,name);
    try {
      writeFileSync(join(work,'PosArgTrace.lean'),changed);compile('PosArgTrace',true);
      compile('PosArgWord',false,true);
      compile('PosArgWordRuntime',false,true,/missing space-delimited word capture|incorrect space-delimited word capture/);
    }finally{
      writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgWord',true);
    }
  }
  return {modules:2,fixtures:posargWordCases.length,semanticMutants:mutants.length,runtimeWitnesses:mutants.length};
}
