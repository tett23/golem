import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {saveProjectFailure} from '../save-project-failure.mjs';
import {compileArgumentProbe,run} from './ast-probe.mjs';
import {diagnosticTraceCases,diagnosticManuscript,expectedDiagnostic} from '../grammar/trace-cases.mjs';
import {posargWordDiagnosticCases,posargWordManuscript,expectedPosargWordDiagnostic} from '../grammar/posarg-word-cases.mjs';

const here=fileURLToPath(new URL('.',import.meta.url));

test('root ADR 0351 I2, I3: bare percent values retain G01102 bytes and fixes; failed fmt leaves source unchanged',async t=>{
  const buildWork=mkdtempSync(join(tmpdir(),'golem-keyword-diagnostic-probe-'));
  try {
    const binary=compileArgumentProbe(buildWork,join(here,'NativeKeywordDiagnostics.hs'));
    const cases=[...diagnosticTraceCases.map(entry=>({source:diagnosticManuscript(entry),expected:expectedDiagnostic(entry)})),
      ...posargWordDiagnosticCases.map(raw=>({source:posargWordManuscript(raw),expected:expectedPosargWordDiagnostic(raw)}))];
    for(const [index,entry] of cases.entries()){
      await t.test('root ADR 0351 I2, I3: G01102 scope '+index,()=>{
        const work=mkdtempSync(join(tmpdir(),'golem-keyword-diagnostic-fields-'));
        const file=join(work,'a.gm');
        const source=entry.source;
        try {
          writeFileSync(file,source);
          const before=readFileSync(file);
          assert.deepEqual(JSON.parse(run(binary,[file])),entry.expected);
          const fmt=spawnSync(process.env.GOLEM??'golem',['fmt',file],{encoding:'utf8',cwd:work});
          assert.equal(fmt.error,undefined);
          assert.equal(fmt.signal,null);
          assert.equal(typeof fmt.status,'number');
          assert.ok(fmt.status>0,fmt.stdout+fmt.stderr);
          assert.match(fmt.stdout+fmt.stderr,/G01102/);
          assert.deepEqual(readFileSync(file),before);
        }catch(error){
          saveProjectFailure('arguments',work,source,error,'trace-diagnostic-'+index,'trace-diagnostics.native-test.mjs');
          throw error;
        }finally{rmSync(work,{recursive:true,force:true});}
      });
    }
  }finally{rmSync(buildWork,{recursive:true,force:true});}
});
