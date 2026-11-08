// The tests that need no browser (docs/adr/0234): the commands of
// webdriver.mjs against a fake WebDriver server on 127.0.0.1 and its
// handling of the error answers, serve.mjs, the PNG decoder, the reading of
// text-emphasis-style, the comparison of the ink of svg-text.mjs, and the
// line of DevTools of cdp.mjs. The prepare job of
// .github/workflows/browser.yml runs them.
//
//   node --test scripts/browser/test/unit.test.mjs
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import { PassThrough } from 'node:stream';
import { fileURLToPath } from 'node:url';
import { chromiumArgs } from '../browsers.mjs';
import { devtoolsUrl } from '../cdp.mjs';
import { emphasis, KENTEN } from '../html-checks.mjs';
import { decode } from '../png.mjs';
import { fileOf, serve } from '../serve.mjs';
import { compareInk, judge } from '../svg-text.mjs';
import { connect } from '../webdriver.mjs';

const ROOT = fileURLToPath(new URL('../../../', import.meta.url));

describe('webdriver.mjs against a fake server', () => {
  let server; let base; let log; let answers;
  before(async () => {
    server = createServer((req, res) => {
      let body = '';
      req.on('data', (c) => { body += c; });
      req.on('end', () => {
        log.push({ method: req.method, url: req.url, body: body === '' ? undefined : JSON.parse(body) });
        const a = answers(req.method, req.url) ?? { status: 200, value: null };
        res.writeHead(a.status, { 'content-type': 'application/json' });
        res.end(a.raw ?? JSON.stringify({ value: a.value }));
      });
    });
    await new Promise((r) => server.listen(0, '127.0.0.1', r));
    base = `http://127.0.0.1:${server.address().port}`;
  });
  after(() => new Promise((r) => server.close(r)));
  const session = (method, url) => (method === 'POST' && url === '/session'
    ? { status: 200, value: { sessionId: 'S1', capabilities: { browserName: 'Safari', browserVersion: '27.2' } } }
    : undefined);

  test('a new session asks for safari with the timeouts of the checks and gives browserVersion', async () => {
    log = []; answers = session;
    const page = await connect(base);
    assert.deepEqual(log[0], { method: 'POST', url: '/session', body: { capabilities: { alwaysMatch: { browserName: 'safari', timeouts: { script: 600000, pageLoad: 300000 } } } } });
    assert.equal(page.browserVersion, '27.2');
    assert.equal(page.failures(), null);
  });

  test('the commands of the six functions', async () => {
    log = [];
    answers = (m, u) => session(m, u) ?? ({
      'POST /session/S1/execute/sync': { status: 200, value: 3 },
      'POST /session/S1/execute/async': { status: 200, value: { ok: true, v: 'done' } },
      'GET /session/S1/screenshot': { status: 200, value: Buffer.from('png').toString('base64') },
    })[`${m} ${u}`];
    const page = await connect(base);
    await page.open('http://127.0.0.1:1/x.html');
    assert.equal(await page.evaluate('1 + 2'), 3);
    assert.equal(await page.evaluateAsync('Promise.resolve("done")'), 'done');
    await page.setWindowSize(800, 600);
    assert.equal((await page.screenshot()).toString(), 'png');
    await page.close();
    assert.deepEqual(log.slice(1).map((l) => `${l.method} ${l.url}`), [
      'POST /session/S1/url', 'POST /session/S1/execute/sync', 'POST /session/S1/execute/async',
      'POST /session/S1/window/rect', 'GET /session/S1/screenshot', 'DELETE /session/S1',
    ]);
    assert.deepEqual(log[1].body, { url: 'http://127.0.0.1:1/x.html' });
    assert.deepEqual(log[2].body, { script: 'return (1 + 2);', args: [] });
    assert.match(log[3].body.script, /Promise\.resolve\("done"\)/);
    assert.match(log[3].body.script, /arguments\[arguments\.length - 1\]/);
    assert.deepEqual(log[4].body, { width: 800, height: 600 });
  });

  test('an error answer throws with the error and the message', async () => {
    answers = (m, u) => session(m, u) ?? (u === '/session/S1/execute/sync'
      ? { status: 500, value: { error: 'javascript error', message: 'x is not defined', stacktrace: '' } }
      : undefined);
    const page = await connect(base);
    await assert.rejects(page.evaluate('x'), (e) => e.error === 'javascript error' && /x is not defined/.test(e.message));
  });

  test('a script that throws in the page throws', async () => {
    answers = (m, u) => session(m, u) ?? (u === '/session/S1/execute/async' ? { status: 200, value: { ok: false, e: 'Error: no' } } : undefined);
    const page = await connect(base);
    await assert.rejects(page.evaluateAsync('Promise.reject(new Error("no"))'), /the page threw: Error: no/);
  });

  test('a failed new session throws (I7: the job fails)', async () => {
    answers = () => ({ status: 500, value: { error: 'session not created', message: 'Could not create a session: You must enable Allow remote automation' } });
    await assert.rejects(connect(base), (e) => e.error === 'session not created');
  });

  test('an answer that is not JSON throws', async () => {
    answers = () => ({ status: 502, raw: '<html>bad gateway</html>' });
    await assert.rejects(connect(base), (e) => e.error === 'invalid response');
  });
});

