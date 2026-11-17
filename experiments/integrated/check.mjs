import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';

const binary=fs.realpathSync(process.argv[2]);
const bleedLiteral=process.argv[3]==='unitful'?'\"0pt\"':'0';
const root=fs.mkdtempSync(path.join(os.tmpdir(),'golem-integrated-'));
const book=path.join(root,'book');
const read=name=>fs.readFileSync(path.join(book,name),'utf8');
const write=(name,text)=>fs.writeFileSync(path.join(book,name),text);
let failed=0, total=0;
function expect(label,actual,expected){
  total++;
  const ok=JSON.stringify(actual)===JSON.stringify(expected);
  if(!ok)failed++;
  console.log(JSON.stringify({label,ok,actual,expected}));
}
function exec(args,cwd=book){
  const p=spawnSync(binary,args,{cwd,encoding:'utf8',env:{...process.env,XDG_CACHE_HOME:path.join(root,'cache')}});
  let ds=[];
  for(const output of [p.stdout,p.stderr]){
    try{const parsed=JSON.parse(output);ds=Array.isArray(parsed)?parsed:parsed.diagnostics;break;}catch{}
  }
  return {exit:p.status,ds};
}
function preflight(extra=[]){return exec(['preflight','--format','json',...extra]);}
const codes=r=>r.ds.map(d=>d.code);
function html(){
  return exec(['build','--target','html','--format','json']);
}
try{
  const made=exec(['new',book,'--language','ja','--no-fonts','--screen'],root);
  expect('screen template created',made.exit,0);
  if(made.exit!==0){
    const fallback=exec(['new',book,'--language','ja','--no-fonts'],root);
    if(fallback.exit!==0)throw Error('cannot create control project');
  }
  expect('screen rules selected',read('preflight.toml').trim(),'based-on = "screen"');
  expect('screen omits bleed',/^bleed\s*=/m.test(read('style.toml')),false);
  fs.copyFileSync('modules/golem-font/test/fonts/SourceHanSans-Regular_subset.otf',path.join(book,'ja.otf'));
  const original=read('style.toml');
  const style=original.replace(/^bleed\s*=.*\n/gm,'').replace('[page]','[page]\nbleed = '+bleedLiteral).replace(/\n\[fonts\.[^\]]+\][\s\S]*?(?=\n\[|$)/g,'');
  write('style.toml',style+'\n[fonts.body]\nja = "ja.otf"\n');
  write('chapters/01.gm','本文。\uE000\n');
  for(const severity of ['off','warning','error']){
    write('preflight.toml','based-on = "screen"\n[glyph-missing]\nseverity = "'+severity+'"\n');
    const r=preflight();
    expect('zero bleed / screen / glyph '+severity,[r.exit,...r.ds.filter(d=>d.code==='G09002'||d.severity==='error').map(d=>[d.code,d.severity])],
      severity==='off'?[0]:[Number(severity==='error'),['G09002',severity]]);
  }
  write('preflight.toml','based-on = "screen"\n[glyph-missing]\nseverity = "warning"\n[bleed-size]\nseverity = "error"\nmin = "3mm"\n');
  const overridden=preflight();
  expect('bleed override and glyph coexist',[overridden.exit,...[...new Set(codes(overridden))].sort()],[1,'G09002','G09010']);
  write('preflight.toml','based-on = "screen"\n[glyph-missing]\nseverity = "off"\n');
  const marks=preflight(['--marks','japanese']);
  expect('0332 M1 explicit marks reject zero bleed',[marks.exit,codes(marks).includes('G07002')],[1,true]);
  const markMessage='日本式のトンボには塗り足しが要ります。style.toml の [page] の bleed に 0 より大きい長さを書いてください';
  expect('0332 M1 marks explain how to correct an explicitly present zero',marks.ds.find(d=>d.code==='G07002')?.message??null,markMessage);
  const explain=spawnSync(binary,['explain','G07002'],{cwd:book,encoding:'utf8'});
  expect('0332 M3 explain lists the same required positive length',[explain.status,explain.stdout.split('\n').includes('- メッセージ: `'+markMessage+'`')],[0,true]);
  const zeroStyle=read('style.toml');
  write('style.toml',zeroStyle.replace(/^bleed = .*$/m,'bleed = "3mm"'));
  const positive=preflight(['--marks','japanese']);
  expect('0332 M2 positive bleed resolves marks error',[positive.exit,codes(positive).includes('G07002')],[0,false]);
  write('style.toml',zeroStyle);
  const htmlMarks=exec(['build','--target','html','--marks','japanese','--format','json']);
  expect('0332 M2 HTML-only build ignores marks',[htmlMarks.exit,codes(htmlMarks).includes('G07002')],[0,false]);
  write('style.toml',zeroStyle.replace(/^bleed = .*\n/m,''));
  const omitted=preflight(['--marks','japanese']);
  expect('0332 M1 omitted bleed has the same repair',[omitted.exit,omitted.ds.filter(d=>d.code==='G07002').map(d=>d.message)],[1,[markMessage]]);
  write('style.toml',zeroStyle);
  const mf=read('manifest.toml')+'\n[[metadata.printings]]\nedition=1\nprinting=1\ndate=2026-10-16\n';
  write('chapters/01.gm','# 本\n\n@printings\n');
  for(const [tag,error] of [['JA-jp',null],['ja_JP','G03119'],['en-US','G02076']]){
    write('manifest.toml',mf.replace(/^language\s*=.*$/m,'language = "'+tag+'"'));
    const r=html();
    expect('HTML language '+tag,[r.exit,...codes(r)],[Number(Boolean(error)),...(error?[error]:[])]);
    if(!error){
      const chapter='build/html/chapters/01.xhtml';
      const contents=fs.existsSync(path.join(book,chapter))?read(chapter):'';
      expect('JA-jp prints Japanese edition and date',contents.match(/<p>([^<]*発行)<\/p>/)?.[1]??null,'二〇二六年十月十六日　初版第一刷発行');
    }
  }
  write('manifest.toml',mf);
  write('style.toml',read('style.toml').replace(/^bleed = .*$/m,'bleed = "0pt"'));
  write('items.csv','one,two\nx\n');
  for(const [source,expected] of [
    ['@table src=items.csv',['G02252']],
    ['@table items.csv src=items.csv',['G02130']],
    ['@table items.csv',['G02154']],
  ]){
    write('chapters/01.gm',source+'\n');
    const r=html();
    expect('table source and row-size precedence: '+source,[r.exit,codes(r)],[1,expected]);
  }
}finally{
  fs.rmSync(root,{recursive:true,force:true});
}
console.log(JSON.stringify({total,passed:total-failed,failed}));
process.exitCode=Number(failed>0);
