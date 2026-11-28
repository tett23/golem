import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {argumentCases,expectedArgument,argumentModelProgram} from './argument-cases.mjs';

export function verifyPosArg({here,work,lean,growthEnv,original,model,generator}) {
  const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals|tactic 'change' failed/,directory=work)=>{
    const result=spawnSync(lean,output?['-o',join(directory,name+'.olean'),join(directory,name+'.lean')]:[join(directory,name+'.lean')],
      {...growthEnv,cwd:directory,env:{...growthEnv.env,LEAN_PATH:directory===work?growthEnv.env.LEAN_PATH:directory}});
    const text=result.stdout+result.stderr;
    if(reject){
      assert.notEqual(result.status,0,name);assert.match(text,pattern);
      assert.doesNotMatch(text,/maximum number of heartbeats|unknown package|unknown module|invalid field|unknown identifier|unknown constant|invalid dotted identifier|unexpected token|unterminated|failed to synthesize/);
    }else{
      assert.equal(result.status,0,text);assert.doesNotMatch(text,/sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for(const name of ['PosArgMetadata','PosArgTrace','PosArgQuoted','PosArgTraceRegression']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const output=compile(name,name!=='PosArgTraceRegression');
    if(name==='PosArgTraceRegression')assert.match(output,/quoted captures and values agree; guards and splat scope retained/);
  }
  const fixtures=argumentModelProgram().replace('import ArgumentTrace','import PosArgQuoted')
    .replaceAll('ArgumentTrace.read Generated.pegGrammar','PosArgTrace.read Generated.pegGrammar')
    .replace('(.ref "Argument" [])','(.ref "PosArg" [])');
  writeFileSync(join(work,'PosArgFixtures.lean'),fixtures);
  const rows=compile('PosArgFixtures').trim().split(String.fromCharCode(10)).map(JSON.parse);
  assert.equal(rows.length,argumentCases.length);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedArgument(argumentCases[index])));
  const source=readFileSync(join(here,'PosArgTrace.lean'),'utf8');
  const mutants=[
    ['WrongDispatch','name == "Argument"','name == "ArgValue"'],
    ['WrongWrapper','KeywordTrace.finish grammar "PosArg"','KeywordTrace.finish grammar "Argument"'],
    ['CapturedGuard','(fun result => result.map fun rest => (rest,[]))',
      '(fun result => result.map fun rest => (rest,[Element.token "Guard" []]))'],
  ];
  for(const [name,before,after] of mutants) {
    const changed=source.replace(before,after);assert.notEqual(changed,source,name);
    try{
      writeFileSync(join(work,'PosArgTrace.lean'),changed);compile('PosArgTrace',true);
      compile('PosArgQuoted',false,true);
      compile('PosArgTraceRegression',false,true,/missing guarded positional capture|wrong guarded positional capture/);
    }finally{
      writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgQuoted',true);
    }
  }
  // Removing guards changes inputs outside the quoted theorem's domain.
  // The quoted theorem still succeeds; the explicit rejected-prefix checks fail.
  const guardBefore='(recognizeEnv grammar [] fuel (.notPred predicate) input).map\n      (fun result => result.map fun rest => (rest,[]))';
  const guardAfter='Except.ok (some (input,[]))';
  const unguarded=source.replace(guardBefore,guardAfter);assert.notEqual(unguarded,source);
  try{
    writeFileSync(join(work,'PosArgTrace.lean'),unguarded);compile('PosArgTrace',true);
    compile('PosArgQuoted',true);
    compile('PosArgTraceRegression',false,true,/accepted a non-positional prefix/);
  }finally{
    writeFileSync(join(work,'PosArgTrace.lean'),source);compile('PosArgTrace',true);compile('PosArgQuoted',true);
  }
  const controls=join(work,'posarg-metadata');mkdirSync(controls);
  copyFileSync(join(work,'PegModel.olean'),join(controls,'PegModel.olean'));
  copyFileSync(join(here,'PosArgMetadata.lean'),join(controls,'PosArgMetadata.lean'));
  const grammar=join(work,'PosArg-native.hpeg');const input=join(work,'PosArg-native.gm');
  const entry=text=>text.replace('%syntax\n','%syntax\n%entry PosArgProbe\n')+'\nPosArgProbe :: ()\nPosArgProbe <- PosArg .* { () }\n';
  const native=text=>{
    writeFileSync(input,text);
    return spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','PosArgProbe','--format','cst',grammar,input],
      {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'posarg-native-cache')}});
  };
  writeFileSync(grammar,entry(original));
  const baseline=native('"value"');assert.equal(baseline.status,0,baseline.stdout+baseline.stderr);
  assert.match(baseline.stdout,/^\s+Argument@/m);assert.doesNotMatch(baseline.stdout,/^\s+PosArg@/m);
  for(const rejected of ['key=value','%% note','**[1]']) {
    const result=native(rejected);assert.notEqual(result.status,0,result.stdout+result.stderr);
  }
  const scope=native('*[1]');assert.equal(scope.status,0,scope.stdout+scope.stderr);assert.match(scope.stdout,/SplatArgument@/);
  const sourceMutants=[
    ['PositiveComment',text=>text.replace("PosArg <- !'%%'","PosArg <- &'%%'")
      .replace("        / !'%%' !(Word Eq) !Splat","        / &'%%' !(Word Eq) !Splat")],
    ['NodeInsteadOfInline',text=>text.replace('%inline PosArg\n','')],
    ['MissingArgumentNode',text=>text.replace("/ !'%%' !(Word Eq) !Splat Argument", "/ !'%%' !(Word Eq) !Splat ArgValue")
      .replace('%syntax\n','%syntax\n%entry Argument\n')],
  ];
  for(const [name,mutate] of sourceMutants) {
    const changed=mutate(original);assert.notEqual(changed,original,name);
    const changedPath=join(controls,name+'.hpeg');writeFileSync(changedPath,changed);
    const emitted=spawnSync(process.execPath,[generator,'--fragment',changedPath,join(controls,'Generated.lean')],{encoding:'utf8'});
    assert.equal(emitted.status,0,emitted.stdout+emitted.stderr);
    compile('Generated',true,false,undefined,controls);
    compile('PosArgMetadata',false,true,/type mismatch|unsolved goals|decide.*false/s,controls);
    writeFileSync(grammar,entry(changed));const result=native('"value"');
    if(name==='PositiveComment')assert.notEqual(result.status,0,result.stdout+result.stderr);
    else{
      assert.equal(result.status,0,result.stdout+result.stderr);
      if(name==='NodeInsteadOfInline')assert.match(result.stdout,/^\s+PosArg@/m);
      else assert.doesNotMatch(result.stdout,/^\s+Argument@/m);
    }
  }
  const metadataOnly=model.split(String.fromCharCode(10)).map(line=>line.includes('name := "PosArg"')
    ?line.replaceAll(/line := ([0-9]+)/g,(_,value)=>'line := '+(Number(value)+17)):line).join(String.fromCharCode(10));
  assert.notEqual(metadataOnly,model);writeFileSync(join(controls,'Generated.lean'),metadataOnly);
  compile('Generated',true,false,undefined,controls);compile('PosArgMetadata',false,false,undefined,controls);
  return {modules:2,fixtures:argumentCases.length,semanticMutants:mutants.length,sourceMutants:sourceMutants.length,
    runtimeWitnesses:mutants.length+1,metadataControls:1,nativeShapeCounterexamples:sourceMutants.length,
    nativeScopeControls:1,nativeRejectedPrefixes:3,quotedOnlyMutationControls:1};
}
