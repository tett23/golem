export const lowerCases = [
  [],
  [['', 'Ignored', 'outside'], ['mode', 'Word', 'plain'], ['text', 'StringLit', 'a"b'],
    ['mode', 'Word', 'plain'], ['empty', 'StringLit', '']],
  [['甲', 'Word', '鰍𠮷'], ['line', 'StringLit', 'a\nb'], ['slash', 'StringLit', 'a\\b']],
  [['drop', 'ProofComment', 'not an ordinary comment'], ['kept', 'Word', '%x'], ['position', 'StringLit', ' @17..19 ']],
  [['n', 'Word', '0.10'], ['', 'Ignored', 'between'], ['n', 'StringLit', '0.10'], ['flag', 'Word', 'true']],
];
export const expectedLower = rows => rows.filter(([, kind]) => !['Ignored', 'ProofComment'].includes(kind))
  .map(([name, kind, value]) => ({ name, kind, value }));
export const quoteLower = value => '"' + [...value]
  .map(c => ['"', '\\', '\n'].includes(c) ? '\\' + c : c).join('') + '"';
export const nativeLowerRows = rows => rows.map(([name, kind, value]) =>
  [name, kind, ['StringLit', 'ProofComment'].includes(kind) ? quoteLower(value) : value]);
const char = c => "'" + ({ '\\': '\\\\', "'": "\\'", '\n': '\\n', '\t': '\\t' }[c] ?? c) + "'";
const part = c => ['"', '\\', '\n'].includes(c)
  ? '.escaped ' + char(c) : '.plain ⟨' + char(c) + ',by decide,by decide,by decide⟩';
const word = s => '{ chars := ' + JSON.stringify(s) + '.toList, valid := by decide, nonempty := by decide }';
export function lowerModelProgram() {
  const input = lowerCases.map(rows => '[' + rows.map(([name, kind, value]) => {
    if (kind === 'Ignored') return 'Element.ignored';
    const entry = '(' + word(name) + ',' + (kind === 'Word' ? '.word ' + word(value) :
      '.string [' + [...value].map(part).join(',') + ']') + ')';
    const decorated = '{ entry := ' + entry + ', before := [.comment "%% before %%".toList], ' +
      'middleLeft := [.whitespace "  ".toList], middleRight := [.comment "%% middle %%".toList], after := [.newline [\'\\n\']] }';
    const tokens = 'decoratedTokens (' + decorated + ')';
    return 'Element.keyword (' + (kind === 'ProofComment' ? '⟨.proofComment,"%%= proof %%".toList⟩ :: ' : '') + tokens + ')';
  }).join(',') + ']').join(',\n');
  return `import Lean
import KeywordLowering
open KeywordLowering
#eval do
  let fixtures : List (List Element) := [${input}]
  for elements in fixtures do
    let rows := (lowerArguments elements).map fun (name,value) => Lean.Json.mkObj [
      ("name",.str (String.mk name)),
      ("kind",.str (match value with | QuotedKeywords.Value.string _ => "StringLit" | QuotedKeywords.Value.word _ => "Word")),
      ("value",.str (String.mk (match value with | QuotedKeywords.Value.string cs => cs | QuotedKeywords.Value.word cs => cs)))]
    IO.println (Lean.Json.compress (.arr rows.toArray))
`;
}
