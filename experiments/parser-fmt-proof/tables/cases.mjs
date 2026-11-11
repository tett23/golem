// Quoted CSV newlines and trailing spaces are significant cell contents.
const tables = {
  csv: '名,b\n"x\ny",\n,z  \n',
  tsv: '名\tb\nx\t\n\tz  \n',
};

export function tableCases(format) {
  const expected = tables[format];
  const cases = [];
  for (const options of [`format=${format} align=left`, `align=left format=${format}`]) {
    const manuscript = `@table data.txt ${options}\n`;
    cases.push({ manuscript, expected, input: '\uFEFF' + expected.replaceAll('\n', '\r\n'), offset: null });
    const bytes = Buffer.from(expected);
    for (const [offset, byte] of bytes.entries()) {
      if (byte !== 10) continue;
      const broken = Buffer.from(bytes);
      broken[offset] = 13;
      cases.push({ manuscript, expected, input: broken.toString(), offset });
    }
  }
  return cases;
}
