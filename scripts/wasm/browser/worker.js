// Builds the project inside a module Worker (docs/adr/0309). The page
// receives only the result status, PDF hash and length, and diagnostics.
const u32 = (n) => { const b = new Uint8Array(4); new DataView(b.buffer).setUint32(0, n, true); return b; };

function frame(files) {
  const enc = new TextEncoder();
  const parts = files.flatMap(([p, c]) => { const raw = enc.encode(p); return [u32(raw.length), raw, u32(c.length), c]; });
  const out = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

const hex = (buf) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');

async function build() {
  let step = 'import browser_wasi_shim';
  try {
    const { WASI, File, OpenFile, ConsoleStdout } = await import('./shim/index.js');
    step = 'fetch the files';
    const paths = await (await fetch('files.json')).json();
    const files = await Promise.all(paths.map(async (p) => [p, new Uint8Array(await (await fetch('/' + p.split('/').map(encodeURIComponent).join('/'))).arrayBuffer())]));
    const fds = [new OpenFile(new File([])), ConsoleStdout.lineBuffered(() => {}), ConsoleStdout.lineBuffered(() => {})];
    const wasi = new WASI(['golem.wasm'], [], fds);
    step = 'instantiate golem.wasm';
    const { instance } = await WebAssembly.instantiateStreaming(fetch('golem.wasm'), { wasi_snapshot_preview1: wasi.wasiImport });
    step = 'initialize';
    wasi.initialize(instance);
    const ex = instance.exports;
    ex.hs_init(0, 0);
    step = 'golem_build_pdf';
    const input = frame(files);
    const ptr = ex.golem_alloc(input.length);
    new Uint8Array(ex.memory.buffer, ptr, input.length).set(input);
    const out = ex.golem_build_pdf(ptr, input.length);
    ex.golem_free(ptr);
    const len = ex.golem_result_len(out);
    const r = new Uint8Array(ex.memory.buffer, out, len).slice();
    ex.golem_free(out);
    const view = new DataView(r.buffer);
    const status = r[0];
    const pdfLen = view.getUint32(1, true);
    const pdf = r.subarray(5, 5 + pdfLen);
    const jsonLen = view.getUint32(5 + pdfLen, true);
    const json = new TextDecoder().decode(r.subarray(9 + pdfLen, 9 + pdfLen + jsonLen));
    step = 'the SHA-256 of the PDF';
    const sha = pdfLen === 0 ? null : hex(await crypto.subtle.digest('SHA-256', pdf));
    return { status, sha, pdfLen, json };
  } catch (e) {
    throw new Error(`${step}: ${e}`);
  }
}

build().then(
  (v) => postMessage({ ok: true, v }),
  (e) => postMessage({ ok: false, e: String(e.message ?? e) }),
);
