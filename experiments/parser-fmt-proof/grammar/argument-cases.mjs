import { traceCases } from './trace-cases.mjs';

export const argumentCases = [
  ...traceCases.slice(0,8).map(({row:[,kind,raw],value}) => ({kind,raw,value})),
  {kind:'Word',raw:'0.10',value:'0.10'},
  {kind:'Word',raw:'กำ',value:'กำ'},
  {kind:'Word',raw:'می‌روم',value:'می‌روم'},
  {kind:'StringLit',raw:'"%%= note"',value:'%%= note'},
];
export const argumentManuscript = ({raw}) => '[inspect '+raw+']\n';
export const expectedArgument = ({kind,raw,value}) => ({
  cst:[[{name:kind,text:raw}]],
  ast:[{argument:'Positional',kind,value}],
});
export function argumentModelProgram() {
  const fixtures=argumentCases.map(({raw})=>JSON.stringify(raw+']\n')).join(',\n');
  return `import Lean
import ArgumentTrace
open CstWrapper
#eval do
  let fixtures : List String := [${fixtures}]
  for input in fixtures do
    let got := ArgumentTrace.read Generated.pegGrammar 512 input.toList
    let .ok (some (rest,[Element.node "Argument" fields])) := got
      | throw (IO.userError s!"missing argument capture {repr got}")
    unless rest == [']','\\n'] do throw (IO.userError "wrong positional suffix")
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "Argument" []) input.toList
    unless (match recognized with | .ok (some suffix) => suffix == rest | _ => false) do
      throw (IO.userError "actual Argument recognition mismatch")
    let raw : List Lean.Json ← fields.mapM fun field => match field with
      | Element.token name chars => pure (Lean.Json.mkObj [("name",.str name),("text",.str (String.mk chars))])
      | _ => throw (IO.userError "unexpected nested argument capture")
    let .ok (some (_,values)) := ArgumentTrace.lower got
      | throw (IO.userError "missing positional AST")
    let ast := values.map fun (ArgumentTrace.Argument.positional value) =>
      let (kind,chars) := match value with
        | QuotedKeywords.Value.word chars => ("Word",chars)
        | QuotedKeywords.Value.string chars => ("StringLit",chars)
      Lean.Json.mkObj [("argument",.str "Positional"),("kind",.str kind),("value",.str (String.mk chars))]
    IO.println (Lean.Json.compress (Lean.Json.mkObj [
      ("cst",.arr #[.arr raw.toArray]),("ast",.arr ast.toArray)]))
`;
}
