import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {delimitedCases,delimitedModelProgram,expectedDelimited} from './delimited-cases.mjs';

export function verifyDelimited({here,work,lean,growthEnv,original,model,generator}) {
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
  for(const name of ['PosArgDelimitedMetadata','PosArgDelimited','PosArgDelimitedBoundary']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const output=compile(name,name!=='PosArgDelimitedBoundary');
    if(name==='PosArgDelimitedBoundary')assert.match(output,/48 delimited word captures, ASTs and recognizers agree; 4 lexical limits retained/);
  }
  writeFileSync(join(work,'DelimitedFixtures.lean'),delimitedModelProgram());
  const rows=compile('DelimitedFixtures').trim().split('\n').map(JSON.parse);
  assert.equal(rows.length,48);assert.equal(delimitedCases.length,48);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedDelimited(delimitedCases[index])));
  const source=readFileSync(join(here,'PosArgTrace.lean'),'utf8');
  const boundary=readFileSync(join(here,'PosArgDelimitedBoundary.lean'),'utf8');assert.equal(boundary.split('#eval').length,2);
  writeFileSync(join(work,'DelimitedRuntime.lean'),'import PosArgTrace\nopen PegModel CstWrapper\n#eval'+boundary.split('#eval')[1]);
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
      compile('DelimitedRuntime',false,true,/missing delimited word capture|wrong delimited word capture/);
    }finally{
      writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgDelimited',true);
    }
  }
  const grammar=join(work,'DelimitedNative.hpeg'),input=join(work,'DelimitedNative.gm');
  const entry=text=>text.replace('%syntax\n','%syntax\n%entry DelimitedProbe\n%token DelimitedRest\n')+
    '\nDelimitedProbe :: ()\nDelimitedProbe <- PosArg DelimitedRest { () }\nDelimitedRest :: ()\nDelimitedRest <- .* { () }\n';
  const native=text=>{
    writeFileSync(input,text);const result=spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','DelimitedProbe','--format','cst',grammar,input],
      {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'delimited-native-cache')}});
    assert.equal(result.error,undefined);assert.equal(result.signal,null);assert.equal(typeof result.status,'number');return result;
  };
  const token=(text,name)=>{
    const match=text.match(new RegExp('^\\s+'+name+'@\\d+\\.\\.\\d+ (.+)$','m'));assert.ok(match,text);return JSON.parse(match[1]);
  };
  writeFileSync(grammar,entry(original));
  for(const row of delimitedCases){
    const result=native(row.word+row.suffix);assert.equal(result.status,0,result.stdout+result.stderr);
    assert.match(result.stdout,/^\s+Argument@/m);assert.doesNotMatch(result.stdout,/^\s+PosArg@/m);
    assert.equal(token(result.stdout,'Word'),row.word);assert.equal(token(result.stdout,'DelimitedRest'),row.suffix);
  }
  for(const rejected of ['cinder=7','**[7]']){
    const result=native(rejected);assert.ok(result.status>0);assert.match(result.stderr,/^1:1: parse error/m);
  }
  const splat=native('*[7]');assert.equal(splat.status,0,splat.stdout+splat.stderr);assert.match(splat.stdout,/^\s+SplatArgument@/m);
  const longer=native('cinder[7]');assert.equal(longer.status,0,longer.stdout+longer.stderr);assert.equal(token(longer.stdout,'Word'),'cinder');assert.equal(token(longer.stdout,'DelimitedRest'),'[7]');
  const controls=join(work,'delimited-metadata');mkdirSync(controls,{recursive:true});
  copyFileSync(join(work,'PegModel.olean'),join(controls,'PegModel.olean'));copyFileSync(join(here,'PosArgDelimitedMetadata.lean'),join(controls,'PosArgDelimitedMetadata.lean'));
  const sourceMutants=[
    ['Eq',text=>text.replace("Eq <- '=' { () }","Eq <- '==' { () }")],
    ['Splat',text=>text.replace("Splat <- '**[' { () } / '*[' { () }","Splat <- '**[' { () } / '*' { () }")],
  ];
  for(const [name,mutate] of sourceMutants){
    const changed=mutate(original);assert.notEqual(changed,original,name);const path=join(controls,name+'.hpeg');writeFileSync(path,changed);
    const emitted=spawnSync(process.execPath,[generator,'--fragment',path,join(controls,'Generated.lean')],{encoding:'utf8'});assert.equal(emitted.status,0,emitted.stdout+emitted.stderr);
    compile('Generated',true,false,undefined,controls);compile('PosArgDelimitedMetadata',false,true,undefined,controls);
    writeFileSync(grammar,entry(changed));const result=native(name==='Eq'?'cinder=7':'* 1]');assert.equal(result.status,0,result.stdout+result.stderr);
    if(name==='Eq')assert.equal(token(result.stdout,'Word'),'cinder');
    else{assert.match(result.stdout,/^\s+SplatArgument@/m);assert.doesNotMatch(result.stdout,/^\s+Argument@/m);}
  }
  const metadataOnly=model.split('\n').map(line=>/name := "(?:Eq|Splat)"/.test(line)?line.replaceAll(/line := ([0-9]+)/g,(_,n)=>'line := '+(Number(n)+17)):line).join('\n');
  assert.notEqual(metadataOnly,model);writeFileSync(join(controls,'Generated.lean'),metadataOnly);
  compile('Generated',true,false,undefined,controls);compile('PosArgDelimitedMetadata',false,false,undefined,controls);
  return {modules:3,fixtures:48,nativeFixtures:48,semanticMutants:3,sourceMutants:2,runtimeWitnesses:3,scopeControls:4,metadataControls:1};
}
