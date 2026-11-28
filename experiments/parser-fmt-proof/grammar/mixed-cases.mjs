// Invented inputs shared by the typed model and actual Haskell AST checks.
export const mixedCases = [
  [],
  [['mode', 'Word', 'plain'], ['text', 'StringLit', 'quoted']],
  [['甲', 'Word', '鰍𠮷'], ['甲', 'StringLit', ''], ['mode', 'Word', '%x']],
  [['n', 'Word', '0.10'], ['n', 'StringLit', '0.10'], ['flag', 'Word', 'true']],
  [['left', 'StringLit', 'a"b'], ['right', 'Word', 'end'], ['line', 'StringLit', 'a\nb']],
];
export const expectedMixed = rows => rows.map(([name, kind, value]) => ({ name, kind, value }));
export const spellMixedString = value => '"' + [...value]
  .map(c => ['"', '\\', '\n'].includes(c) ? '\\' + c : c).join('') + '"';
export const mixedManuscript = rows => '@inspect' + rows
  .map(([name, kind, value]) => ' ' + name + '=' + (kind === 'Word' ? value : spellMixedString(value))).join('') + '\n';
const leanChar = c => "'" + ({ '\\': '\\\\', "'": "\\'", '\n': '\\n', '\t': '\\t' }[c] ?? c) + "'";
const leanPart = c => ['"', '\\', '\n'].includes(c)
  ? '.escaped ' + leanChar(c)
  : '.plain ⟨' + leanChar(c) + ',by decide,by decide,by decide⟩';
const leanWord = s => '{ chars := ' + JSON.stringify(s) + '.toList, valid := by decide, nonempty := by decide }';
export function mixedModelProgram() {
  const fixtures = mixedCases.map(rows => '[' + rows.map(([name, kind, value]) =>
    '(' + leanWord(name) + ',' + (kind === 'Word' ? '.word ' + leanWord(value) :
      '.string [' + [...value].map(leanPart).join(',') + ']') + ')').join(',') + ']').join(',\n');
  return `import Lean
import MixedCanonical
open MixedKeywords
#eval do
  let fixtures : List (List Entry) := [${fixtures}]
  for args in fixtures do
    let got := MixedKeywords.parseArgs args.length (MixedKeywords.printArgs args)
    let some values := got | throw (IO.userError "mixed fields missing")
    let rows := values.map fun (name,value) => Lean.Json.mkObj [
      ("name",.str (String.mk name)),
      ("kind",.str (match value with | QuotedKeywords.Value.string _ => "StringLit" | QuotedKeywords.Value.word _ => "Word")),
      ("value",.str (String.mk (match value with | QuotedKeywords.Value.string cs => cs | QuotedKeywords.Value.word cs => cs)))]
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "Arguments" []) (printArgs args ++ "@suffix\\n".toList)
    unless (match recognized with | .ok (some rest) => rest == "\\n@suffix\\n".toList | _ => false) do
      throw (IO.userError "canonical mixed arguments mismatch")
    IO.println (Lean.Json.compress (.arr rows.toArray))
`;
}
