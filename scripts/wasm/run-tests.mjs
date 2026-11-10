// Runs one test suite of the packages of golem.wasm, built for wasm32, under
// the node:wasi of Node (docs/adr/0293).
//
//   node run-tests.mjs SUITE.wasm PACKAGE [ARGUMENT...]
//
// The root of the repository is preopened at /, and a new host temporary
// directory is preopened at /tmp for this run and removed after it ends.
// The suite gets
// GOLEM_TEST_PACKAGE_DIR=/modules/PACKAGE, where the main of the suite
// moves first (Golem.TestSupport.PackageDirectory), and TASTY_NO_CREATE=true,
// so that a missing golden file fails instead of being written. No other
// environment variable is passed, and stdin is /dev/null. The arguments
// after PACKAGE are those of the suite (tasty's -p, for one). The exit code
// is that of the suite; a usage error exits 2.
import { WASI } from 'node:wasi';
import { mkdtempSync, openSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import process from 'node:process';

const [wasm, pkg, ...rest] = process.argv.slice(2);
if (wasm === undefined || pkg === undefined || !/^[a-z0-9-]+$/.test(pkg)) {
  process.stderr.write('usage: node run-tests.mjs SUITE.wasm PACKAGE [ARGUMENT...]\n');
  process.exit(2);
}
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const temp = mkdtempSync(join(tmpdir(), 'golem-wasm-tests-'));
try {
  const wasi = new WASI({
    version: 'preview1',
    args: [basename(wasm, '.wasm'), ...rest],
    env: { GOLEM_TEST_PACKAGE_DIR: `/modules/${pkg}`, TASTY_NO_CREATE: 'true' },
    preopens: { '/': root, '/tmp': temp },
    stdin: openSync('/dev/null', 'r'),
    returnOnExit: true,
  });
  const module = await WebAssembly.compile(readFileSync(wasm));
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  process.exitCode = wasi.start(instance);
} finally {
  rmSync(temp, { recursive: true, force: true });
}
