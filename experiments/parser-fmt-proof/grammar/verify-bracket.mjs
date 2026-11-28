import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {bracketCases,bracketModelProgram,expectedBracket} from './bracket-cases.mjs';

export function verifyBracket({here,work,lean,growthEnv,original,model,generator}) {
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
  for(const name of ['PosArgBracketBoundary']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const output=compile(name,name!=='PosArgBracketBoundary');
    if(name==='PosArgBracketBoundary')assert.match(output,/15 bracket word captures, ASTs and recognizers agree; 2 splat limits retained/);
  }
  writeFileSync(join(work,'BracketFixtures.lean'),bracketModelProgram());
  const rows=compile('BracketFixtures').trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,15);assert.equal(bracketCases.length,15);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedBracket(bracketCases[index])));
  const source=readFileSync(join(here,'PosArgTrace.lean'),'utf8');
  const boundary=readFileSync(join(here,'PosArgBracketBoundary.lean'),'utf8');assert.equal(boundary.split('#eval').length,2);
  writeFileSync(join(work,'BracketRuntime.lean'),'import PosArgTrace\nopen PegModel CstWrapper\n#eval'+boundary.split('#eval')[1]);
  const mutants=[
    ['Dispatch','name == "Argument"','name == "ArgValue"'],
    ['Wrapper','KeywordTrace.finish grammar "PosArg"','KeywordTrace.finish grammar "Argument"'],
    ['GuardCapture','(fun result => result.map fun rest => (rest,[]))','(fun result => result.map fun rest => (rest,[Element.token "Guard" []]))'],
  ];
  for(const [name,before,after] of mutants){
    const changed=source.replace(before,after);assert.notEqual(changed,source,name);
    try{
      writeFileSync(join(work,'PosArgTrace.lean'),changed);compile('PosArgTrace',true);
      compile('PosArgDelimited',false,true);
      compile('BracketRuntime',false,true,/missing bracket word capture|wrong bracket word capture/);
    }finally{
      writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgDelimited',true);
    }
  }
  const grammar=join(work,'BracketNative.hpeg'),input=join(work,'BracketNative.gm');
  const entry=text=>text.replace('%syntax\n','%syntax\n%entry BracketProbe\n%token BracketRest\n')+
    '\nBracketProbe :: ()\nBracketProbe <- PosArg BracketRest { () }\nBracketRest :: ()\nBracketRest <- .* { () }\n';
  const native=text=>{
    writeFileSync(input,text);const result=spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','BracketProbe','--format','cst',grammar,input],
      {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'bracket-native-cache')}});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(typeof result.status,'number');return result;
  };
  const token=(text,name)=>{
    const match=text.match(new RegExp('^\\s+'+name+'@\\d+\\.\\.\\d+ (.+)$','m'));assert.ok(match,text);return JSON.parse(match[1]);
  };
  writeFileSync(grammar,entry(original));
  for(const row of bracketCases){
    const result=native(row.word+row.suffix);assert.equal(result.status,0,result.stdout+result.stderr);
    assert.match(result.stdout,/^\s+Argument@/m);assert.doesNotMatch(result.stdout,/^\s+PosArg@/m);
    assert.equal(token(result.stdout,'Word'),row.word);assert.equal(token(result.stdout,'BracketRest'),row.suffix);
  }
  for(const rejected of ['**[7]']){
    const result=native(rejected);assert.ok(result.status>0);assert.match(result.stderr,/^1:1: parse error/m);
  }
  const splat=native('*[7]');assert.equal(splat.status,0,splat.stdout+splat.stderr);assert.match(splat.stdout,/^\s+SplatArgument@/m);
  const changed=original.replace("Splat <- '**[' { () } / '*[' { () }","Splat <- '**[' { () } / '*' { () }");
  assert.notEqual(changed,original);
  writeFileSync(grammar,entry(changed));
  const altered=native('***[7]');
  if(altered.status>0){assert.equal(altered.status,1);assert.match(altered.stderr,/^1:2: expected /m);}
  else assert.doesNotMatch(altered.stdout,/^\s+Word@\d+\.\.\d+ "\*\*\*"$/m);
  return {modules:1,fixtures:15,nativeFixtures:15,semanticMutants:3,runtimeWitnesses:3,scopeControls:2,nativeMutationControls:1};
}
