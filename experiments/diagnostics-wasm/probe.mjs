// gh run download 42892137240 --repo tett23/golem -n golem-wasm -D /tmp/golem-0322-run
// node experiments/diagnostics-wasm/probe.mjs /tmp/golem-0322-run/golem.wasm /path/to/0a8d21a0/scripts/wasm/run.mjs
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { WASI } from 'node:wasi';
const [, , wasm, runner] = process.argv;
const bytes = await readFile(wasm);
const sha256 = createHash('sha256').update(bytes).digest('hex');
assert.equal(sha256, '38c216a5b0403bf4b3e520ccadef7fd024fecb02b9b4799b6070d846f7d6d0cb');
const module = await WebAssembly.compile(bytes);
const wasi = new WASI({ version: 'preview1', args: ['golem.wasm'], env: {}, preopens: {} });
const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
wasi.initialize(instance);
const ex = instance.exports;
ex.hs_init(0, 0);
const ptr = ex.golem_version();
const version = Buffer.from(ex.memory.buffer, ptr, ex.golem_result_len(ptr)).toString('utf8');
ex.golem_free(ptr);
const frontend = spawnSync(process.execPath, [runner, 'preflight', wasm, '.'], { encoding: 'utf8' });
assert.equal(frontend.status, 2);
assert.ok(frontend.stderr.includes('usage:'));
console.log(JSON.stringify({ run:42892137240, artifact:13799726596, head:'0a8d21a091d830573fb6229111ed744f74162afd', sha256, node:process.version, version,
  exports:Object.keys(ex).sort(), preflightFrontendExit:frontend.status, usage:frontend.stderr.split('\n').find(s=>s.startsWith('usage:')), A2:'未測定。WASM の公開 API と実行用 CLI に preflight がない。' }, null, 2));
