// Quoted CSV newlines and trailing spaces are significant cell contents.
const tables = {
  csv: '名,b\n\n"x""甲,\n\ny",\n,z  \n',
  tsv: '名\tb\nx\t\n\tz  \n',
};

export function tableCases(format) {
  const expected = tables[format];
  const cases = [];
  for (const options of [`format=${format} align=left`, `align=left format=${format}`]) {
    const manuscript = `@table data.txt ${options}\n`;
    cases.push({ manuscript, expected, input: '\uFEFF' + expected.replaceAll('\n', '\r\n'), offset: null });
    const variants = [expected];
    for (const parity of [0, 1]) {
      let line = 0;
      const input = expected.replaceAll('\n', () => line++ % 2 === parity ? '\r\n' : '\n');
      variants.push(input);
      cases.push({ manuscript, expected, input, offset: null });
    }
    for (const variant of variants) {
      const bytes = Buffer.from(variant);
      for (const [offset, byte] of bytes.entries()) {
        // Replacing the first LF of an adjacent pair creates a valid CRLF.
        if (byte !== 10 || bytes[offset - 1] === 13 || bytes[offset + 1] === 10) continue;
        const broken = Buffer.from(bytes);
        broken[offset] = 13;
        cases.push({ manuscript, expected, input: broken.toString(), offset });
      }
    }
  }
  return cases;
}

// The generated tables contain at most one Text inline per cell. Keep the row and
// column nesting so that a moved empty cell changes the comparison.
export function inspectedCells(ir) {
  const values = label => {
    const lines = ir.split('\n');
    const start = lines.findIndex(line => line.trimStart().startsWith(label + ' ='));
    if (start < 0) throw new Error('Missing IR field ' + label);
    let line = start;
    let value = lines[line].slice(lines[line].indexOf(' =') + 2).trim() || lines[++line].trim();
    if (value.startsWith('- ')) {
      const rows = [];
      while (line < lines.length && lines[line].trimStart().startsWith('- ')) {
        rows.push(lines[line++].trim().slice(2));
      }
      value = '[' + rows.join(',') + ']';
    }
    return JSON.parse(value.replace(/\[Text @\d+\.\.\d+ ("(?:\\.|[^"\\])*")\]/gu, '$1'));
  };
  return [values('tableHeader'), ...values('tableRows')].map(row =>
    row.map(cell => Array.isArray(cell) && cell.length === 0 ? '' : cell));
}
