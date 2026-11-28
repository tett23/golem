export const posargWordCases = ['cinder','*','**','%','%x','cinder%%','星','7.25','0','-7','a/b','a.b'];
export const posargWordSuccessCases = posargWordCases.filter(raw=>!raw.includes('%%'));
export const posargWordDiagnosticCases = posargWordCases.filter(raw=>raw.includes('%%'));
export const expectedPosargWordDiagnostic = raw => {
  const start=Buffer.byteLength('[inspect ','utf8');const end=start+Buffer.byteLength(raw,'utf8');
  return [{code:'G01102',severity:'error',start,end,fixes:[[{start,end,text:JSON.stringify(raw)}]]}];
};
export const posargWordManuscript = raw => '[inspect '+raw+' ]\n';
export const expectedPosargWord = raw => ({cst:[[{name:'Word',text:raw}]],
  ast:[{argument:'Positional',kind:'Word',value:raw}]});
export function posargWordModelProgram() {
  return `import Lean
import PosArgWord
open CstWrapper
#eval do
  let values : List String := [${posargWordCases.map(JSON.stringify).join(',')}]
  for value in values do
    let input := (value++" ]\\n").toList
    let got := PosArgTrace.read Generated.pegGrammar (input.length+14) input
    let .ok (some (rest,[Element.node "Argument" [Element.token "Word" raw]])) := got
      | throw (IO.userError s!"missing space-delimited word capture {repr got}")
    unless rest == " ]\\n".toList && raw == value.toList do
      throw (IO.userError "wrong space-delimited word capture")
    let .ok (some (_, [.positional (.word text)])) := ArgumentTrace.lower got
      | throw (IO.userError "missing space-delimited word AST")
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] (input.length+14) (.ref "PosArg" []) input
    unless (match recognized with | .ok (some suffix) => suffix == rest | _ => false) do
      throw (IO.userError "space-delimited word recognition mismatch")
    IO.println (Lean.Json.compress (Lean.Json.mkObj [
      ("cst",.arr #[.arr #[Lean.Json.mkObj [("name",.str "Word"),("text",.str (String.mk raw))]]]),
      ("ast",.arr #[Lean.Json.mkObj [("argument",.str "Positional"),("kind",.str "Word"),("value",.str (String.mk text))]])]))
`;
}