describe('serve.mjs', () => {
  test('a path with .. stays under the root', () => {
    assert.equal(fileOf('/r', '/../etc/passwd'), '/r/etc/passwd');
    assert.equal(fileOf('/r', '/a/../../x'), '/r/x');
    assert.equal(fileOf('/r', '/%2e%2e/x'), '/r/x');
    assert.equal(fileOf('/r', '/%E0%A4%A'), null);
    assert.equal(fileOf('/r', '/a/b.xhtml?x=1'), '/r/a/b.xhtml');
  });
  test('the files of the root, the pages, and 404', async () => {
    const s = await serve(fileURLToPath(new URL('pages', import.meta.url)), { pages: { '/p.html': '<p>x</p>' } });
    try {
      const css = await fetch(`${s.url}/ok.css`);
      assert.equal(css.status, 200);
      assert.equal(css.headers.get('content-type'), 'text/css; charset=utf-8');
      assert.equal(await (await fetch(`${s.url}/p.html`)).text(), '<p>x</p>');
      assert.equal((await fetch(`${s.url}/no-such-file`)).status, 404);
      assert.equal((await fetch(`${s.url}/`)).status, 404);
    } finally {
      await s.close();
    }
  });
});

describe('png.mjs', () => {
  const read = async (n) => decode(await readFile(`${ROOT}modules/golem-driver/test/fixtures/figures/images/${n}.png`));
  const alpha = (img) => [...Array(img.width * img.height).keys()].map((i) => img.rgba[i * 4 + 3]);
  test('tRNS of a palette of 2 bits', async () => {
    const img = await read('trns-palette');
    assert.equal(img.width, 4); assert.equal(img.height, 2);
    assert.ok(alpha(img).includes(0));
    assert.ok(alpha(img).includes(128));
  });
  test('tRNS of grey of 2 bits', async () => {
    const img = await read('trns-gray');
    assert.deepEqual(alpha(img), [255, 255, 0, 255]);
  });
  test('tRNS of RGB of 8 and 16 bits', async () => {
    assert.equal(alpha(await read('trns-rgb')).filter((a) => a === 0).length, 1);
    assert.equal(alpha(await read('trns-rgb16')).filter((a) => a === 0).length, 1);
  });
  test('RGBA of 8 bits', async () => {
    const img = await read('rgba');
    assert.equal(img.rgba.length, img.width * img.height * 4);
  });
});

describe('text-emphasis-style', () => {
  test('the computed values of the ten shapes', () => {
    assert.deepEqual(emphasis('sesame'), ['filled', 'sesame']);
    assert.deepEqual(emphasis('filled sesame'), ['filled', 'sesame']);
    assert.deepEqual(emphasis('open double-circle'), ['open', 'double-circle']);
    assert.deepEqual(emphasis('double-circle open'), ['open', 'double-circle']);
    assert.deepEqual(emphasis('none'), ['filled', 'none']);
    assert.deepEqual(emphasis(''), ['']);
    assert.equal(Object.keys(KENTEN).length, 10);
  });
});

