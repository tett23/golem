import assert from 'node:assert/strict';
import {copyFileSync,mkdirSync,readFileSync,writeFileSync} from 'node:fs';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import {traceCases,expectedTrace,traceModelProgram} from './trace-cases.mjs';

export function verifyKwArg({here,work,lean,growthEnv,original,model,generator}){
 const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals/,directory=work)=>{
  const file=join(directory,name+'.lean');
  const result=spawnSync(lean,output?['-o',join(directory,name+'.olean'),file]:[file],{...growthEnv,cwd:directory,env:{...growthEnv.env,LEAN_PATH:directory===work?growthEnv.env.LEAN_PATH:directory}});
  const text=result.stdout+result.stderr;
  if(reject){
   assert.notEqual(result.status,0,name);assert.match(text,pattern);
   assert.doesNotMatch(text,/maximum number of heartbeats|unknown package|unknown module|invalid field|unknown identifier|unknown constant|invalid dotted identifier|unexpected token|unterminated|failed to synthesize/);
  }else{
   assert.equal(result.status,0,text);assert.doesNotMatch(text,/sorryAx|declaration uses 'sorry'/);
  }
  return result.stdout;
 };
 for(const name of ['KwArgMetadata','KwArgTrace','KwArgTraceRegression']){
  if(join(here,name+'.lean')!==join(work,name+'.lean'))copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
  const out=compile(name,name!=='KwArgTraceRegression');
  if(name==='KwArgTraceRegression')assert.match(out,/inline KwArg kept its keyword node only/);
 }
 const program=traceModelProgram().replace('import KeywordTrace','import KwArgTrace').replaceAll('KeywordTrace.keyword','KwArgTrace.read');
 writeFileSync(join(work,'KwArgFixtures.lean'),program);
 const rows=compile('KwArgFixtures').trim().split(String.fromCharCode(10)).map(row=>JSON.parse(row));
 assert.equal(rows.length,traceCases.length);
 rows.forEach((row,index)=>assert.deepEqual(row,expectedTrace(traceCases[index])));
 const source=readFileSync(join(here,'KwArgTrace.lean'),'utf8');
 const mutants=[
  ['IgnoreInline','KeywordTrace.body grammar "KwArg"','KeywordTrace.body {grammar with inline := grammar.inline.filter (fun name => name != "KwArg")} "KwArg"'],
  ['WrongDispatch','name == "KeywordArgument"','name == "Word"'],
  ['WrongRule','KeywordTrace.body grammar "KwArg"','KeywordTrace.body grammar "Missing"'],
 ];
 const definitions=text=>{
  const rows=[];let skipping=false;
  for(const row of text.split(String.fromCharCode(10))){
   if(row.startsWith('theorem '))skipping=true;
   else if(/^(def |#print |end )/.test(row))skipping=false;
   if(!skipping&&!row.startsWith('#print '))rows.push(row);
  }
  return rows.join(String.fromCharCode(10));
 };
 for(const [name,before,after] of mutants){
  const changed=source.replace(before,after);assert.notEqual(changed,source,name);
  writeFileSync(join(work,'WrongKwArg'+name+'.lean'),changed);
  compile('WrongKwArg'+name,false,true);
  try{
   writeFileSync(join(work,'KwArgTrace.lean'),definitions(changed));
   compile('KwArgTrace',true);
   compile('KwArgTraceRegression',false,true,/missing inline KwArg capture/);
  }finally{
   writeFileSync(join(work,'KwArgTrace.lean'),source);
   compile('KwArgTrace',true);
  }
 }
 assert.match(compile('KwArgTraceRegression'),/inline KwArg kept its keyword node only/);
 const controls=join(work,'kwarg-metadata');mkdirSync(controls);
 copyFileSync(join(work,'PegModel.olean'),join(controls,'PegModel.olean'));
 copyFileSync(join(here,'KwArgMetadata.lean'),join(controls,'KwArgMetadata.lean'));
 const grammar=join(work,'KwArg-native.hpeg');const input=join(work,'KwArg-native.gm');
 const entry=source=>source.replace('%syntax\n','%syntax\n%entry KwArgProbe\n')+'\nKwArgProbe :: ()\nKwArgProbe <- KwArg .* { () }\n';
 const native=text=>{
  writeFileSync(input,text);
  return spawnSync(process.env.PEG_HS??'peg-hs',['parse','--entry','KwArgProbe','--format','cst',grammar,input],{encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'kwarg-native-cache')}});
 };
 writeFileSync(grammar,entry(original));
 const normal=native('key="value"');assert.equal(normal.status,0,normal.stdout+normal.stderr);
 assert.match(normal.stdout,/KeywordArgument@/);assert.doesNotMatch(normal.stdout,/^\s+KwArg@/m);
 const splat=native('**[items]');assert.equal(splat.status,0,splat.stdout+splat.stderr);assert.match(splat.stdout,/SplatArgument@/);
 writeFileSync(join(work,'KwArgScope.lean'),'import KwArgTrace\n#eval show IO Unit from do\n'+
  '  let got := KwArgTrace.read Generated.pegGrammar 512 "**[items]".toList\n'+
  '  match got with\n'+
  '  | .error "unmodeled non-reference expression" => IO.println "splat remains an explicit capture-model limitation"\n'+
  '  | _ => throw (IO.userError s!"unexpected splat capture {repr got}")\n');
 assert.match(compile('KwArgScope'),/splat remains an explicit capture-model limitation/);
 const sourceMutants=[
  ['NodeKwArg','%inline KwArg\n',''],
  ['WrongFirst','KwArg <- KeywordArgument','KwArg <- StringLit'],
 ];
 for(const [name,before,after] of sourceMutants){
  let changed=original.replace(before,after);assert.notEqual(changed,original,name);
  if(name==='WrongFirst')changed=changed.replace('%syntax\n','%syntax\n%entry KeywordArgument\n');
  const changedPath=join(controls,name+'.hpeg');writeFileSync(changedPath,changed);
  const emitted=spawnSync(process.execPath,[generator,'--fragment',changedPath,join(controls,'Generated.lean')],{encoding:'utf8'});
  assert.equal(emitted.status,0,emitted.stdout+emitted.stderr);
  compile('Generated',true,false,undefined,controls);
  compile('KwArgMetadata',false,true,/type mismatch|unsolved goals|decide.*false/s,controls);
  writeFileSync(grammar,entry(changed));
  if(name==='NodeKwArg'){
   const result=native('key="value"');assert.equal(result.status,0,result.stdout+result.stderr);assert.match(result.stdout,/^\s+KwArg@/m);
  }else{
   const control=native('"value"');assert.equal(control.status,0,control.stdout+control.stderr);
   const rejected=native('key="value"');assert.notEqual(rejected.status,0,rejected.stdout+rejected.stderr);
  }
 }
 const metadataOnly=model.split(String.fromCharCode(10)).map(line=>line.includes('name := "KwArg"')
  ?line.replaceAll(/line := ([0-9]+)/g,(_,value)=>'line := '+(Number(value)+17)):line).join(String.fromCharCode(10));
 assert.notEqual(metadataOnly,model);
 writeFileSync(join(controls,'Generated.lean'),metadataOnly);
 compile('Generated',true,false,undefined,controls);
 compile('KwArgMetadata',false,false,undefined,controls);
 return {modules:2,metadataControls:1,semanticMutants:mutants.length,runtimeWitnesses:mutants.length,sourceMutants:sourceMutants.length,fixtures:traceCases.length,nativeShapeCounterexamples:sourceMutants.length,nativeScopeControls:1};
}
