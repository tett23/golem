// Run one case with: node experiments/parser-fmt-proof/tables/check.mjs csv-0
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tableCases } from './cases.mjs';

const root = fileURLToPath(new URL('../../../', import.meta.url));
const fixture = join(root, 'modules/golem-driver/test/fixtures/int-width');
const read = file => readFileSync(file, 'utf8');
const filter = process.argv[2];
let tested = 0;

for (const format of ['csv', 'tsv']) {
  for (const [index, c] of tableCases(format).entries()) {
    const name = format + '-' + index;
    if (filter && filter !== name) continue;
    tested++;
    const dir = mkdtempSync(join(tmpdir(), 'golem-table-'));
    function run(args, expected = 0) {
      const result = spawnSync(process.env.GOLEM || 'golem', args, { cwd: dir, encoding: 'utf8' });
      if (result.error) throw result.error;
      assert.equal(result.status, expected, args.join(' ') + '\n' + result.stderr);
      return result;
    }
    const source = join(dir, 'int-width.gm');
    const table = join(dir, 'data.txt');
    try {
      writeFileSync(join(dir, 'manifest.toml'), read(join(fixture, 'manifest.toml')).replace('[targets.pdf]', '[targets.html]'));
      copyFileSync(join(fixture, 'style.toml'), join(dir, 'style.toml'));
      mkdirSync(join(dir, 'fonts'));
      copyFileSync(join(fixture, '../kanikosen/fonts/NotoSerifJP-Regular.otf'), join(dir, 'fonts/ja.otf'));
      copyFileSync(join(root, 'modules/golem-font/test/fonts/SourceSansPro-Regular.otf'), join(dir, 'fonts/latin.otf'));
      writeFileSync(source, c.manuscript);
      writeFileSync(table, c.input);
      if (c.offset !== null) {
        const { stderr } = run(['check', '--format', 'json'], 1);
        const spans = JSON.parse(stderr).map(({ code, span }) => [code, span.file, span.start, span.end]);
        assert.deepEqual(spans, [['G02082', 'data.txt', c.offset, c.offset + 1]]);
      } else {
        run(['check', '--format', 'json']);
      }
      run(['fmt']);
      assert.equal(read(table), c.expected);
      const formatted = read(source);
      run(['check', '--format', 'json']);
      run(['fmt']);
      assert.equal(read(source), formatted);
      assert.equal(read(table), c.expected);
    } catch (error) {
      const evidence = join(process.env.ROUND_TRIP_FAILURES || 'round-trip-failures', name);
      mkdirSync(evidence, { recursive: true });
      writeFileSync(join(evidence, 'original.gm'), c.manuscript);
      writeFileSync(join(evidence, 'original-table.txt'), c.expected);
      writeFileSync(join(evidence, 'input.gm'), c.manuscript);
      writeFileSync(join(evidence, 'input-table.txt'), c.input);
      writeFileSync(join(evidence, 'reproduce.txt'), 'node experiments/parser-fmt-proof/tables/check.mjs ' + name + '\n');
      console.error(name, error);
      process.exitCode = 1;
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  }
}
assert.ok(tested, 'no matching table case');
console.log(tested + ' Golem ADR 0351 I9/I10 cases');
