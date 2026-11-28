import assert from 'node:assert/strict';
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { expectedWrapper, wrapperCases, wrapperModelProgram } from './wrapper-cases.mjs';

export function verifyWrapper({ here, work, lean, growthEnv, model, original }) {
  const compile = (name, output = false, reject = false, directory = work) => {
    const file = join(directory, name + '.lean');
    const result = spawnSync(lean, output ? ['-o', join(directory, name + '.olean'), file] : [file],
      { ...growthEnv, cwd: directory, env: { ...growthEnv.env, LEAN_PATH: directory } });
    const text = result.stdout + result.stderr;
    if (reject) {
      assert.notEqual(result.status, 0, name);
      assert.match(text, /type mismatch|unsolved goals|decide.*false/s);
      assert.doesNotMatch(text, /maximum number of heartbeats|unknown package|unknown module/);
    } else {
      assert.equal(result.status, 0, text);
      assert.doesNotMatch(text, /sorryAx|declaration uses 'sorry'/);
    }
    return result.stdout;
  };
  for (const name of ['CstWrapperMetadata', 'CstWrapper', 'CstWrapperRegression']) {
    if (join(here, name + '.lean') !== join(work, name + '.lean'))
      copyFileSync(join(here, name + '.lean'), join(work, name + '.lean'));
    const result = compile(name, name !== 'CstWrapperRegression');
    if (name === 'CstWrapperRegression') assert.match(result, /raw CST quoted spelling matched/);
  }
  writeFileSync(join(work, 'WrapperFixtures.lean'), wrapperModelProgram());
  const rows = compile('WrapperFixtures').trim().split('\n').map(row => JSON.parse(row));
  assert.equal(rows.length, wrapperCases.length);
  rows.forEach((row, index) => assert.deepEqual(row, expectedWrapper(wrapperCases[index])));
  const source = readFileSync(join(here, 'CstWrapper.lean'), 'utf8');
  const mutants = [
    ['RawSpelling', '[.token name (consumed input rest)]', '[.token name []]'],
    ['TokenChild', '[.token name (consumed input rest)]', 'children'],
    ['Inline', 'if grammar.inline.contains name then children', 'if grammar.inline.contains name then []'],
    ['Ordinary', 'else [.node name children]', 'else children'],
    ['Consumed', 'input.take (input.length - rest.length)', 'input.take (input.length - rest.length + 1)'],
    ['Priority', 'if grammar.inline.contains name then children\n  else if grammar.tokens.contains name then\n    [.token name (consumed input rest)]',
      'if grammar.tokens.contains name then [.token name (consumed input rest)]\n  else if grammar.inline.contains name then children'],
  ];
  for (const [name, before, after] of mutants) {
    const changed = source.replace(before, after);
    assert.notEqual(changed, source);
    writeFileSync(join(work, 'WrongWrapper' + name + '.lean'), changed);
    compile('WrongWrapper' + name, false, true);
  }
  // A fresh metadata-only proof imports only this newly generated grammar.
  // It must not reuse canonical Generated-specific proof artifacts.
  const controls = join(work, 'wrapper-metadata');
  mkdirSync(controls);
  copyFileSync(join(work, 'PegModel.olean'), join(controls, 'PegModel.olean'));
  copyFileSync(join(here, 'CstWrapperMetadata.lean'), join(controls, 'CstWrapperMetadata.lean'));
  const setModel = source => {
    writeFileSync(join(controls, 'Generated.lean'), source);
    compile('Generated', true, false, controls);
  };
  setModel(model);
  compile('CstWrapperMetadata', false, false, controls);
  const input = join(controls, 'input.gm');
  writeFileSync(input, '[inspect key="a\\"b"]\n');
  const peg = process.env.PEG_HS ?? 'peg-hs';
  const native = grammar => {
    const file = join(controls, 'native.hpeg');
    writeFileSync(file, grammar);
    return spawnSync(peg, ['parse', '--format', 'cst', file, input],
      { encoding: 'utf8', env: { ...process.env, XDG_CACHE_HOME: join(controls, 'cache') } });
  };
  const normal = native(original);
  assert.equal(normal.status, 0, normal.stdout + normal.stderr);
  const metadataMutants = [
    ['StringToken', '%token StringLit\n', '', out => assert.match(out, /^\s*StringLit@\d+\.\.\d+\s*$/m)],
    ['ValueInline', '%inline ArgValue\n', '', out => assert.match(out, /ArgValue@/)],
    ['KeywordToken', '%token Word\n', '%token KeywordArgument\n%token Word\n', out => assert.doesNotMatch(out, /Word@/)],
    ['WordInline', '%token Word\n', '%inline Word\n', out => assert.doesNotMatch(out, /Word@/)],
  ];
  for (const [name, before, after, check] of metadataMutants) {
    const changed = original.replace(before, after);
    assert.notEqual(changed, original);
    const grammar = join(controls, name + '.hpeg');
    writeFileSync(grammar, changed);
    const generated = join(controls, 'Generated.lean');
    const emitted = spawnSync(process.execPath, [join(here, 'generate.mjs'), grammar, generated], { encoding: 'utf8' });
    assert.equal(emitted.status, 0, emitted.stdout + emitted.stderr);
    compile('Generated', true, false, controls);
    compile('CstWrapperMetadata', false, true, controls);
    const result = native(changed);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.notEqual(result.stdout, normal.stdout, name);
    check(result.stdout);
  }
  setModel(model);
  compile('CstWrapperMetadata', false, false, controls);
  return { modules: 2, semanticMutants: mutants.length, metadataMutants: metadataMutants.length,
    nativeShapeCounterexamples: metadataMutants.length, fixtures: wrapperCases.length };
}