describe('the ink of svg-text.mjs (docs/adr/0239 I1, I2)', () => {
  const box = (x, y, w, h, area = 100) => ({ x, y, width: w, height: h, area });
  test('ADR0239-I1: centres that differ by exactly 1 and sizes by exactly 2 CSS pixels pass', () => {
    assert.deepEqual(compareInk(box(10, 10, 20, 10), box(10, 10, 22, 10)).failures, []);
    assert.deepEqual(compareInk(box(10, 10, 20, 10), box(11, 10, 20, 10)).failures, []);
    assert.deepEqual(compareInk(box(10, 10, 20, 10), box(9, 9, 22, 12)).failures, []);
  });
  test('ADR0239-I1: sizes that differ by 3 CSS pixels fail', () => {
    assert.match(compareInk(box(10, 10, 20, 10), box(10, 10, 20, 13)).failures.join(), /sizes differ by 3/);
    assert.match(compareInk(box(10, 10, 20, 10), box(10, 10, 23, 10)).failures.join(), /sizes differ by 3/);
  });
  test('ADR0239-I1: centres that differ by 1.5 CSS pixels fail, though the sizes are the same', () => {
    const r = compareInk(box(10, 10, 20, 10), box(11.5, 10, 20, 10));
    assert.equal(r.failures.length, 1);
    assert.match(r.failures[0], /centres differ by 1.5/);
  });
  test('ADR0239-I1: grey text whose ink is 1 CSS pixel wider on each side passes', () => {
    assert.deepEqual(compareInk(box(10, 10, 200, 20), box(9, 10, 202, 20)).failures, []);
  });
  test('ADR0239-I1: ink beyond the limit fails', () => {
    assert.deepEqual(compareInk(box(10, 10, 20, 10, 100), box(10, 10, 20, 10, 90), 0.1).failures, []);
    assert.match(compareInk(box(10, 10, 20, 10, 100), box(10, 10, 20, 10, 89), 0.1).failures.join(), /ink differs/);
  });
  test('ADR0239-I1: no ink in one image fails', () => {
    assert.equal(compareInk(null, box(0, 0, 1, 1)).failures.length, 1);
  });

  // the measures of three text elements of one figure: a horizontal one
  // that passes and two vertical ones, one of which differs by 315 pixels
  const rows = () => [
    { name: 'stages', text: 'h', vertical: false, ...compareInk(box(0, 0, 100, 20), box(0, 0, 101, 20)) },
    { name: 'stages', text: 'v1', vertical: true, ...compareInk(box(0, 0, 20, 100), box(0, 0, 20, 415)) },
    { name: 'stages', text: 'v2', vertical: true, ...compareInk(box(0, 0, 20, 100), box(0, 0, 20, 103)) },
  ];
  test('ADR0239-I1: vertical text is judged as horizontal text is (Chromium)', () => {
    const r = judge(rows());
    assert.ok(r.failures.every((f) => /^stages: "v[12]"/.test(f)), r.failures.join('\n'));
    assert.match(r.failures.join('\n'), /"v1": the sizes differ by 315/);
    assert.match(r.failures.join('\n'), /"v2": the sizes differ by 3/);
    assert.equal(r.measured.stages.size, 315);
    assert.deepEqual(r.excluded, { count: 0, centre: 0, size: 0, ink: 0 });
  });
  test('ADR0239-I2: vertical text is measured but not judged (Safari), and the summary counts it', () => {
    const r = judge(rows(), { vertical: false });
    assert.deepEqual(r.failures, []);
    assert.equal(r.measured.stages.size, 1);
    assert.equal(r.excluded.count, 2);
    assert.equal(r.excluded.size, 315);
    assert.ok(r.excluded.centre >= 157);
  });
  test('ADR0239-I2: horizontal text is judged in Safari too', () => {
    const r = judge([{ name: 'x', text: 'h', vertical: false, ...compareInk(box(0, 0, 100, 20), box(-1.5, 0, 103, 20)) }], { vertical: false });
    assert.equal(r.failures.length, 1);
    assert.match(r.failures[0], /sizes differ by 3/);
  });
});

describe('the launch of Chromium (docs/adr/0239 I3)', () => {
  test('ADR0239-I3: the check svg launches Chromium without hinting, the check html as it is', () => {
    assert.deepEqual(chromiumArgs('svg'), ['--font-render-hinting=none']);
    assert.deepEqual(chromiumArgs('html'), []);
  });
});

describe('cdp.mjs', () => {
  test('the URL of the line DevTools listening on', async () => {
    const s = new PassThrough();
    const p = devtoolsUrl(s, 1000);
    s.write('[0101/000000.000:WARNING] something\nDevTools listening on ws://127.0.0.1:41234/devtools/browser/abc\n');
    assert.equal(await p, 'ws://127.0.0.1:41234/devtools/browser/abc');
  });
  test('a browser that ends without the line fails', async () => {
    const s = new PassThrough();
    const p = devtoolsUrl(s, 1000);
    s.end('No usable sandbox!\n');
    await assert.rejects(p, /ended before "DevTools listening on"/);
  });
});
