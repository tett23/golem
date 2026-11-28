import assert from 'node:assert/strict';
import {chmodSync,mkdtempSync,readFileSync,rmSync,unlinkSync,writeFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {tmpdir} from 'node:os';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import test from 'node:test';
import {nativeTests,validateNativeTests} from './native-runner.mjs';
function fixture(action) {
  const work=mkdtempSync(join(tmpdir(),'golem-native-manifest-'));
  try { for(const name of nativeTests)writeFileSync(join(work,name),'');action(work); }
  finally { rmSync(work,{recursive:true,force:true}); }
}
test('root ADR 0351: the local native runner includes all eight files',()=>fixture(work=>{
  assert.equal(nativeTests.length,8);
  assert.deepEqual(validateNativeTests(work),nativeTests);
}));
test('root ADR 0351: each missing observer fails rather than silently passing',()=>{
  for(const name of nativeTests)fixture(work=>{
    unlinkSync(join(work,name));assert.throws(()=>validateNativeTests(work),/native observer manifest mismatch/);
  });
});
test('root ADR 0351: a new observer cannot remain outside the local full runner',()=>fixture(work=>{
  writeFileSync(join(work,'forgotten.native-test.mjs'),'');
  assert.throws(()=>validateNativeTests(work),/native observer manifest mismatch/);
}));

test('root ADR 0351: local full checks still run every observer after a proof failure',()=>fixture(work=>{
  const fake=join(work,'node');const log=join(work,'calls.log');
  writeFileSync(fake,'#!/bin/sh\nprintf "%s\\n" "$*" >> "$TASK_NATIVE_LOG"\ncase "$*" in *grammar/test.mjs*) exit 1;; esac\n');
  chmodSync(fake,0o755);
  const script=fileURLToPath(new URL('./check-local.sh',import.meta.url));
  const result=spawnSync('sh',[script],{encoding:'utf8',env:{...process.env,
    PATH:work+':'+process.env.PATH,TASK_NATIVE_LOG:log}});
  assert.equal(result.status,1,result.stdout+result.stderr);
  const calls=readFileSync(log,'utf8').trim().split('\n');
  assert.equal(calls.length,4);
  assert.match(calls[0],/native-runner.test.mjs/);
  assert.match(calls[1],/grammar\/test.mjs/);
  assert.match(calls[2],/native-runner.mjs/);
  assert.match(calls[3],/arguments\/check.test.mjs/);
}));
