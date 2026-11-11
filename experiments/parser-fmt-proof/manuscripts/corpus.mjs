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
