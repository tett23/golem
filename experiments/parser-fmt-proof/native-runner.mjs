import assert from 'node:assert/strict';
import {readdirSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';

export const nativeTests = [
  'quoted-values.native-test.mjs', 'mixed-values.native-test.mjs',
  'lowered-cst.native-test.mjs', 'raw-cst.native-test.mjs',
  'token-values.native-test.mjs', 'trace-values.native-test.mjs',
  'trace-diagnostics.native-test.mjs', 'positional-values.native-test.mjs',
];
export function validateNativeTests(directory) {
  const actual = readdirSync(directory).filter(name => name.endsWith('.native-test.mjs')).sort();
  assert.deepEqual(actual, [...nativeTests].sort(), 'native observer manifest mismatch');
  return nativeTests;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const directory = fileURLToPath(new URL('./arguments/', import.meta.url));
  const files = validateNativeTests(directory);
  console.log('Local native observers: ' + files.length + ' files; no CI claim');
  const result = spawnSync(process.execPath, ['--test', ...files.map(name => resolve(directory, name))],
    {stdio: 'inherit'});
  if (result.error) throw result.error;
  process.exitCode = result.status ?? 1;
}
