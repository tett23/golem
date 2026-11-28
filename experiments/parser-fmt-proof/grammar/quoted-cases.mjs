// Shared, invented parser examples: values are compared as typed AST fields,
// not by removing spans with a regular expression from Haskell's Show output.
export const quotedCases = [
  [],
  [['path', 'a"b']],
  [['path', 'a\\b'], ['%k', '%v%%=x']],
  [['甲', '鰍𠮷👨‍👩‍👧‍👦กำبَمی‌روم']],
  [['x', ''], ['x', 'other']],
  [['key', 'space = ] | [ :'], ['number', '0.10'], ['literal', 'true']],
  [['line', 'line\nbreak']],
  [['tail', 'slash\\'], ['position', ' @17..19 ']],
];

export const expectedQuoted = rows => rows.map(([name, value]) => ({ name, kind: 'StringLit', value }));
export const spellQuoted = value => '"' + [...value]
  .map(c => ['"', '\\', '\n'].includes(c) ? '\\' + c : c).join('') + '"';
export const quotedManuscript = rows => '@inspect' + rows
  .map(([name, value]) => ' ' + name + '=' + spellQuoted(value)).join('') + '\n';

const leanChar = c => "'" + ({ '\\': '\\\\', "'": "\\'", '\n': '\\n', '\t': '\\t' }[c] ?? c) + "'";
const leanPart = c => ['"', '\\', '\n'].includes(c)
  ? '.escaped ' + leanChar(c)
  : '.plain ⟨' + leanChar(c) + ',by decide,by decide,by decide⟩';

export function quotedModelProgram() {
  const fixtures = quotedCases.map(rows => '[' + rows.map(([name, value]) =>
    '({ chars := ' + JSON.stringify(name) + '.toList, valid := by decide, nonempty := by decide }, [' +
    [...value].map(leanPart).join(',') + '])').join(',') + ']').join(',\n');
  return `import Lean
import QuotedCanonical
open QuotedKeywords
#eval do
  let fixtures : List (List Entry) := [${fixtures}]
  for args in fixtures do
    let got : Option (List (List Char × QuotedKeywords.Value)) := QuotedKeywords.parseArgs args.length (QuotedKeywords.printArgs args)
    let some values := got | throw (IO.userError "quoted fields missing")
    let rows := values.map fun (name,value) => Lean.Json.mkObj [
      ("name",.str (String.mk name)),
      ("kind",.str (match value with | QuotedKeywords.Value.string _ => "StringLit" | QuotedKeywords.Value.word _ => "Word")),
      ("value",.str (String.mk (match value with | QuotedKeywords.Value.string cs => cs | QuotedKeywords.Value.word cs => cs)))]
    let recognized := PegModel.recognizeEnv Generated.pegGrammar [] 512 (.ref "Arguments" []) (printArgs args ++ "@suffix\\n".toList)
    unless (match recognized with | .ok (some rest) => rest == "\\n@suffix\\n".toList | _ => false) do
      throw (IO.userError "canonical quoted arguments mismatch")
    IO.println (Lean.Json.compress (.arr rows.toArray))
`;
}
