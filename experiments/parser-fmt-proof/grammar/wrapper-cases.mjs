export const wrapperCases = [
  ['key', 'Word', 'value'],
  ['key', 'StringLit', '"a\\"b"'],
  ['key', 'StringLit', '"a\\n b"'],
  ['甲', 'Word', '鰍𠮷'],
  ['甲', 'StringLit', '"𠮷👨‍👩‍👧‍👦"'],
  ['line', 'StringLit', '"a\\\nb"'],
  ['empty', 'StringLit', '""'],
  ['tail', 'StringLit', '"slash\\\\"'],
];
export const expectedWrapper = ([key, kind, raw]) => [[
  { name: 'Word', text: key }, { name: 'Eq', text: '=' }, { name: kind, text: raw },
]];
export const wrapperManuscript = ([key, , raw]) => '[inspect ' + key + '=' + raw + ']\n';
export function wrapperModelProgram() {
  const fixtures = wrapperCases.map(([key, kind, raw]) =>
    '(' + JSON.stringify(key) + ',' + JSON.stringify(kind) + ',' + JSON.stringify(raw) + ')').join(',\n');
  return `import Lean
import CstWrapper
open CstWrapper
#eval do
  let fixtures : List (String × String × String) := [${fixtures}]
  for (key,kind,raw) in fixtures do
    let input := (key ++ "=" ++ raw ++ "]\\n").toList
    let children := [Element.node "discarded inner child" []]
    let .ok (some (afterName,name)) := project Generated.pegGrammar "Word" 512 input children
      | throw (IO.userError "missing name token")
    let .ok (some (afterEq,eq)) := project Generated.pegGrammar "Eq" 512 afterName children
      | throw (IO.userError "missing equals token")
    let .ok (some (rest,value)) := project Generated.pegGrammar kind 512 afterEq children
      | throw (IO.userError "missing value token")
    unless rest == "]\\n".toList do throw (IO.userError "wrong keyword suffix")
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "KeywordArgument" []) input
    unless (match recognized with | .ok (some remaining) => remaining == rest | _ => false) do
      throw (IO.userError "actual KeywordArgument recognition mismatch")
    let body := name ++ eq ++ wrap Generated.pegGrammar "ArgValue" afterEq rest value
    let wrapped := wrap Generated.pegGrammar "KeywordArgument" input rest body
    let [.node nodeName fields] := wrapped | throw (IO.userError "missing keyword wrapper")
    unless nodeName == "KeywordArgument" do throw (IO.userError "wrong node wrapper")
    let rows : List Lean.Json ← fields.mapM fun field => match field with
      | Element.token name chars => pure (Lean.Json.mkObj [("name",.str name),("text",.str (String.mk chars))])
      | Element.node _ _ => throw (IO.userError "unexpected nested wrapper")
    IO.println (Lean.Json.compress (.arr #[.arr rows.toArray]))
`;
}
