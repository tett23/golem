import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {declaration} from './review.mjs';
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
  for(const input of ['@listing a.txt a.txt','@listing src=a.txt src=a.txt','@listing a.txt src=a.txt src=a.txt','@listing a.txt lines="1...3, 5...7"','@listing a.txt lines="1.,.3, 5..,7"','@listing a.txt lines=-1','@set n = 0\n@listing a.txt lines=[= n]','@set n = -1\n@listing a.txt lines=[= n]','@blank-line 0','@blank-line 2','@set x = "abc"\n\n[= x]','set x = "abc"\n\n[= x]','@set x = "abc"\n\n[= @x]','前置 @x','@x','set x is fine']) {
    const observed=check('',input);
    console.log(JSON.stringify({input,status:observed.status,codes:observed.ds.map(d=>d.code)}));
  }
  const viaPrototype=check('',['set x = "abc"','','[= x]'].map(declaration).join('\n'));
  assert.equal(viaPrototype.status,0);
  console.log(JSON.stringify({declarationPrototype:viaPrototype}));
} finally {fs.rmSync(folder,{recursive:true,force:true});}
