import assert from 'node:assert/strict';
import test from 'node:test';
import { tableCases } from './cases.mjs';

for (const format of ['csv', 'tsv']) {
  test(`Golem ADR 0351 I9/I10: every lone-CR mutation of each reference ordering in ${format}`, () => {
    const cases = tableCases(format);
    const orders = new Set(cases.map(c => c.manuscript));
    assert.equal(orders.size, 2);
    for (const manuscript of orders) {
      const group = cases.filter(c => c.manuscript === manuscript);
      const [normal, ...broken] = group;
      assert.equal(normal.offset, null);
      assert.ok(normal.input.startsWith('\uFEFF'));
      assert.equal(normal.input.slice(1).replaceAll('\r\n', '\n'), normal.expected);
      const bytes = Buffer.from(normal.expected);
      if (format === 'csv') assert.ok(normal.expected.includes('\n\n'));
      const positions = Array.from(bytes.keys()).filter(i => bytes[i] === 10 && bytes[i + 1] !== 10);
      assert.deepEqual(broken.map(c => c.offset), positions);
      for (const c of broken) {
        const mutated = Buffer.from(bytes);
        mutated[c.offset] = 13;
        assert.notEqual(mutated[c.offset + 1], 10);
        assert.deepEqual(Buffer.from(c.input), mutated);
      }
    }
  });
}

test('Golem ADR 0351 I9: inspect IR exposes cell boundaries and significant whitespace', async () => {
  const { inspectedCells } = await import('./cases.mjs');
  assert.deepEqual(inspectedCells([
    'tableHeader = [[Text @0..7 "a"]]',
    'tableRows =',
    '  [[[Text @0..7 "x\\ny"]], [[Text @0..7 ""]], [[Text @0..7 "z  "]]]',
  ].join('\n')), [['a'], ['x\ny'], [''], ['z  ']]);
});
