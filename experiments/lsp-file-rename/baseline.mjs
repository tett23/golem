import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, rename, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const root = await mkdtemp(path.join(tmpdir(), 'golem-file-rename-'));
await writeFile(path.join(root, 'manifest.toml'), 'chapters=["a.gm"]\n[metadata]\nid="urn:uuid:11111111-2222-4333-8444-555555555555"\ntitle="T"\nlanguage="ja"\ndate=2026-10-11\n[targets.html]\n');
await writeFile(path.join(root, 'a.gm'), '# A\n');
const server = spawn(process.env.GOLEM_BIN, ['lsp'], { cwd: root, stdio: ['pipe', 'pipe', 'ignore'] });
const stopped = new Promise(resolve => server.on('exit', resolve));
const pending = new Map();
let buffer = Buffer.alloc(0);
let nextId = 0;
function send(message) {
  const payload = Buffer.from(JSON.stringify({ jsonrpc: '2.0', ...message }));
  server.stdin.write(Buffer.concat([Buffer.from('Content-Length: ' + payload.length + '\r\n\r\n'), payload]));
}
function request(method, params) {
  const id = ++nextId;
  return new Promise(resolve => {
    const timer = setTimeout(() => { pending.delete(id); resolve({ timedOut: true }); }, 5000);
    pending.set(id, message => { clearTimeout(timer); resolve(message); });
    send({ id, method, params });
  });
}
server.stdout.on('data', chunk => {
  buffer = Buffer.concat([buffer, chunk]);
  while (true) {
    const end = buffer.indexOf('\r\n\r\n');
    if (end < 0) return;
    const len = Number(/Content-Length: (\d+)/i.exec(buffer.subarray(0, end).toString())[1]);
    if (buffer.length < end + 4 + len) return;
    const m = JSON.parse(buffer.subarray(end + 4, end + 4 + len));
    buffer = buffer.subarray(end + 4 + len);
    if (m.method && m.id !== undefined) send({ id: m.id, result: m.method === 'workspace/configuration' ? m.params.items.map(() => null) : null });
    else if (pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  }
});
try {
  const uri = p => pathToFileURL(path.join(root,p)).href;
  const init = await request('initialize', { processId: process.pid, rootUri: uri(''), capabilities: { workspace: { fileOperations: { willRename: true, didRename: true }, workspaceEdit: { documentChanges: true } }, general: { positionEncodings: ['utf-16'] } } });
  assert.ok(init.result.capabilities);
  console.log('initialize fileOperations=' + JSON.stringify(init.result.capabilities.workspace?.fileOperations ?? null));
  send({ method: 'initialized', params: {} });
  if (process.env.PROBE === '1') {
    await mkdir(path.join(root, '章'));
    await writeFile(path.join(root, '章','a.gm'), '本文');
    const original = '😀\n@import ./章/a.gm as one\n@import "章/a.gm" as two\n本文 章/a.gm\n';
    send({method:'textDocument/didOpen',params:{textDocument:{uri:uri('a.gm'),version:7,languageId:'golem',text:original}}});
    const entry = {oldUri:uri('章'),newUri:uri('新章')};
    const requestEdits = files => request('workspace/willRenameFiles',{files});
    const r = await requestEdits([entry]);
    const [docEdit] = r.result.documentChanges;
    assert.equal(docEdit.textDocument.version,7);
    assert.equal(docEdit.textDocument.uri,uri('a.gm'));
    assert.ok(init.result.capabilities.workspace.fileOperations.willRename.filters.length);
    assert.ok(init.result.capabilities.workspace.fileOperations.didRename.filters.length);
    assert.equal((await requestEdits([entry,{oldUri:uri('章/a.gm'),newUri:uri('別.gm')}])).error.code,-32600);
    const edits = docEdit.edits;
    assert.deepEqual(edits,[
      {range:{start:{line:1,character:8},end:{line:1,character:16}},newText:'新章/a.gm'},
      {range:{start:{line:2,character:8},end:{line:2,character:16}},newText:'"新章/a.gm"'},
    ]);
    assert.deepEqual((await requestEdits([entry,entry])).result,r.result);
    assert.equal((await requestEdits([])).result,null);
    console.log('live didOpen version=7, on-disk imports=0, edits=' + JSON.stringify(edits));
    const lines=original.split('\n');
    for (const {range:{start,end},newText} of edits.toReversed()) {
      lines[start.line]=lines[start.line].slice(0,start.character)+newText+lines[start.line].slice(end.character);
    }
    send({method:'textDocument/didChange',params:{textDocument:{uri:uri('a.gm'),version:8},contentChanges:[{text:lines.join('\n')}] }});
    await rename(path.join(root,'章'),path.join(root,'新章'));
    send({method:'workspace/didRenameFiles',params:{files:[entry]}});
    assert.equal((await requestEdits([entry])).result,null);
    console.log('duplicate=2 edits, conflict=-32600, empty=null, after didChange/rename/didRename=null');
  } else {
  const res = await request('workspace/willRenameFiles', { files: [{oldUri: uri('a.gm'), newUri: uri('b.gm')}] });
  console.log('willRenameFiles=' + JSON.stringify(res.error ?? (res.timedOut ? { timedOut: true } : res.result)));
  }
  await request('shutdown', null);
  send({ method: 'exit' });
} finally {
  server.stdin.end(); server.kill(); await stopped; await rm(root, { recursive: true, force: true });
}
