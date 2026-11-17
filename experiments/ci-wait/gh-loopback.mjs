// Use the installed gh against a loopback HTTP server, with a dummy token.
import { createServer } from 'node:http';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import assert from 'node:assert/strict';
const run = promisify(execFile);
const dir = await mkdtemp(join(tmpdir(), 'golem-wait-gh-'));
const gh = (await run('sh', ['-c', 'command -v gh'])).stdout.trim();
let mode = 'rate', count = 0;
const server = createServer((req, res) => {
  count++;
  if (mode === 'two-pages') {
    const artifact = req.url.includes('/artifacts?name=');
    const last = req.url.endsWith('page=2');
    const headers = {'Content-Type':'application/json'};
    if (!artifact && !last) headers.Link = '<http://127.0.0.1:' + server.address().port + '/repos/test/test/actions/runs/1/attempts/1/jobs?page=2>; rel="next"';
    res.writeHead(200, headers);
    res.end(JSON.stringify(artifact ? {artifacts:[]} : {jobs:[{name:last ? 'ci / producer' : 'producer',status:'in_progress'}]}));
    return;
  }
  assert.equal(req.url, '/repos/test/test/actions/runs/1/artifacts?name=visual-pdfs');
  const code = mode === 'denied' || count === 1 ? 403 : 200;
  res.writeHead(code, {'Content-Type':'application/json', 'Retry-After':'1'});
  res.end(JSON.stringify(code === 200 ? {artifacts:[{expired:false}]} :
    {message:mode === 'denied' ? 'Resource not accessible by integration' : 'API rate limit exceeded for installation'}));
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await writeFile(join(dir, 'gh'), `#!/bin/sh
set -eu
[ "$1" = api ]
shift
paginate=
if [ "$1" = --paginate ]; then paginate=--paginate; shift; fi
case "$1" in repos/*) endpoint="$1"; shift;; *) exit 99;; esac
exec "$REAL_GH" api $paginate "$BASE/$endpoint" "$@"
`, {mode:0o755});
  for (mode of ['rate','denied','two-pages']) {
    count = 0;
    const env = {...process.env, PATH:dir + ':' + process.env.PATH, REAL_GH:gh, GH_REPO:'test/test',
      GH_TOKEN:'loopback-test-only', GH_NO_UPDATE_NOTIFIER:'1', BASE:'http://127.0.0.1:' + server.address().port};
    let code = 0, stderr;
    try {
      ({stderr} = await run('sh', ['scripts/visual/wait-pdfs.sh', '1', '1', 'producer'], {env, timeout:10000}));
    } catch(e) { code=e.code; stderr=e.stderr; }
    console.log(JSON.stringify({mode, code, requests:count, stderr:stderr.trim().split('\n')}));
    assert.equal(code, mode === 'rate' ? 0 : 1);
    assert.equal(count, mode === 'rate' ? 2 : mode === 'two-pages' ? 3 : 1);
    if (mode === 'two-pages') assert.ok(stderr.includes('has 2 jobs'));
  }
} finally {
  await new Promise(resolve => server.close(resolve));
  await rm(dir, {recursive:true,force:true});
}
