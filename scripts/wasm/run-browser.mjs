// golem.wasm in Chromium or Safari, with browser_wasi_shim (docs/adr/0234
// section 5): the host of scripts/wasm/compare.sh --browser BROWSER.
//
//   node run-browser.mjs build BROWSER WASM DIR
//
// serves the files under DIR (build/ left out), golem.wasm and
// scripts/wasm/browser/run.html with scripts/browser/serve.mjs on
// 127.0.0.1, opens run.html in BROWSER (chromium or safari, by
// scripts/browser/browsers.mjs) and builds the PDF there. It prints the
// SHA-256 of the PDF, or - when there is none, on stdout, and the JSON of
// the diagnostics on stderr; it exits 1 when the JSON has an error, as
// golem build does, 2 when the module cannot read the input frame
// (status 1), and 3 when the browser or the page failed (the error on
// stderr). The browser_wasi_shim of scripts/browser/package-lock.json
// must be installed (npm ci in scripts/browser).
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import process from 'node:process';
import { openBrowser } from '../browser/browsers.mjs';
import { serve } from '../browser/serve.mjs';

const SHIM = new URL('../browser/node_modules/@bjorn3/browser_wasi_shim/dist/', import.meta.url);

// Every file under DIR but build/, by its path from DIR with /, in code point order.
async function filesOf(dir, rel = '') {
  const out = [];
  for (const e of await readdir(join(dir, rel), { withFileTypes: true })) {
    const p = rel === '' ? e.name : `${rel}/${e.name}`;
    if (e.isDirectory()) {
      if (p !== 'build') out.push(...await filesOf(dir, p));
    } else {
      out.push(p);
    }
  }
  return out.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
}

async function build(browser, wasmPath, dir) {
  const pages = {
    '/__golem/run.html': await readFile(new URL('browser/run.html', import.meta.url)),
    '/__golem/golem.wasm': await readFile(wasmPath),
    '/__golem/files.json': JSON.stringify(await filesOf(dir)),
  };
  for (const f of await readdir(SHIM)) if (f.endsWith('.js')) pages[`/__golem/shim/${f}`] = await readFile(new URL(f, SHIM));
  const server = await serve(dir, { pages });
  const page = await openBrowser(browser);
  let r;
  try {
    await page.open(`${server.url}/__golem/run.html`);
    r = await page.evaluateAsync('golemBuild()');
  } finally {
    await page.close();
    await server.close();
  }
  if (r.status !== 0) {
    process.stderr.write(`the module could not read the input frame (status ${r.status})\n`);
    return 2;
  }
  process.stdout.write(`${r.sha ?? '-'}\n`);
  process.stderr.write(r.json);
  return JSON.parse(r.json).some((d) => d.severity === 'error') ? 1 : 0;
}

const [command, ...args] = process.argv.slice(2);
if (command === 'build' && args.length === 3) {
  try {
    process.exitCode = await build(...args);
  } catch (e) {
    process.stderr.write(`run-browser: ${e.stack ?? e}\n`);
    process.exitCode = 3;
  }
} else {
  process.stderr.write('usage: node run-browser.mjs build BROWSER WASM DIR\n');
  process.exitCode = 2;
}
