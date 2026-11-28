import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import { saveProjectFailure } from '../save-project-failure.mjs';
import { compileArgumentProbe, run } from './ast-probe.mjs';
import { expectedTrace, traceCases, traceManuscript } from '../grammar/trace-cases.mjs';

const here=fileURLToPath(new URL('.',import.meta.url));

test('root ADR 0351 I1, I2, I3: generated keyword captures and decoded fields match native parsing and fmt',async t => {
  const cstWork=mkdtempSync(join(tmpdir(),'golem-trace-cst-probe-'));
  const astWork=mkdtempSync(join(tmpdir(),'golem-trace-ast-probe-'));
  try {
    const cst=compileArgumentProbe(cstWork,join(here,'NativeRawCst.hs'));
    const ast=compileArgumentProbe(astWork);
    for(const [index,entry] of traceCases.entries()) {
      await t.test('root ADR 0351 I1, I2, I3: capture fields '+index,()=>{
        const work=mkdtempSync(join(tmpdir(),'golem-trace-fields-'));
        const source=traceManuscript(entry);
        const file=join(work,'a.gm');
        try {
          writeFileSync(file,source);
          const expected=expectedTrace(entry);
          assert.deepEqual(JSON.parse(run(cst,[file])),expected.cst);
          assert.deepEqual(JSON.parse(run(ast,[file])),expected.ast);
          run(process.env.GOLEM??'golem',['fmt',file],{cwd:work});
          assert.deepEqual(JSON.parse(run(ast,[file])),expected.ast);
          const once=readFileSync(file);
          run(process.env.GOLEM??'golem',['fmt',file],{cwd:work});
          assert.deepEqual(readFileSync(file),once);
        } catch(error) {
          saveProjectFailure('arguments',work,source,error,'trace-fields-'+index,'trace-values.native-test.mjs');
          throw error;
        } finally {rmSync(work,{recursive:true,force:true});}
      });
    }
  } finally {
    rmSync(cstWork,{recursive:true,force:true});
    rmSync(astWork,{recursive:true,force:true});
  }
});
