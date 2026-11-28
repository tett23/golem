import { wrapperCases } from './wrapper-cases.mjs';
const values = ['value', 'a"b', 'an b', '鰍𠮷', '𠮷👨‍👩‍👧‍👦', 'a\nb', '', 'slash\\'];
const rows = wrapperCases.map((row,index) => ({row,value:values[index]}));
export const tokenCases = [...rows.map(row => [row]),rows];
export const tokenManuscript = entries => '[inspect ' + entries.map(({row:[key,,raw]}) => key + '=' + raw).join(' ') + ']\n';
export const expectedToken = entries => entries.map(({row:[name,kind],value}) => ({name,kind,value}));
export function tokenModelProgram() {
  const fixtures = tokenCases.map(entries => '[' + entries.map(({row:[key,kind,raw]}) =>
    '(' + JSON.stringify(key) + ',' + JSON.stringify(kind) + ',' + JSON.stringify(raw) + ')').join(',') + ']').join(',\n');
  return `import Lean
import TokenLowering
open CstWrapper
#eval do
  let fixtures : List (List (String × String × String)) := [${fixtures}]
  for entries in fixtures do
    let mut elements : List Element := []
    for (key,kind,raw) in entries do
      let input := (key ++ "=" ++ raw ++ "]\\n").toList
      let children := [Element.node "discarded child" []]
      let .ok (some (afterName,name)) := project Generated.pegGrammar "Word" 512 input children
        | throw (IO.userError "missing name")
      let .ok (some (afterEq,eq)) := project Generated.pegGrammar "Eq" 512 afterName children
        | throw (IO.userError "missing equals")
      let .ok (some (rest,value)) := project Generated.pegGrammar kind 512 afterEq children
        | throw (IO.userError "missing value")
      unless rest == "]\\n".toList do throw (IO.userError "wrong suffix")
      let recognized := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "KeywordArgument" []) input
      unless (match recognized with | .ok (some remaining) => remaining == rest | _ => false) do
        throw (IO.userError "actual keyword recognition mismatch")
      let fields := name ++ eq ++ wrap Generated.pegGrammar "ArgValue" afterEq rest value
      elements := elements ++ wrap Generated.pegGrammar "KeywordArgument" input rest fields
    let rows := (TokenLowering.arguments elements).map fun (key,value) =>
      let (kind,chars) := match value with
        | QuotedKeywords.Value.word chars => ("Word",chars)
        | QuotedKeywords.Value.string chars => ("StringLit",chars)
      Lean.Json.mkObj [("name",.str (String.mk key)),("kind",.str kind),("value",.str (String.mk chars))]
    IO.println (Lean.Json.compress (.arr rows.toArray))
`;
}
