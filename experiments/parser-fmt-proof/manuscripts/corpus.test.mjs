import assert from 'node:assert/strict';
import test from 'node:test';
import { clusterCount, bodies, withoutPositions } from './corpus.mjs';

test('Golem ADR 0351 I2: count extended grapheme clusters in generated text', () => {
  for (const text of ['a','鰍','𠮷','👨‍👩‍👧‍👦','กำ','بَ']) assert.equal(clusterCount(text), 1);
  for (const text of ['เก','لا']) assert.equal(clusterCount(text), 2);
  const words = [...bodies(2)];
  assert.ok(words.includes('𠮷👨‍👩‍👧‍👦'));
  assert.ok(words.every(text => clusterCount(text) <= 2));
  assert.equal(words.length, new Set(words).size);
});

test('Golem ADR 0351 I2: inspect positions are erased only outside literals', () => {
  assert.equal(withoutPositions('Text "a @2..3" @0..8'), 'Text "a @2..3"');
  assert.equal(withoutPositions('Text "a\\" @2..3" @0..8'), 'Text "a\\" @2..3"');
});

test('Golem ADR 0351 I4: listing keywords cover independent omissions and both orders', async () => {
  const { listingCases } = await import('./corpus.mjs');
  assert.deepEqual([...listingCases()], [
    '@listing x.hs\n',
    '@listing x.hs lines=1...1\n',
    '@listing x.hs lines=1...1 %%甲%%%%乙%% lang=haskell\n',
    '@listing x.hs lang=haskell\n',
    '@listing x.hs lang=haskell %%甲%%%%乙%% lines=1...1\n',
  ]);
});

test('Golem ADR 0351 I2/I3: enumerate nested inline command paths at each depth', async () => {
  const { nestedInlineCases } = await import('./corpus.mjs');
  assert.deepEqual([...nestedInlineCases(0)], []);
  assert.deepEqual([...nestedInlineCases(2)], [
    '[strong: 鰍]\n', '[em: 鰍]\n',
    '[strong: [strong: 鰍]]\n', '[em: [strong: 鰍]]\n',
    '[strong: [em: 鰍]]\n', '[em: [em: 鰍]]\n',
  ]);
});

test('Golem ADR 0351 I4: enumerate every ordered subset of three fence keys', async () => {
  const { orderedSubsets } = await import('./corpus.mjs');
  const cases = [...orderedSubsets(['k', 'm', 'n'])];
  assert.deepEqual([0, 1, 2, 3].map(n => cases.filter(keys => keys.length === n).length), [1, 3, 6, 6]);
  assert.equal(new Set(cases.map(keys => keys.join(''))).size, 16);
  assert.ok(cases.every(keys => keys.every(key => ['k', 'm', 'n'].includes(key)) && new Set(keys).size === keys.length));
});
