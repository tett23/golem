import test from 'node:test';
import assert from 'node:assert/strict';
import {retire, replacements, zero, resolve, completions, rename} from './proposal.mjs';
const diag = (code,severity='notice') => ({code,severity,span:{start:1,end:4}});
for (const [id,codes] of [[315,['G02065']],[316,['G02108']],[317,['G02129']],[318,['G03114','G03115','G03116','G03117']]]) {
  test(id+' I1 migration preserves location and only changes targeted codes',()=>{
    for(const code of codes){
      const actual=retire([diag(code),diag('G02062')],new Set(codes));
      assert.deepEqual(actual,[diag(replacements[code],'error'),diag('G02062')]);
    }
  });
}
test('317 I2 existing duplicate path error takes precedence',()=>{
  assert.deepEqual(retire([diag('G02129'),diag('G02130','error')],new Set(['G02129'])),[diag('G02130','error')]);
});
test('319 I1 numeric and textual zero share canonical dimension',()=>{
  for(const input of [0,-0,'0','-0']) assert.equal(zero(input,'length'),'0pt');
  for(const input of [1,'1','-1',false,'','0.0','+0','00']) assert.equal(zero(input,'length'),input);
});
test('319 I2 count and CSS remain distinct',()=>{
  assert.equal(zero(0,'count'),0);
  assert.equal(zero('0','css-length'),'0');
});
const decl={body:{kind:'length',value:'1zw'},gap:{kind:'aki',value:'二分'},rows:{kind:'count',value:2}};
test('320 I1 use site resolves zw and enforces kind',()=>{
  assert.equal(resolve(decl,'$body','length',10),10);
  assert.equal(resolve(decl,'$body','length',12),12);
  assert.equal(resolve(decl,'$gap','aki',12),'二分');
  assert.equal(resolve(decl,'$rows','count',12),2);
  assert.throws(()=>resolve(decl,'$body','count',12));
  assert.throws(()=>resolve(decl,'$other','length',10));
});
test('320 I2 completion and rename follow references',()=>{
  assert.deepEqual(completions(decl,'length'),['$body']);
  assert.deepEqual(rename(decl,['$body','body','$rows'],'body','indent'),['$indent','body','$rows']);
  assert.throws(()=>rename(decl,[],'body','rows'));
});
test('315 I2, 317 I2 reject ambiguous input before file lookup',async()=>{
  const {pathOf} = await import('./proposal.mjs');
  for(const command of ['listing','table']){
    const calls=[];
    const read=path=>{calls.push(path);return path;};
    assert.equal(pathOf(command,['a'],['b'],read).error,command==='listing'?'G02253':'G02130');
    assert.equal(pathOf(command,[],['b'],read).error,command==='listing'?'G02250':'G02252');
    assert.deepEqual(calls,[]);
    assert.equal(pathOf(command,['a'],[],read),'a');
    assert.deepEqual(calls,['a']);
  }
});
test('320 I3 declarations reject duplicates, aliases and ill-typed literals',async()=>{
  const {declare}=await import('./proposal.mjs');
  const rows=[['length','zw','1zw'],['aki','half','二分'],['count','rows',2]];
  assert.deepEqual(Object.keys(declare(rows)),['zw','half','rows']);
  for(const invalid of [[...rows,['aki','zw','ベタ']],[['length','a','$b']],[['count','a',-1]],[['length','a','二分']],[['aki','a','3mm']],[['count','a',1.5]]])assert.throws(()=>declare(invalid));
});
test('320 I4 dimensional references expand only in eligible source fields',async()=>{
  const {expand}=await import('./proposal.mjs');
  assert.equal(expand(decl,'$body','length','style'),'1zw');
  assert.equal(expand(decl,'$body','length','style-def'),'1zw');
  assert.throws(()=>expand(decl,'$body','length','preflight'));
});
