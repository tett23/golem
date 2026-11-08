// A small client of W3C WebDriver for safaridriver (docs/adr/0234 section
// 2), with the built-ins of Node only.
//
//   const page = await launch();          // starts safaridriver --port N
//   const page = await connect(baseUrl);  // a WebDriver server already up
//
// Both make one session (Safari has one at a time, so the checks run one
// after another in it) and return the functions that every check receives,
// the same set as cdp.mjs:
//
//   open(url)             Navigate To
//   evaluate(expr)        Execute Script: the value of an expression
//   evaluateAsync(expr)   Execute Async Script: the value of its promise
//   setWindowSize(w, h)   Set Window Rect (of the window, not the viewport)
//   screenshot()          Take Screenshot: a PNG (Buffer) of the viewport
//   close()               Delete Session (and ends safaridriver)
//   failures()            null: WebDriver has no command for the console
//                         errors and the failed loads
//
// and browserVersion, that of the answer to New Session. An error of the
// server (an HTTP status that is not 2xx with value.error) throws an Error
// with its error and message.
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';

// An Error of COMMAND with the error code of WebDriver in .error.
export function webDriverError(command, error, message) {
  return Object.assign(new Error(`webdriver: ${command}: ${error}: ${message}`), { error });
}

// One command: METHOD PATH with BODY, its value.
export async function command(base, method, path, body = undefined) {
  const res = await fetch(`${base}${path}`, {
    method,
    headers: body === undefined ? {} : { 'content-type': 'application/json; charset=utf-8' },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw webDriverError(`${method} ${path}`, 'invalid response', `HTTP ${res.status}: ${text.slice(0, 200)}`);
  }
  if (!res.ok || (json.value && typeof json.value === 'object' && typeof json.value.error === 'string')) {
    const v = json.value ?? {};
    throw webDriverError(`${method} ${path}`, v.error ?? `HTTP ${res.status}`, v.message ?? text.slice(0, 200));
  }
  return json.value;
}

// The script of Execute Async Script for an expression whose value is a
// promise: its value, or an object that says what it threw.
export function asyncScript(expression) {
  return `const done = arguments[arguments.length - 1];
Promise.resolve().then(() => (${expression})).then(
  (v) => done({ ok: true, v }),
  (e) => done({ ok: false, e: String(e) + (e && e.stack ? '\\n' + e.stack : '') }));`;
}

// The script timeout of WebDriver is 30 s by default; golem.wasm builds a
// book in a page for longer (docs/adr/0234 section 5).
export const TIMEOUTS = { script: 600000, pageLoad: 300000 };

export async function connect(base, { quit = async () => {} } = {}) {
  let created;
  try {
    created = await command(base, 'POST', '/session', { capabilities: { alwaysMatch: { browserName: 'safari', timeouts: TIMEOUTS } } });
  } catch (e) {
    await quit();
    throw e;
  }
  const s = `/session/${created.sessionId}`;
  const run = (method, path, body) => command(base, method, `${s}${path}`, body);
  return {
    browser: 'safari',
    browserVersion: created.capabilities?.browserVersion ?? null,
    async open(url) {
      await run('POST', '/url', { url });
    },
    async evaluate(expression) {
      return run('POST', '/execute/sync', { script: `return (${expression});`, args: [] });
    },
    async evaluateAsync(expression) {
      const r = await run('POST', '/execute/async', { script: asyncScript(expression), args: [] });
      if (!r || r.ok !== true) throw webDriverError('POST /execute/async', 'the page threw', r?.e ?? String(r));
      return r.v;
    },
    async setWindowSize(width, height) {
      await run('POST', '/window/rect', { width, height });
    },
    async screenshot() {
      return Buffer.from(await run('GET', '/screenshot'), 'base64');
    },
    failures() {
      return null;
    },
    async close() {
      try {
        await run('DELETE', '');
      } finally {
        await quit();
      }
    },
  };
}

export function freePort() {
  return new Promise((resolve, reject) => {
    const srv = createServer();
    srv.on('error', reject);
    srv.listen(0, '127.0.0.1', () => {
      const { port } = srv.address();
      srv.close(() => resolve(port));
    });
  });
}

// Waits until BASE answers GET /status (with any answer of WebDriver),
// within TIMEOUT ms.
export async function ready(base, timeout = 30000) {
  const end = Date.now() + timeout;
  for (;;) {
    try {
      await command(base, 'GET', '/status');
      return;
    } catch (e) {
      if (e.error !== undefined) return;
    }
    if (Date.now() > end) throw new Error(`webdriver: ${base}/status did not answer ready in ${timeout} ms`);
    await new Promise((r) => setTimeout(r, 200));
  }
}

export async function launch(binary = 'safaridriver') {
  const port = await freePort();
  const child = spawn(binary, ['--port', String(port)], { stdio: 'ignore' });
  const exited = new Promise((resolve) => child.on('exit', resolve));
  const quit = async () => {
    if (child.exitCode === null) child.kill('SIGTERM');
    await exited;
  };
  const base = `http://127.0.0.1:${port}`;
  try {
    await ready(base);
  } catch (e) {
    await quit();
    throw e;
  }
  return connect(base, { quit });
}
