import assert from 'node:assert/strict';
import {mkdtempSync,readFileSync,rmSync,writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {compileArgumentProbe,run} from './ast-probe.mjs';
import {saveProjectFailure} from '../save-project-failure.mjs';
import {argumentCases,argumentManuscript,expectedArgument} from '../grammar/argument-cases.mjs';

const here=fileURLToPath(new URL('.',import.meta.url));
test('root ADR 0351 I1, I2, I3: positional word and string captures match parsing and ordinary fmt',async t=>{
  const compiled=mkdtempSync(join(tmpdir(),'golem-positional-native-'));
  try {
    const probe=compileArgumentProbe(compiled,join(here,'NativePositional.hs'));
    for(const [index,entry] of argumentCases.entries()) {
      await t.test('root ADR 0351 I1, I2, I3: positional value '+index,()=>{
        const work=mkdtempSync(join(tmpdir(),'golem-positional-value-'));
        const source=argumentManuscript(entry);const file=join(work,'a.gm');
        try {
          writeFileSync(file,source);const expected=expectedArgument(entry);
          assert.deepEqual(JSON.parse(run(probe,[file])),expected);
          run(process.env.GOLEM??'golem',['fmt',file],{cwd:work});
          assert.deepEqual(JSON.parse(run(probe,[file])).ast,expected.ast);
          const once=readFileSync(file);
          run(process.env.GOLEM??'golem',['fmt',file],{cwd:work});
          assert.deepEqual(readFileSync(file),once);
        }catch(error){
          saveProjectFailure('arguments',work,source,error,'positional-'+index,'positional-values.native-test.mjs');throw error;
        }finally{rmSync(work,{recursive:true,force:true});}
      });
    }
  }finally{rmSync(compiled,{recursive:true,force:true});}
});
