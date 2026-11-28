export const bracketWords=['cinder','***','星','7.25','cinder%%'];
export const bracketSuffixes=['[','[7]','[tail]'];
export const bracketCases=bracketWords.flatMap(word=>bracketSuffixes.map(suffix=>({word,suffix})));
export const expectedBracket=({word,suffix})=>({rest:suffix,cst:[[{name:'Word',text:word}]],ast:[{argument:'Positional',kind:'Word',value:word}]});
export function bracketModelProgram(){
 return `import Lean
import PosArgDelimited
open CstWrapper
#eval do
  let inputs : List String := [${bracketCases.map(row=>JSON.stringify(row.word+row.suffix)).join(',')}]
  for text in inputs do
    let input := text.toList
    let got := PosArgTrace.read Generated.pegGrammar (input.length+14) input
    let .ok (some (rest,[Element.node "Argument" [Element.token "Word" raw]])) := got
      | throw (IO.userError s!"missing bracket capture {repr got}")
    let .ok (some (suffix,[.positional (.word value)])) := ArgumentTrace.lower got
      | throw (IO.userError "missing bracket AST")
    unless suffix == rest do throw (IO.userError "different bracket AST suffix")
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] (input.length+14) (.ref "PosArg" []) input
    unless (match recognized with | .ok (some r) => r == rest | _ => false) do
      throw (IO.userError "different bracket recognition suffix")
    IO.println (Lean.Json.compress (Lean.Json.mkObj [
      ("rest",.str (String.mk rest)),
      ("cst",.arr #[.arr #[Lean.Json.mkObj [("name",.str "Word"),("text",.str (String.mk raw))]]]),
      ("ast",.arr #[Lean.Json.mkObj [("argument",.str "Positional"),("kind",.str "Word"),("value",.str (String.mk value))]])]))
`;
}
