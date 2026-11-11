export function source(args) {
  const keywords=args.filter(x=>x.startsWith('src='));
  if (keywords.length>1) return 'G02077';
  if(args.length>1) return 'G02253';
  return keywords.length ? 'G02250' : args[0] ?? 'G02036';
}
export function selection(input) {
  if(typeof input==='number') return input>0 && Number.isInteger(input) ? [[input,input]] : 'value';
  const output=[];
  let rest=input.trim();
  while(rest.length) {
    const item=/^(\d+)(?:(\.\.\.|-)(\d+))?\s*(?:,\s*(?=\d)|$)/.exec(rest);
    if(!item) return 'syntax';
    if(item[2]==='-') return 'G02251';
    const a=Number(item[1]), b=Number(item[3]??item[1]);
    if(!a || b<a) return 'value';
    output.push([a,b]);
    rest=rest.slice(item[0].length);
  }
  return output.length ? output : 'syntax';
}
export function blank(a,b) {return a+b;}
function parseTerm(raw) {
  const word=String(raw).trim();
  if(/^\d+$/.test(word)) return {tag:'integer',value:Number(word)};
  if(/^\d+(?:zw|pt|mm)$/.test(word)) return {tag:'length',value:word};
  if(['二分','ベタ'].includes(word)) return {tag:'aki',value:word};
  if(/^[a-z][a-z0-9-]*$/.test(word)) return {tag:'name',value:word};
  return {tag:'invalid'};
}
export function quantity(kind,expression,defs,path=new Set()) {
  const terms=String(expression).split('+').map(parseTerm);
  function resolve(term) {
    if(term.tag==='invalid') return 'invalid';
    if(term.tag==='name') {
      const binding=defs.get(term.value);
      if(!binding) return 'G03257';
      if(binding[0]!==kind) return 'G03258';
      if(path.has(term.value)) return 'cycle';
      return quantity(kind,binding[1],defs,new Set([...path,term.value]));
    }
    if(term.tag===kind) return term.value;
    if(term.tag==='integer') {
      if(kind==='count') return term.value<=2147483647 ? term.value : 'G03256';
      if(term.value===0) return kind==='length'?'0pt':'ベタ';
    }
    return 'G03258';
  }
  if(terms.length===1) return resolve(terms[0]);
  if(kind!=='count') return 'G03258';
  const values=terms.map(resolve);
  const error=values.find(x=>typeof x!=='number');
  if(error) return error;
  const sum=values.reduce((total,n)=>total+n,0);
  return sum<=2147483647 ? sum : 'G03256';
}
// One ordinary top-level manuscript line. Fences are handled by the host parser.
export function declaration(line) {
  return /^set[ \t]+[a-zA-Z_]\w*[ \t]+=(?!=)(?:[ \t]|$)/.test(line) ? '@'+line : line;
}
