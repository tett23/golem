// The two kinds of editor grammars give the same element the same class
// (docs/adr/0170-emet-editor-support.md, "分類の一致").
//
// The samples sample.gm and sample.emet are the tests of the TextMate
// grammars in the format of vscode-tmgrammar-test: each source line is
// followed by lines that write, under the elements, the scopes they must
// have. This test reads those scopes, turns each into its class by the
// table of the ADR, and checks that
//
// - the innermost scope that the TextMate grammar gives there is of the same
//   class (vscode-tmgrammar-test only checks that the scope is among them);
// - the innermost capture of queries/highlights.scm of the tree-sitter
//   grammar on the same source is of the same class.
//
// An assertion of the scope of the file alone (source.golem) or of a scope
// of no class (markup.raw) says that the element has no class: no capture.
//
// Run by tools/editors/test.sh: node --test tools/editors/test/

'use strict';

const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const EDITORS = path.resolve(__dirname, '..');
const MODULES = path.join(EDITORS, 'node_modules');
const { parseGrammarTestCase } = require(path.join(MODULES, 'vscode-tmgrammar-test/dist/unit/parsing.js'));
const vsctm = require(path.join(MODULES, 'vscode-textmate'));
const oniguruma = require(path.join(MODULES, 'vscode-oniguruma'));
const TREE_SITTER = path.join(MODULES, '.bin', 'tree-sitter');

// The TextMate scopes of the classes (the table of docs/adr/0170), by
// prefix. markup.heading is the line of a heading: the TextMate grammar
// gives the whole line that scope, and its text is the namespace of the
// semantic tokens of .gm.
const SCOPES = [
  ['comment.line', 'comment'],
  ['keyword.control', 'keyword'],
  ['entity.name.function', 'function'],
  ['entity.name.tag', 'decorator'],
  ['variable.parameter', 'parameter'],
  ['variable.other', 'variable'],
  ['entity.name.type', 'type'],
  ['constant.other', 'enumMember'],
  ['entity.name.namespace', 'namespace'],
  ['string.quoted', 'string'],
  ['string.unquoted', 'string'],
  ['constant.numeric', 'number'],
  ['keyword.operator', 'operator'],
  ['constant.character.escape', 'macro'],
  ['storage.modifier', 'macro'],
  ['markup.heading', 'namespace'],
];

// The captures of the tree-sitter grammars (nvim-treesitter's names).
// type and typeParameter share @type, as they share entity.name.type.
const CAPTURES = {
  comment: 'comment',
  keyword: 'keyword',
  function: 'function',
  attribute: 'decorator',
  'variable.parameter': 'parameter',
  variable: 'variable',
  type: 'type',
  constructor: 'enumMember',
  module: 'namespace',
  string: 'string',
  number: 'number',
  operator: 'operator',
  'string.escape': 'macro',
  'keyword.modifier': 'macro',
};

// Where the TextMate grammar is coarser (the ADR): the head of an
// application in .emet is a variable there and a function in tree-sitter.
const COARSER = {
  emet: { variable: ['variable', 'function'] },
  golem: {},
};

function classOfScope(scope) {
  const hit = SCOPES.find(([prefix]) => scope === prefix || scope.startsWith(prefix + '.'));
  return hit ? hit[1] : 'none';
}

async function textmate(grammarFile, scopeName) {
  const wasm = fs.readFileSync(path.join(MODULES, 'vscode-oniguruma/release/onig.wasm')).buffer;
  await oniguruma.loadWASM(wasm);
  const registry = new vsctm.Registry({
    onigLib: Promise.resolve({
      createOnigScanner: sources => new oniguruma.OnigScanner(sources),
      createOnigString: s => new oniguruma.OnigString(s),
    }),
    loadGrammar: async scope =>
      scope === scopeName ? vsctm.parseRawGrammar(fs.readFileSync(grammarFile, 'utf8'), grammarFile) : null,
  });
  return registry.loadGrammar(scopeName);
}

// The captures of the highlights query: {row, start, end, name} with
// columns in bytes, from the output of tree-sitter query.
function captures(grammarDir, source) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'golem-editors-'));
  try {
    const file = path.join(dir, 'sample');
    fs.writeFileSync(file, source);
    const out = execFileSync(
      TREE_SITTER,
      ['query', '-p', grammarDir, path.join(grammarDir, 'queries/highlights.scm'), file],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    const re = /capture: \d+ - ([\w.]+), start: \((\d+), (\d+)\), end: \((\d+), (\d+)\)/;
    return out
      .split('\n')
      .map(l => re.exec(l))
      .filter(m => m)
      .map(m => ({ name: m[1], start: [+m[2], +m[3]], end: [+m[4], +m[5]] }));
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function before(a, b) {
  return a[0] < b[0] || (a[0] === b[0] && a[1] <= b[1]);
}

// the class of the innermost capture at (row, byte column)
function classOfCaptures(caps, row, col) {
  const at = [row, col];
  const hits = caps.filter(c => before(c.start, at) && !before(c.end, at));
  if (hits.length === 0) return 'none';
  // innermost: the one that starts last, then ends first
  const same = (p, q) => p[0] === q[0] && p[1] === q[1];
  hits.sort((a, b) => {
    if (!same(a.start, b.start)) return before(a.start, b.start) ? 1 : -1;
    if (same(a.end, b.end)) return 0;
    return before(a.end, b.end) ? -1 : 1;
  });
  return CAPTURES[hits[0].name] || `unknown capture @${hits[0].name}`;
}

function check(language, sample, grammarFile, scopeName, grammarDir) {
  test(`${sample}: the same class in both grammars`, async () => {
    const tc = parseGrammarTestCase(fs.readFileSync(path.join(__dirname, sample), 'utf8'));
    assert.ok(tc.assertions.length > 0, 'the sample has assertions');
    const grammar = await textmate(path.join(EDITORS, 'textmate', grammarFile), scopeName);
    const caps = captures(path.join(EDITORS, grammarDir), tc.source.join('\n'));

    let stack = vsctm.INITIAL;
    const tokens = tc.source.map(line => {
      const r = grammar.tokenizeLine(line, stack);
      stack = r.ruleStack;
      return r.tokens;
    });

    const failures = [];
    for (const { sourceLineNumber: row, scopeAssertions } of tc.assertions) {
      const line = tc.source[row];
      for (const { from, to, scopes } of scopeAssertions) {
        if (scopes.length === 0) continue;
        const what = `line ${row + 1} "${line.slice(from, to)}"`;
        const want = classOfScope(scopes[scopes.length - 1]);
        const token = tokens[row].find(t => t.startIndex <= from && from < t.endIndex);
        const tm = token ? classOfScope(token.scopes[token.scopes.length - 1]) : 'none';
        if (tm !== want) failures.push(`${what}: TextMate gives ${tm}, the assertion ${want}`);
        const byte = Buffer.byteLength(line.slice(0, from), 'utf8');
        const ts = classOfCaptures(caps, row, byte);
        const allowed = COARSER[language][want] || [want];
        if (!allowed.includes(ts)) failures.push(`${what}: tree-sitter gives ${ts}, TextMate ${want}`);
      }
    }
    assert.deepStrictEqual(failures, []);
  });
}

check('golem', 'sample.gm', 'golem.tmLanguage.json', 'source.golem', 'tree-sitter-golem');
check('emet', 'sample.emet', 'emet.tmLanguage.json', 'source.emet', 'tree-sitter-emet');
