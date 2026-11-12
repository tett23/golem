import { copyFileSync, cpSync, existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

export function saveProjectFailure(suite, dir, original, error, caseName = '', testFile = 'check.test.mjs') {
  const output = join(process.env.ROUND_TRIP_FAILURES || 'round-trip-failures', suite, caseName);
  mkdirSync(output, { recursive: true });
  writeFileSync(join(output, 'original.gm'), original);
  for (const name of ['a.gm', 'fn/book.emet']) {
    const file = join(dir, name);
    if (existsSync(file)) copyFileSync(file, join(output, name === 'a.gm' ? 'actual.gm' : 'book.emet'));
  }
  const data = join(dir, 'data');
  if (existsSync(data)) cpSync(data, join(output, 'data'), { recursive: true });
  writeFileSync(join(output, 'failure.txt'), String(error.stack || error) + '\n');
  writeFileSync(join(output, 'reproduce.txt'), `node --test experiments/parser-fmt-proof/${suite}/${testFile}\n`);
}
