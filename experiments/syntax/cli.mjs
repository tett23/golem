import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {retire,zero,resolve} from './proposal.mjs';
import assert from 'node:assert/strict';
const binary=fs.realpathSync(process.argv[2]);
const sample='modules/golem-driver/test/fixtures/sample';
const folder=fs.mkdtempSync(path.join(os.tmpdir(),'golem-road-syntax-'));
function check(style,source,command='check',rules='') {
  const page='[page]\nsize="A5"\n';
  const grid='[page.grid]\nfont-size="10pt"\ncharacters=30\nlines=20\nline-pitch="16pt"\nposition={top="12mm",gutter="12mm"}\n';
  if(!style.includes('[page]')) style=page+style;
  if(style.includes("[page]") && !style.includes("size=")) style=style.replace("[page]","[page]\nsize=\"A5\"");
  if(!style.includes('[page.grid]')) style+='\n'+grid;
  fs.writeFileSync(path.join(folder,'style.toml'),style+'\n[fonts.body]\nja="body.otf"\n');
  fs.writeFileSync(path.join(folder,'front.gm'),source+'\n');
  fs.writeFileSync(path.join(folder,'preflight.toml'),rules);
  const child=spawnSync(binary,[command,'--format','json'],{cwd:folder,encoding:'utf8'});
  for(const stream of [child.stderr,child.stdout]){
    try {const ds=JSON.parse(stream);if(Array.isArray(ds))return {status:child.status,ds};}catch{}
  }
  throw Error(child.stderr+child.stdout);
}
try {
  fs.cpSync(sample,folder,{recursive:true});
  fs.copyFileSync('modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf',path.join(folder,'body.otf'));
  const manifest=fs.readFileSync(path.join(folder,'manifest.toml'),'utf8').replace(/^chapters = .*/m,'chapters = ["front.gm"]');
  fs.writeFileSync(path.join(folder,'manifest.toml'),manifest);
  fs.writeFileSync(path.join(folder,'a.txt'),'one\ntwo\nthree\n');
  fs.writeFileSync(path.join(folder,'t.csv'),'a,b\nc,d\n');
  const old = [
    ['G02065','@listing src=a.txt','@listing a.txt'],
    ['G02065','@listing a.txt src=missing.txt','@listing a.txt'],
    ['G02108','@listing a.txt lines=1-2','@listing a.txt lines=1...2'],
    ['G02129','@table src=t.csv','@table t.csv'],
    ['G03114','[lists]\nnumbers = ["{{{n}}}"]','[lists]\nnumbers = [\'\\{{n}\\}\']'],
    ['G03115','[lists]\nnumbers = ["{a}."]','[lists]\nnumbers = ["{n:lower-alpha}."]'],
    ['G03116','[masters.extra]\nrunning-head = { position = "top-outside", content = ["{{x}}"] }','[masters.extra]\nrunning-head = { position = "top-outside", content = [\'\\{x\\}\'] }'],
    ['G03117','[notes]\nmark-size = "0.5zw"','[character-styles.note-mark]\nsize = "0.5zw"'],
  ];
  for(const [code,before,after] of old){
    const run=x=>x.startsWith('@')?check('',x):check(x,'本文。');
    const b=run(before), a=run(after);
    console.log(code,b.status,b.ds.map(d=>d.code),'=>',a.status,a.ds.map(d=>d.code));
    assert(b.ds.some(d=>d.code===code)); assert.equal(a.status,0);
    assert(retire(b.ds,new Set([code])).some(d=>d.severity==='error'));
  }
  const grid='[page]\nsize="A5"\n[page.grid]\nfont-size="10pt"\ncharacters=30\nlines=20\nline-pitch="16pt"\n';
  const cases=[
    '[page]\nbleed=?',grid+'position={top="10mm",gutter="10mm"}\ncolumn-gap=?',grid+'position={top=?,gutter="10mm"}',
    ...['indent','first-line-indent'].map(k=>'[paragraph-styles.quote]\n'+k+'=?'),
    ...['paragraph','character'].map(k=>'['+k+'-styles.code]\npadding=?'),
    '[composition.ruby]\noverhang=?',
    ...['space-before','space-after','start-indent'].flatMap(k=>['[paragraph-styles.quote]\nrule-before={'+k+'=?}','[notes.rule]\nlength="1zw"\n'+k+'=?']),
    '[character-styles.sup]\nbaseline-shift=?','[lists]\ngap=?','[index]\ncolumn-gap=?',
    '[aki-sets.a]\nrules=[{before="kana",after="line-end",optimum=?}]',
  ];
  for(const tmpl of cases){
    const run=x=>check(tmpl.replace('?',x),'本文。');
    const old=run('0'), str=run('"0"'), after=run(JSON.stringify(zero(0,tmpl.includes('aki-sets')?'aki':'length')));
    console.log(tmpl.split('\n').slice(-2).join('/'),old.ds.map(d=>d.code),str.ds.map(d=>d.code),'=>',after.ds.map(d=>[d.code,d.message]));
    assert.equal(old.status,1);assert.equal(str.status,1);assert.equal(after.status,tmpl.includes('notes.rule') && tmpl.includes('start-indent') ? 1 : 0);
  }
  fs.writeFileSync(path.join(folder,'t.svg'),'<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>');
  for(const [before,after] of [
    ['@style-def paragraph x indent=0\n\n本文。','@style-def paragraph x indent=0pt\n\n本文。'],
    ['あ[aki 0]い','あ[aki ベタ]い'],
    ['@blank-line 0\n\n本文。','@blank-line 1\n\n本文。'],
    ['@figure t.svg alt="図" wrap=end width=0\n  図。','@figure t.svg alt="図" wrap=end width=0pt\n  図。'],
  ]) {
    const b=check('',before),a=check('',after);
    console.log(before.split('\n')[0],b.status,b.ds.map(d=>d.code),'=>',a.status,a.ds.map(d=>d.code));
    assert.equal(b.status,1);assert.equal(a.status,before.startsWith('@figure')?1:0);
  }
  const pf=x=>check('','本文。','preflight','[bleed-size]\nmin='+x+'\n');
  for(const x of ['0','"0"','"0pt"']) {
    const r=pf(x);console.log('preflight',x,r.status,r.ds.map(d=>d.code));
    assert.equal(r.ds.some(d=>d.code==='G09001'),x!=='"0pt"');
  }
  const defs={indent:{kind:'length',value:'1zw'}};
  for(const size of [10,12]){
    const reading=check('[paragraph-styles.body]\nindent="'+resolve(defs,'$indent','length',size)+'pt"','本文。');
    console.log('named indent at',size,reading.status,reading.ds.map(d=>d.code));assert.equal(reading.status,0);
  }
}finally{fs.rmSync(folder,{recursive:true,force:true});}
