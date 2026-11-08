// The host of golem.wasm under the node:wasi of Node (docs/adr/0199): the
// one host script of the CI. No directory is preopened, so the wasm cannot
// open a file; the host reads the files of the project and passes their
// bytes in the input frame.
//
//   node run.mjs build WASM DIR PDF   builds the files under DIR (build/
//                                     left out): writes the PDF to PDF, or
//                                     removes PDF when there is none; the
//                                     JSON of the diagnostics to stderr;
//                                     exits 1 when it has an error, as
//                                     golem build does
//   node run.mjs check WASM DIR       the checks of the module: its exports
//                                     and imports, an input frame it cannot
//                                     read, a manifest with [plugins], and
//                                     the same bytes from DIR twice in one
//                                     instance and once in a new one
//
// The other hosts (scripts/wasm/run-wasmtime.sh, docs/adr/0238) read and
// write the frames here, so that one implementation does it:
//
//   node run.mjs frame DIR            writes the input frame of the files
//                                     under DIR to stdout
//   node run.mjs result PDF           reads a result frame from stdin and
//                                     does with it what build does
//   node run.mjs call WASM            passes the input frame of stdin to
//                                     golem_build_pdf of a new instance and
//                                     writes its result frame to stdout, as
//                                     run-wasmtime.c call does
//
// An input frame that the module cannot read (status 1) exits 2.
import { WASI } from 'node:wasi';
import { readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';

const EXPORTS = ['_initialize', 'golem_alloc', 'golem_build_pdf', 'golem_free', 'golem_result_len', 'golem_version', 'hs_init', 'memory'];

// A new instance, initialised: _initialize once, hs_init(0, 0) once.
async function instantiate(module) {
  const wasi = new WASI({ version: 'preview1', args: ['golem.wasm'], env: {}, preopens: {}, returnOnExit: true });
  const instance = await WebAssembly.instantiate(module, wasi.getImportObject());
  wasi.initialize(instance);
  instance.exports.hs_init(0, 0);
  return instance.exports;
}

// The bytes of a buffer the module handed out, which it then frees.
function take(ex, ptr) {
  const len = ex.golem_result_len(ptr);
  const bytes = Buffer.from(new Uint8Array(ex.memory.buffer, ptr, len));
  ex.golem_free(ptr);
  return bytes;
}

function u32(n) {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n);
  return b;
}

// The input frame of files [path, bytes] (Golem.Wasm.Frame).
function frame(files) {
  return Buffer.concat(files.flatMap(([p, c]) => {
    const raw = Buffer.from(p, 'utf8');
    return [u32(raw.length), raw, u32(c.length), c];
  }));
}

// The result frame of one call of golem_build_pdf.
function call(ex, input) {
  const ptr = ex.golem_alloc(input.length);
  new Uint8Array(ex.memory.buffer, ptr, input.length).set(input);
  const out = ex.golem_build_pdf(ptr, input.length);
  ex.golem_free(ptr);
  return take(ex, out);
}

// The result of one call of golem_build_pdf: { status, pdf, json }.
function buildFrame(ex, input) {
  return parseResult(call(ex, input));
}

// Whether the bytes are one whole result frame, no more.
function wellFormed(r) {
  if (r.length < 9) return false;
  const pdfLen = r.readUInt32LE(1);
  if (r.length < 9 + pdfLen) return false;
  return r.length === 9 + pdfLen + r.readUInt32LE(5 + pdfLen);
}

// The parts of a result frame: { status, pdf, json }.
function parseResult(r) {
  const status = r[0];
  const pdfLen = r.readUInt32LE(1);
  const pdf = r.subarray(5, 5 + pdfLen);
  const jsonLen = r.readUInt32LE(5 + pdfLen);
  const json = r.subarray(9 + pdfLen, 9 + pdfLen + jsonLen);
  return { status, pdf: Buffer.from(pdf), json: Buffer.from(json) };
}

// Every file under DIR but build/, by its path from DIR with /, in code point order.
async function filesOf(dir, rel = '') {
  const out = [];
  for (const e of await readdir(join(dir, rel), { withFileTypes: true })) {
    const p = rel === '' ? e.name : `${rel}/${e.name}`;
    if (e.isDirectory()) {
      if (p !== 'build') out.push(...await filesOf(dir, p));
    } else {
      out.push([p, await readFile(join(dir, p))]);
    }
  }
  return out.sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
}

function hasError(json) {
  return JSON.parse(json.toString('utf8')).some((d) => d.severity === 'error');
}

