export const eofWords=['cinder','*','**','***','7.25','星','cinder%%','%','*cinder','-','.','a,b'];
export const expectedEof=word=>({rest:'',cst:[[{name:'Word',text:word}]],ast:[{argument:'Positional',kind:'Word',value:word}]});
export function eofModelProgram(){
 return `import Lean
import PosArgEof
open CstWrapper
#eval do
  let inputs : List String := [${eofWords.map(word=>JSON.stringify(word)).join(',')}]
  for text in inputs do
    unless !text.isEmpty && text.toList.all WordRoundTrip.allowed && !WordRoundTrip.startsComment text.toList do
      throw (IO.userError "invalid EOF positional fixture")
    let input := text.toList
    let got := PosArgTrace.read Generated.pegGrammar (input.length+14) input
    let .ok (some ([],[Element.node "Argument" [Element.token "Word" raw]])) := got
      | throw (IO.userError s!"missing EOF capture {repr got}")
    let .ok (some ([],[.positional (.word value)])) := ArgumentTrace.lower got
      | throw (IO.userError "missing EOF AST")
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] (input.length+14) (.ref "PosArg" []) input
    unless (match recognized with | .ok (some []) => true | _ => false) do
      throw (IO.userError "different EOF recognition suffix")
    IO.println (Lean.Json.compress (Lean.Json.mkObj [
      ("rest",.str ""),
      ("cst",.arr #[.arr #[Lean.Json.mkObj [("name",.str "Word"),("text",.str (String.mk raw))]]]),
      ("ast",.arr #[Lean.Json.mkObj [("argument",.str "Positional"),("kind",.str "Word"),("value",.str (String.mk value))]])]))
`;
}
