import assert from 'node:assert/strict';
import { copyFileSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedQuoted, quotedCases, quotedModelProgram } from './quoted-cases.mjs';

export function verifyQuoted({ here, work, generated, model, original, lean, growthEnv }) {
  const compile = (name, output = false, reject = false) => {
    const file = join(work, name + '.lean');
    const result = spawnSync(lean, output ? ['-o', join(work, name + '.olean'), file] : [file], growthEnv);
    const text = result.stdout + result.stderr;
    if (reject) {
      assert.notEqual(result.status, 0, name);
      assert.match(text, /type mismatch|unsolved goals/);
      assert.doesNotMatch(text, /maximum number of heartbeats|unknown package|unknown module/);
    } else {
      assert.equal(result.status, 0, text);
      assert.doesNotMatch(text, /sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  const setModel = source => {
    writeFileSync(generated, source);
    compile('Generated', true);
  };
  // Both existing standalone checks need artifacts for the new imports.
  const proofModules = ['QuotedArgumentRules', 'QuotedKeywords', 'QuotedCanonical'];
  for (const name of ['StringRoundTrip', 'PrintedArguments', ...proofModules]) {
    copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    compile(name, true);
  }
  copyFileSync(join(here, 'QuotedKeywordRegression.lean'), join(work, 'QuotedKeywordRegression.lean'));
  assert.match(compile('QuotedKeywordRegression'), /quoted keyword exact name, kind and decoded value matched/);
  writeFileSync(join(work, 'QuotedFixtures.lean'), quotedModelProgram());
  const rows = compile('QuotedFixtures').trim().split('\n').map(row => JSON.parse(row));
  assert.equal(rows.length, quotedCases.length);
  rows.forEach((row, index) => assert.deepEqual(row, expectedQuoted(quotedCases[index])));

  const canonical = readFileSync(join(here, 'QuotedKeywords.lean'), 'utf8');
  const semanticMutants = [
    ['DecodedValue', '.string (StringRoundTrip.unescape spelling)', '.string spelling'],
    ['Kind', '.string (StringRoundTrip.unescape spelling)', '.word (StringRoundTrip.unescape spelling)'],
    ['Name', 'some ((name,.string (StringRoundTrip.unescape spelling))::values)',
      'some (([],.string (StringRoundTrip.unescape spelling))::values)'],
    ['Tail', 'some ((name,.string (StringRoundTrip.unescape spelling))::values)',
      'some [(name,.string (StringRoundTrip.unescape spelling))]'],
  ];
  for (const [name, before, after] of semanticMutants) {
    const changed = canonical.replace(before, after);
    assert.notEqual(changed, canonical);
    writeFileSync(join(work, 'WrongQuoted' + name + '.lean'), changed);
    compile('WrongQuoted' + name, false, true);
  }

  const stringLine = original.split('\n').find(line => line.startsWith('StringLit <-'));
  const body = stringLine.match(/\((.+) \/ (.+)\)\*/);
  assert.ok(body);
  const reversedString = stringLine.replace('(' + body[1] + ' / ' + body[2] + ')*',
    '(' + body[2] + ' / ' + body[1] + ')*');
  const grammarMutants = [
    ['Value', 'KeywordArgument <- Word Eq ArgValue', 'KeywordArgument <- Word Eq Word', '@inspect path="a\\"b"\n'],
    ['Name', 'KeywordArgument <- Word Eq ArgValue', 'KeywordArgument <- Ident Eq ArgValue', '@inspect %k="value"\n'],
    ['EscapeOrder', stringLine, reversedString, '@inspect path="a\\"b"\n'],
  ];
  const peg = process.env.PEG_HS ?? 'peg-hs';
  for (const [name, before, after, sample] of grammarMutants) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original);
    const grammar = join(work, 'Quoted' + name + '.hpeg');
    writeFileSync(grammar, changed);
    const gate = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.notEqual(gate.status, 0);
    assert.match(gate.stderr, name === 'EscapeOrder' ? /^unsupported StringLit choice /m : /KeywordArgument: unsupported production/);
    const input = join(work, 'quoted-counterexample.gm');
    writeFileSync(input, sample);
    const native = spawnSync(peg, ['parse', '--format', 'cst', grammar, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(work, 'cache') } });
    assert.notEqual(native.status, 0, native.stdout);
    assert.match(native.stdout + native.stderr, /^\d+:\d+: expected/m);

    // Change the actual emitted AST, then rebuild its only dependent guard
    // from source. No canonical, Generated-specific .olean is reused here.
    let ast = model;
    if (name === 'EscapeOrder') {
      ast = ast.split('\n').map(row => row.includes('name := "StringLit"')
        ? row.replace(/(\.star \(\.choice \[)(\[\.lit .*?\.any\]), (\[\.notPred .*?\.any\])(\]\))/, '$1$3, $2$4') : row).join('\n');
      assert.notEqual(ast, model, 'the actual StringLit AST order must change');
      ast = ast.replace('def stringLitEscapeFirst : Bool := true', 'def stringLitEscapeFirst : Bool := false');
    } else {
      ast = ast.split('\n').map(row => row.includes('name := "KeywordArgument"')
        ? name === 'Value' ? row.replace('.ref "ArgValue" []', '.ref "Word" []')
          : row.replace('.ref "Word" []', '.ref "Ident" []') : row).join('\n');
    }
    assert.notEqual(ast, model);
    setModel(ast);
    compile('QuotedArgumentRules', false, true);
  }
  const metadataControls = ['KeywordArgument', 'ArgValue', 'StringLit'];
  for (const name of metadataControls) {
    const changed = model.split('\n').map(row => row.includes('name := "' + name + '"')
      ? row.replace(/line := (\d+)/g, (_, value) => 'line := ' + (Number(value) + 17))
        .replaceAll(' () ', '  ()  ') : row).join('\n');
    assert.notEqual(changed, model);
    setModel(changed);
    compile('QuotedArgumentRules');
  }
  setModel(model);
  return {
    modules: proofModules.length, semanticMutants: semanticMutants.length,
    sourceMutants: grammarMutants.length, astMutants: grammarMutants.length,
    metadataControls: metadataControls.length, fixtures: quotedCases.length,
    nativeCounterexamples: grammarMutants.length,
  };
}
