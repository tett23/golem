import assert from 'node:assert/strict';
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedTrace, traceCases, traceModelProgram, scopeProgram, diagnosticTraceCases, diagnosticModelProgram } from './trace-cases.mjs';

export function verifyTrace({here,work,lean,growthEnv,grammar}) {
  const compile=(name,output=false,reject=false,pattern=/type mismatch|unsolved goals/) => {
    const file=join(work,name+'.lean');
    const result=spawnSync(lean,output?['-o',join(work,name+'.olean'),file]:[file],growthEnv);
    const text=result.stdout+result.stderr;
    if(reject) {
      assert.notEqual(result.status,0,name);
      assert.match(text,pattern);
      assert.doesNotMatch(text,/maximum number of heartbeats|unknown package|unknown module|invalid field|unknown identifier|unknown constant|invalid dotted identifier|unexpected token|unterminated|failed to synthesize/);
    } else {
      assert.equal(result.status,0,text);
      assert.doesNotMatch(text,/sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for(const name of ['KeywordTrace','KeywordTraceRegression','KeywordDiagnosticRegression']) {
    if(join(here,name+'.lean')!==join(work,name+'.lean'))
      copyFileSync(join(here,name+'.lean'),join(work,name+'.lean'));
    const out=compile(name,name==='KeywordTrace');
    if(name==='KeywordTraceRegression') assert.match(out,/generated keyword CST and decoded AST matched/);
    if(name==='KeywordDiagnosticRegression') assert.match(out,/modeled G01102 quote predicate matched/);
  }
  writeFileSync(join(work,'TraceFixtures.lean'),traceModelProgram());
  const rows=compile('TraceFixtures').trim().split('\n').map(row=>JSON.parse(row));
  assert.equal(rows.length,traceCases.length);
  rows.forEach((row,index)=>assert.deepEqual(row,expectedTrace(traceCases[index])));
  writeFileSync(join(work,'TraceDiagnosticFixtures.lean'),diagnosticModelProgram());
  const diagRows=compile('TraceDiagnosticFixtures').trim().split(String.fromCharCode(10)).map(row=>JSON.parse(row));
  assert.equal(diagRows.length,diagnosticTraceCases.length);
  diagRows.forEach(row=>assert.deepEqual(row,['G01102']));
  writeFileSync(join(work,'TraceScope.lean'),scopeProgram);
  assert.match(compile('TraceScope'),/unsupported non-token capture rejected/);
  const source=readFileSync(join(here,'KeywordTrace.lean'),'utf8');
  const mutants=[
    ['DropChildren','(rest,first++last)','(rest,[])'],
    ['ReverseChildren','(rest,first++last)','(rest,last++first)'],
    ['ResetInput','sequence read more after','sequence read more input'],
    ['DropNode','(rest,wrap grammar name input rest children)','(rest,children)'],
    ['IgnoreInline','wrap grammar name input rest children','wrap {grammar with inline:=[]} name input rest children'],
    ['SkipFirst','rule.alts.map (·.items)','(rule.alts.drop 1).map (·.items)'],
    ['WrongDispatch','if name == "ArgValue" && args.isEmpty','if name == "Word" && args.isEmpty'],
    ['IgnoreQuoteCode','if WordRoundTrip.containsDoublePercent chars then some "G01102" else none','none'],
    ['NameQuoteCode','(wordTokens fields).drop 1','(wordTokens fields).drop 0'],
    ['DropQuoteProjection','.node "KeywordArgument" fields => keywordQuoteCodes fields','.node "KeywordArgument" fields => []'],
  ];
  for(const [name,before,after] of mutants) {
    const changed=source.replace(before,after);
    assert.notEqual(changed,source,name);
    writeFileSync(join(work,'WrongTrace'+name+'.lean'),changed);
    compile('WrongTrace'+name,false,true);
  }
  const forged=source.replace('.error "unmodeled non-token capture"','.ok (some (rest,[]))');
  assert.notEqual(forged,source);
  try {
    writeFileSync(join(work,'KeywordTrace.lean'),forged);
    compile('KeywordTrace',true);
    compile('TraceScope',false,true,/expected unsupported non-token capture/);
  } finally {
    writeFileSync(join(work,'KeywordTrace.lean'),source);
    compile('KeywordTrace',true);
  }
  assert.match(compile('TraceScope'),/unsupported non-token capture rejected/);
  const input=join(work,'trace-native-scope.gm');
  writeFileSync(input,'[inspect key=[= 1]]\n');
  const native=spawnSync(process.env.PEG_HS??'peg-hs',['parse','--format','cst',grammar,input],
    {encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:join(work,'trace-native-cache')}});
  assert.equal(native.status,0,native.stdout+native.stderr);
  assert.match(native.stdout,/Expr/);
  return {modules:1,proofMutants:mutants.length,runtimeMutants:1,fixtures:traceCases.length,diagnosticFixtures:diagnosticTraceCases.length,nativeScopeControls:1};
}
