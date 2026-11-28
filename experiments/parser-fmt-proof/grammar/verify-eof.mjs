import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {eofWords,eofModelProgram,expectedEof} from './eof-cases.mjs';

export function verifyEof({here,work,lean,growthEnv,original,generator}) {
  const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals|tactic 'change' failed|tactic 'rfl' failed/,directory=work)=>{
    const result=spawnSync(lean,output?['-o',join(directory,name+'.olean'),join(directory,name+'.lean')]:[join(directory,name+'.lean')],
      {...growthEnv,cwd:directory,env:{...growthEnv.env,LEAN_PATH:directory}});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(typeof result.status,'number');
    const text=result.stdout+result.stderr;
    if(reject){
      assert.notEqual(result.status,0,name);assert.match(text,pattern);
      assert.doesNotMatch(text,/maximum number of heartbeats|unknown package|unknown module|unknown identifier|unknown constant|invalid field|unexpected token|unterminated|failed to synthesize/);
    }else{
      assert.equal(result.status,0,text);assert.doesNotMatch(text,/sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for(const name of ['WordEof','ArgumentEof','PosArgEof','EofBoundary']) {
    copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const output=compile(name,name!=='EofBoundary');
    if(name==='EofBoundary')assert.match(output,/12 PosArg EOF captures, ASTs and recognizers agree/);
  }
  writeFileSync(join(work,'EofFixtures.lean'),eofModelProgram());
  const rows=compile('EofFixtures').trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,12);assert.equal(eofWords.length,12);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedEof(eofWords[index])));
  const source=readFileSync(join(here,'PosArgTrace.lean'),'utf8');
  const boundary=readFileSync(join(here,'EofBoundary.lean'),'utf8');assert.equal(boundary.split('#eval').length,2);
  writeFileSync(join(work,'EofRuntime.lean'),'import PosArgTrace\n#eval'+boundary.split('#eval')[1]);
  for(const [name,before,after] of [
    ['Dispatch','name == "Argument"','name == "ArgValue"'],
    ['Wrapper','KeywordTrace.finish grammar "PosArg"','KeywordTrace.finish grammar "Argument"'],
    ['GuardCapture','(fun result => result.map fun rest => (rest,[]))','(fun result => result.map fun rest => (rest,[Element.token "Guard" []]))'],
  ]){
    const changed=source.replace(before,after);assert.notEqual(changed,source,name);
    try{
      writeFileSync(join(work,'PosArgTrace.lean'),changed);compile('PosArgTrace',true);
      compile('PosArgEof',false,true);
      compile('EofRuntime',false,true,/different EOF positional capture|missing EOF positional capture/);
    }finally{
      writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgEof',true);
    }
  }
  const grammar=join(work,'EofNative.hpeg'),input=join(work,'EofNative.gm');
  const entry=text=>text.replace('%syntax\n','%syntax\n%entry EofProbe\n')+
    '\nEofProbe :: ()\nEofProbe <- PosArg !. { () }\n';
  const native=text=>{
    writeFileSync(input,text);const result=spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','EofProbe','--format','cst',grammar,input],
      {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'eof-native-cache')}});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(typeof result.status,'number');return result;
  };
  writeFileSync(grammar,entry(original));
  for(const word of eofWords){
    const result=native(word);assert.equal(result.status,0,result.stdout+result.stderr);
    assert.match(result.stdout,/^\s+Argument@/m);assert.doesNotMatch(result.stdout,/^\s+PosArg@/m);
    const match=result.stdout.match(/^\s+Word@\d+\.\.\d+ (.+)$/m);assert.ok(match,result.stdout);
    assert.equal(JSON.parse(match[1]),word);
  }
  for(const text of ['','%%','%%=discard']){
    const result=native(text);assert.equal(result.status,1,result.stdout+result.stderr);
    assert.match(result.stderr,/^1:1: (?:parse error|expected )/m);
  }
  const changed=original.replace("Splat <- '**[' { () } / '*[' { () }","Splat <- '**[' { () } / '*' { () }");
  assert.notEqual(changed,original);
  writeFileSync(grammar,entry(changed));
  const altered=native('*');assert.equal(altered.status,1,altered.stdout+altered.stderr);assert.match(altered.stderr,/^1:2: expected /m);

  // Isolate the actual recognizer from unrelated closed regression proofs.
  // A complete mutant rebuild already fails an older PegModelTest fixture;
  // this finite comparison is not a claim that the new general proof failed.
  for(const [name,text] of [['canonical',original],['mutant',changed]]){
    const directory=join(work,'eof-source-'+name);mkdirSync(directory,{recursive:true});
    copyFileSync(join(here,'PegModel.lean'),join(directory,'PegModel.lean'));
    const sourceFile=join(directory,'Golem.hpeg');writeFileSync(sourceFile,text);
    const emitted=spawnSync(process.execPath,[generator,'--fragment',sourceFile,join(directory,'Generated.lean')],{encoding:'utf8'});
    assert.equal(emitted.error,undefined);assert.equal(emitted.signal,null);assert.equal(emitted.status,0,emitted.stdout+emitted.stderr);
    assert.doesNotMatch(emitted.stderr,/^unsupported /m);
    compile('PegModel',true,false,undefined,directory);compile('Generated',true,false,undefined,directory);
    writeFileSync(join(directory,'EofSource.lean'),`import PegModel
import Generated
#eval show IO Unit from do
  let got := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "PosArg" []) ['*']
  match got with
  | .ok (some []) => IO.println "EOF Word '*' recognized"
  | other => throw (IO.userError s!"different EOF Word recognition {repr other}")
`);
    compile('EofSource',false,name==='mutant',/different EOF Word recognition Except\.error "label: expr"/,directory);
  }
  return {modules:4,fixtures:12,nativeFixtures:12,semanticMutants:3,sourceMutants:1,runtimeWitnesses:3,scopeControls:3,nativeMutationControls:1};
}