async function build(wasmPath, dir, pdfPath) {
  const ex = await instantiate(await WebAssembly.compile(await readFile(wasmPath)));
  return writeResult(buildFrame(ex, frame(await filesOf(dir))), pdfPath);
}

// The PDF to PDF (removed when there is none), the JSON to stderr, and the
// exit code of golem build; 2 for status 1.
async function writeResult(r, pdfPath) {
  if (r.status !== 0) {
    process.stderr.write(`the module could not read the input frame (status ${r.status})\n`);
    return 2;
  }
  if (r.pdf.length > 0) await writeFile(pdfPath, r.pdf);
  else await rm(pdfPath, { force: true });
  process.stderr.write(r.json);
  return hasError(r.json) ? 1 : 0;
}

async function check(wasmPath, dir) {
  const module = await WebAssembly.compile(await readFile(wasmPath));
  const failures = [];
  const expect = (what, ok) => {
    console.log(`${ok ? 'ok' : 'FAIL'}: ${what}`);
    if (!ok) failures.push(what);
  };
  const exports = WebAssembly.Module.exports(module).map((e) => e.name).sort();
  expect(`the exports are ${EXPORTS.join(', ')} (got ${exports.join(', ')})`, exports.join() === EXPORTS.join());
  const imports = [...new Set(WebAssembly.Module.imports(module).map((i) => i.module))];
  expect(`every import is of wasi_snapshot_preview1 (got ${imports.join(', ')})`, imports.length === 1 && imports[0] === 'wasi_snapshot_preview1');

  const files = await filesOf(dir);
  const ex = await instantiate(module);
  const version = take(ex, ex.golem_version()).toString('utf8');
  expect(`golem_version is VERSION (${version})`, version === (await readFile(new URL('../../VERSION', import.meta.url), 'utf8')).trim());

  const bad = buildFrame(ex, frame([['./manifest.toml', Buffer.from('')]]));
  expect('a path that is not normalised is status 1, with no PDF and no JSON', bad.status === 1 && bad.pdf.length === 0 && bad.json.length === 0);

  const first = buildFrame(ex, frame(files));
  const second = buildFrame(ex, frame(files));
  const fresh = buildFrame(await instantiate(module), frame(files));
  expect('a PDF of the project', first.status === 0 && first.pdf.length > 0);
  expect('the same input twice in one instance gives the same bytes', first.pdf.equals(second.pdf) && first.json.equals(second.json));
  expect('a new instance gives the same bytes', first.pdf.equals(fresh.pdf) && first.json.equals(fresh.json));

  const manifest = files.find(([p]) => p === 'manifest.toml');
  const withPlugin = files.map(([p, c]) => [p, p === 'manifest.toml' ? Buffer.concat([manifest[1], Buffer.from('\n[plugins.sample]\npath = "plugins/sample.wasm"\n')]) : c]);
  const plugin = buildFrame(ex, frame(withPlugin));
  const codes = JSON.parse(plugin.json.toString('utf8')).map((d) => d.code);
  expect(`[plugins]: no PDF and one G06106 (got ${codes.join(', ')})`, plugin.status === 0 && plugin.pdf.length === 0 && codes.filter((c) => c === 'G06106').length === 1);
  return failures.length === 0 ? 0 : 1;
}

async function stdin() {
  const chunks = [];
  for await (const c of process.stdin) chunks.push(c);
  return Buffer.concat(chunks);
}

async function writeStdout(bytes) {
  await new Promise((resolve, reject) => process.stdout.write(bytes, (e) => (e ? reject(e) : resolve())));
}

const [command, ...args] = process.argv.slice(2);
if (command === 'build' && args.length === 3) process.exitCode = await build(...args);
else if (command === 'check' && args.length === 2) process.exitCode = await check(...args);
else if (command === 'frame' && args.length === 1) await writeStdout(frame(await filesOf(args[0])));
else if (command === 'result' && args.length === 1) {
  const r = await stdin();
  if (!wellFormed(r)) {
    process.stderr.write(`not a result frame (${r.length} bytes)\n`);
    process.exitCode = 2;
  } else process.exitCode = await writeResult(parseResult(r), args[0]);
}
else if (command === 'call' && args.length === 1) {
  const ex = await instantiate(await WebAssembly.compile(await readFile(args[0])));
  await writeStdout(call(ex, await stdin()));
} else {
  process.stderr.write('usage: node run.mjs build WASM DIR PDF | node run.mjs check WASM DIR | node run.mjs frame DIR | node run.mjs result PDF | node run.mjs call WASM\n');
  process.exitCode = 2;
}
