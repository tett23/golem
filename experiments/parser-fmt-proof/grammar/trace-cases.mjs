import { expectedWrapper } from './wrapper-cases.mjs';
import { expectedToken, tokenCases, tokenManuscript } from './token-cases.mjs';
export const traceCases = [
  ...tokenCases.slice(0,8).map(entries => entries[0]),
  {row:['na%%me','Word','value'],value:'value'},
  {row:['percent','Word','%'],value:'%'},
  {row:['marker','StringLit','"%%= note"'],value:'%%= note'},
  {row:['number','Word','0.10'],value:'0.10'},
];
export const expectedTrace = entry => ({cst:expectedWrapper(entry.row),ast:expectedToken([entry]),codes:[]});
export const traceManuscript = entry => tokenManuscript([entry]);
export function traceModelProgram() {
  const rows=traceCases.map(({row:[key,kind,raw]}) => '('+JSON.stringify(key)+','+JSON.stringify(kind)+','+JSON.stringify(raw)+')').join(',\n');
  return `import Lean
import KeywordTrace
open CstWrapper
#eval do
  let fixtures : List (String × String × String) := [${rows}]
  for (key,_,raw) in fixtures do
    let got := KeywordTrace.keyword Generated.pegGrammar 512 (key ++ "=" ++ raw ++ "]\\n").toList
    let .ok (some (rest,[Element.node "KeywordArgument" fields])) := got
      | throw (IO.userError s!"missing traced keyword {repr got}")
    unless rest == "]\\n".toList do throw (IO.userError "wrong trace suffix")
    let tokens : List Lean.Json ← fields.mapM fun field => match field with
      | Element.token name chars => pure (Lean.Json.mkObj [("name",.str name),("text",.str (String.mk chars))])
      | _ => throw (IO.userError "unexpected nested trace capture")
    let .ok (some (after,values)) := KeywordTrace.lower got
      | throw (IO.userError "missing lowered trace")
    unless after == rest do throw (IO.userError "lowering changed suffix")
    let arguments := values.map fun (name,value) =>
      let (kind,chars) := match value with
        | QuotedKeywords.Value.word chars => ("Word",chars)
        | QuotedKeywords.Value.string chars => ("StringLit",chars)
      Lean.Json.mkObj [("name",.str (String.mk name)),("kind",.str kind),("value",.str (String.mk chars))]
    let .ok (some (codeRest,codes)) := KeywordTrace.quoteFlags got
      | throw (IO.userError "missing quote flags")
    unless codeRest == rest do throw (IO.userError "quote flags changed suffix")
    IO.println (Lean.Json.compress (Lean.Json.mkObj [("cst",.arr #[.arr tokens.toArray]),("ast",.arr arguments.toArray),("codes",.arr ((codes.map Lean.Json.str).toArray))]))
`;
}
export const scopeProgram=`import KeywordTrace
#eval show IO Unit from do
  let got := KeywordTrace.keyword Generated.pegGrammar 512 "key=[= 1]@tail".toList
  match got with
  | .error "unmodeled non-token capture" => IO.println "unsupported non-token capture rejected"
  | _ => throw (IO.userError s!"expected unsupported non-token capture, got {repr got}")
`;

export const diagnosticTraceCases=[
  {name:'na%%me',value:'a%%b'},
  {name:'名',value:'a%%b'},
  {name:'名',value:'𠮷%%b'},
];
export const diagnosticManuscript=({name,value})=>'[inspect '+name+'='+value+']\n';
export const expectedDiagnostic=entry=>{
  const source=diagnosticManuscript(entry);
  const start=Buffer.byteLength(source.slice(0,source.lastIndexOf(entry.value)),'utf8');
  const end=start+Buffer.byteLength(entry.value,'utf8');
  return [{code:'G01102',severity:'error',start,end,fixes:[[{start,end,text:'"'+entry.value+'"'}]]}];
};

export function diagnosticModelProgram(){
 const rows=diagnosticTraceCases.map(({name,value})=>'('+JSON.stringify(name)+','+JSON.stringify(value)+')').join(',');
 return `import Lean
import KeywordTrace
#eval do
  let inputs : List (String × String) := [${rows}]
  for (name,value) in inputs do
    let got := KeywordTrace.keyword Generated.pegGrammar 512 (name ++ "=" ++ value ++ "]\\n").toList
    let .ok (some (rest,codes)) := KeywordTrace.quoteFlags got
      | throw (IO.userError "missing G01102 projection")
    unless rest == "]\\n".toList do throw (IO.userError "wrong G01102 projection suffix")
    IO.println (Lean.Json.compress (.arr ((codes.map Lean.Json.str).toArray)))
`;
}
