const segmenter = new Intl.Segmenter('und', { granularity: 'grapheme' });
const representatives = ['a', '鰍', '𠮷', '👨‍👩‍👧‍👦', 'กำ', 'بَ'];

export function clusterCount(text) {
  return Array.from(segmenter.segment(text)).length;
}

export function* bodies(limit) {
  let layer = [''];
  yield '';
  for (let depth = 1; depth <= limit; depth++) {
    layer = layer.flatMap(prefix => representatives.map(letter => prefix + letter));
    for (const text of layer) {
      if (clusterCount(text) <= limit) yield text;
    }
  }
}

// The CLI prints quoted contents and byte positions. A position-like string
// inside an AST value is part of the comparison.
export function withoutPositions(ast) {
  return ast.replace(/"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'| @\d+\.\.\d+/gu,
    token => token.startsWith(' @') ? '' : token);
}

export function* listingCases() {
  const keys = ['lines=1...1', 'lang=haskell'];
  yield '@listing x.hs\n';
  for (const first of keys) {
    yield `@listing x.hs ${first}\n`;
    for (const second of keys) {
      if (second !== first) yield `@listing x.hs ${first} %%甲%%%%乙%% ${second}\n`;
    }
  }
}

export function* nestedInlineCases(depth) {
  let layer = ['鰍'];
  for (let level = 1; level <= depth; level++) {
    layer = layer.flatMap(body => ['strong', 'em'].map(name => `[${name}: ${body}]`));
    for (const command of layer) yield command + '\n';
  }
}

// One branch per choice of next key; stopping here omits the rest.
export function* orderedSubsets(keys) {
  yield [];
  for (const key of keys) {
    for (const tail of orderedSubsets(keys.filter(other => other !== key))) {
      yield [key, ...tail];
    }
  }
}
