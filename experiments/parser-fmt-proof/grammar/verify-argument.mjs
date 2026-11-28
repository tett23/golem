import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {argumentCases,expectedArgument,argumentModelProgram} from './argument-cases.mjs';

export function verifyArgument({here,work,lean,growthEnv,original,model,generator}) {
  const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals/,directory=work)=>{
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
  for(const name of ['ArgumentMetadata','ArgumentTrace','ArgumentTraceRegression']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const out=compile(name,name!=='ArgumentTraceRegression');
    if(name==='ArgumentTraceRegression')assert.match(out,/positional word and quoted captures retain their node and kind/);
  }
  writeFileSync(join(work,'ArgumentFixtures.lean'),argumentModelProgram());
  const rows=compile('ArgumentFixtures').trim().split(String.fromCharCode(10)).map(JSON.parse);
  assert.equal(rows.length,argumentCases.length);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedArgument(argumentCases[index])));
  const source=readFileSync(join(here,'ArgumentTrace.lean'),'utf8');
  const mutants=[
    ['InlineNode','KeywordTrace.body grammar "Argument"','KeywordTrace.body {grammar with inline := "Argument"::grammar.inline} "Argument"'],
    ['WrongDispatch','name == "ArgValue"','name == "StringLit"'],
    ['WrongValue','.map Argument.positional','.map (fun _ => Argument.positional (.word []))'],
  ];
  for(const [name,before,after] of mutants) {
    const changed=source.replace(before,after);assert.notEqual(changed,source,name);
    writeFileSync(join(work,'WrongArgument'+name+'.lean'),changed);
    compile('WrongArgument'+name,false,true);
    try {
      const definitions=changed.slice(0,changed.indexOf('\ntheorem '))+'\nend ArgumentTrace\n';
      writeFileSync(join(work,'ArgumentTrace.lean'),definitions);compile('ArgumentTrace',true);
      compile('ArgumentTraceRegression',false,true,/(missing|wrong) positional argument (capture|lowering)/);
    }finally{
      writeFileSync(join(work,'ArgumentTrace.lean'),source);compile('ArgumentTrace',true);
    }
  }
  assert.match(compile('ArgumentTraceRegression'),/positional word and quoted captures retain their node and kind/);
  const controls=join(work,'argument-metadata');mkdirSync(controls);
  copyFileSync(join(work,'PegModel.olean'),join(controls,'PegModel.olean'));
  copyFileSync(join(here,'ArgumentMetadata.lean'),join(controls,'ArgumentMetadata.lean'));
  const grammar=join(work,'Argument-native.hpeg');const input=join(work,'Argument-native.gm');
  const entry=text=>text.replace('%syntax\n','%syntax\n%entry ArgumentProbe\n')+'\nArgumentProbe :: ()\nArgumentProbe <- Argument .* { () }\n';
  const native=text=>{
    writeFileSync(input,text);
    return spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','ArgumentProbe','--format','cst',grammar,input],
      {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'argument-native-cache')}});
  };
  writeFileSync(grammar,entry(original));
  const normal=native('"value"');assert.equal(normal.status,0,normal.stdout+normal.stderr);assert.match(normal.stdout,/^\s+Argument@/m);
  const expression=native('[=1 + 2]');assert.equal(expression.status,0,expression.stdout+expression.stderr);
  assert.match(expression.stdout,/ExprCtx@/);
  writeFileSync(join(work,'ArgumentScope.lean'),'import ArgumentTrace\n#eval show IO Unit from do\n'+
    '  match ArgumentTrace.read Generated.pegGrammar 512 "[=1 + 2]".toList with\n'+
    '  | .error "unmodeled non-token capture" => IO.println "expression capture remains outside this increment"\n'+
    '  | got => throw (IO.userError s!"unexpected expression capture {repr got}")\n');
  assert.match(compile('ArgumentScope'),/expression capture remains outside this increment/);
  const sourceMutants=[
    ['InlineArgument','%syntax\n','%syntax\n%inline Argument\n'],
    ['WrongChild','Argument <- ArgValue','Argument <- StringLit'],
  ];
  for(const [name,before,after] of sourceMutants) {
    const changed=original.replace(before,after);assert.notEqual(changed,original,name);
    const changedPath=join(controls,name+'.hpeg');writeFileSync(changedPath,changed);
    const emitted=spawnSync(process.execPath,[generator,'--fragment',changedPath,join(controls,'Generated.lean')],{encoding:'utf8'});
    assert.equal(emitted.status,0,emitted.stdout+emitted.stderr);
    compile('Generated',true,false,undefined,controls);
    compile('ArgumentMetadata',false,true,/type mismatch|unsolved goals|decide.*false/s,controls);
    writeFileSync(grammar,entry(changed));
    if(name==='InlineArgument'){
      const result=native('"value"');assert.equal(result.status,0,result.stdout+result.stderr);assert.doesNotMatch(result.stdout,/^\s+Argument@/m);
    }else{
      const control=native('"value"');assert.equal(control.status,0,control.stdout+control.stderr);
      const rejected=native('word');assert.notEqual(rejected.status,0,rejected.stdout+rejected.stderr);
    }
  }
  const metadataOnly=model.split(String.fromCharCode(10)).map(line=>line.includes('name := "Argument"')
    ?line.replaceAll(/line := ([0-9]+)/g,(_,value)=>'line := '+(Number(value)+17)):line).join(String.fromCharCode(10));
  assert.notEqual(metadataOnly,model);writeFileSync(join(controls,'Generated.lean'),metadataOnly);
  compile('Generated',true,false,undefined,controls);compile('ArgumentMetadata',false,false,undefined,controls);
  return {modules:2,fixtures:argumentCases.length,semanticMutants:mutants.length,runtimeWitnesses:mutants.length,
    sourceMutants:sourceMutants.length,metadataControls:1,nativeShapeCounterexamples:sourceMutants.length,nativeScopeControls:1};
}
