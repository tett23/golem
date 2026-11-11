// One directive, or one style value, at a time: unrelated directives have separate diagnostics.
export const replacements={G02065:'G02250',G02108:'G02251',G02129:'G02252',G03114:'G03250',G03115:'G03251',G03116:'G03252',G03117:'G03253'};
export function retire(diagnostics, activeCodes) {
  const duplicateTable = diagnostics.some(d => d.code === 'G02130') && activeCodes.has('G02129');
  return diagnostics.filter(d => !(duplicateTable && d.code === 'G02129'))
    .map(d => activeCodes.has(d.code) && d.severity === 'notice' ? {...d,code:replacements[d.code],severity:'error'} : d);
}
export function zero(input, field) {
  if (field === 'count') return input;
  if (input === 0 || input === '0' || input === '-0') return field === 'css-length' ? '0' : field === 'aki' ? 'ベタ' : '0pt';
  return input;
}
export function resolve(declarations, reference, kind, fontSize) {
  const entry = declarations[reference.slice(1)];
  if (!reference.startsWith('$') || !entry || entry.kind !== kind) throw Error('unknown name or wrong kind');
  if (kind === 'length' && entry.value.endsWith('zw')) return Number(entry.value.slice(0,-2)) * fontSize;
  return entry.value;
}
export function completions(declarations,kind) {
  return Object.entries(declarations).filter(([,entry]) => entry.kind === kind).map(([name]) => '$' + name);
}
export function rename(declarations, references, oldName, newName) {
  if (!Object.hasOwn(declarations,oldName) || Object.hasOwn(declarations,newName)) throw Error('name collision');
  return references.map(ref => ref === '$'+oldName ? '$'+newName : ref);
}

// Source-argument check before asset lookup. The caller retains existing empty-path handling.
export function pathOf(command, positional, src, read) {
  if (src.length && positional.length) return {error:command === 'listing' ? 'G02253' : 'G02130'};
  if (src.length) return {error:command === 'listing' ? 'G02250' : 'G02252'};
  return read(positional[0]);
}

// Probe a subset of literals; the production implementation should reuse the project's parsers.
const literalChecks={
  length:x=>typeof x==='string' && /^-?\d+(?:\.\d+)?(?:pt|mm|zw|Q|H)$/.test(x),
  aki:x=>typeof x==='string' && (/^(?:ベタ|全角|二分|三分|四分)$/.test(x)||/^\d+(?:\.\d+)?(?:zw|%)$/.test(x)),
  count:x=>Number.isSafeInteger(x) && x>=0
};
export function declare(rows) {
  const declarations=Object.create(null);
  for(const [kind,name,value] of rows){
    if(!/^[a-z][a-z0-9-]*$/.test(name) || Object.hasOwn(declarations,name)) throw Error('duplicate or invalid name');
    if(!literalChecks[kind]?.(value)) throw Error('invalid literal');
    declarations[name]={kind,value};
  }
  return declarations;
}
export function expand(declarations,ref,kind,scope) {
  if(!['style','style-def'].includes(scope)) throw Error('name outside style');
  const name=ref.slice(1);
  if(!ref.startsWith('$') || !Object.hasOwn(declarations,name) || declarations[name].kind!==kind) throw Error('unknown name or wrong kind');
  return declarations[name].value;
}
