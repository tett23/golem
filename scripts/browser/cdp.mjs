// A small client of the Chrome DevTools Protocol for chrome-headless-shell
// (docs/adr/0234 section 2), with the built-ins of Node only.
//
//   const page = await launch(binary, { scale: 1 });
//
// starts `chrome-headless-shell --remote-debugging-port=0
// --user-data-dir=<a temporary directory>`, reads the URL of the browser
// from the line `DevTools listening on ws://...` of its standard error,
// opens one page and returns the functions that every check receives
// (the same set as webdriver.mjs):
//
//   open(url)             navigates and waits for the load event
//   evaluate(expr)        the value of a JavaScript expression in the page
//   evaluateAsync(expr)   the value of the promise of an expression
//   setWindowSize(w, h)   the size of the viewport in CSS pixels
//   screenshot()          a PNG (Buffer) of the viewport
//   close()               ends the browser
//   failures()            the console errors (console.error and uncaught
//                         exceptions) and the failed loads
//                         (Network.loadingFailed) since the last open
//
// scale is the devicePixelRatio of the page. The browser runs without its
// sandbox: Ubuntu 24.04 does not let it make the user namespaces it needs
// (kernel.apparmor_restrict_unprivileged_userns), and the pages are the
// files of the checks, served on 127.0.0.1.
import { spawn } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

// The URL of the browser from its standard error, within TIMEOUT ms.
export function devtoolsUrl(stream, timeout = 30000) {
  return new Promise((resolve, reject) => {
    let seen = '';
    const timer = setTimeout(() => reject(new Error(`cdp: no "DevTools listening on" line in ${timeout} ms:\n${seen}`)), timeout);
    stream.setEncoding('utf8');
    stream.on('data', (chunk) => {
      seen += chunk;
      const m = /DevTools listening on (ws:\/\/\S+)/.exec(seen);
      if (m) {
        clearTimeout(timer);
        resolve(m[1]);
      }
    });
    stream.on('end', () => {
      clearTimeout(timer);
      reject(new Error(`cdp: the browser ended before "DevTools listening on":\n${seen}`));
    });
  });
}

// A connection: send(method, params, sessionId) and on(method, f).
export function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    let next = 0;
    const pending = new Map();
    const listeners = new Map();
    ws.addEventListener('error', () => reject(new Error(`cdp: cannot connect to ${url}`)), { once: true });
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id !== undefined) {
        const p = pending.get(msg.id);
        pending.delete(msg.id);
        if (!p) return;
        if (msg.error) p.reject(new Error(`cdp: ${p.method}: ${msg.error.message}`));
        else p.resolve(msg.result);
      } else {
        for (const f of listeners.get(msg.method) ?? []) f(msg.params, msg.sessionId);
      }
    });
    ws.addEventListener('close', () => {
      for (const p of pending.values()) p.reject(new Error(`cdp: the connection closed during ${p.method}`));
      pending.clear();
    });
    ws.addEventListener('open', () => resolve({
      send(method, params = {}, sessionId = undefined) {
        const id = ++next;
        return new Promise((res, rej) => {
          pending.set(id, { resolve: res, reject: rej, method });
          ws.send(JSON.stringify(sessionId === undefined ? { id, method, params } : { id, method, params, sessionId }));
        });
      },
      on(method, f) {
        listeners.set(method, [...(listeners.get(method) ?? []), f]);
      },
      close() {
        ws.close();
      },
    }), { once: true });
  });
}

// The functions of a page of an open connection.
export async function page(conn, { scale = 1, close = async () => {} } = {}) {
  const { targetId } = await conn.send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await conn.send('Target.attachToTarget', { targetId, flatten: true });
  const send = (method, params) => conn.send(method, params, sessionId);
  let failures = [];
  let loaded = null;
  const urls = new Map();
  conn.on('Runtime.consoleAPICalled', (p, s) => {
    if (s !== sessionId || p.type !== 'error') return;
    failures.push(`console.error: ${p.args.map((a) => a.value ?? a.description ?? a.type).join(' ')}`);
  });
  conn.on('Runtime.exceptionThrown', (p, s) => {
    if (s !== sessionId) return;
    failures.push(`uncaught: ${p.exceptionDetails.exception?.description ?? p.exceptionDetails.text}`);
  });
  conn.on('Network.loadingFailed', (p, s) => {
    if (s !== sessionId || p.canceled) return;
    failures.push(`loading failed: ${p.type} ${p.errorText} (${urls.get(p.requestId) ?? p.requestId})`);
  });
  conn.on('Network.requestWillBeSent', (p, s) => {
    if (s === sessionId) urls.set(p.requestId, p.request.url);
  });
  conn.on('Page.loadEventFired', (_p, s) => {
    if (s === sessionId && loaded) loaded();
  });
  await send('Page.enable');
  await send('Runtime.enable');
  await send('Network.enable');
  let size = { width: 1024, height: 768 };
  const metrics = () => send('Emulation.setDeviceMetricsOverride', { ...size, deviceScaleFactor: scale, mobile: false });
  await metrics();

  const value = (r) => {
    if (r.exceptionDetails) throw new Error(`cdp: the page threw: ${r.exceptionDetails.exception?.description ?? r.exceptionDetails.text}`);
    return r.result.value;
  };
  return {
    browser: 'chromium',
    async open(url) {
      failures = [];
      const done = new Promise((resolve) => { loaded = resolve; });
      const r = await send('Page.navigate', { url });
      if (r.errorText) throw new Error(`cdp: cannot open ${url}: ${r.errorText}`);
      await done;
      loaded = null;
    },
    async evaluate(expression) {
      return value(await send('Runtime.evaluate', { expression, returnByValue: true }));
    },
    async evaluateAsync(expression) {
      return value(await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true }));
    },
    async setWindowSize(width, height) {
      size = { width, height };
      await metrics();
    },
    async screenshot() {
      const { data } = await send('Page.captureScreenshot', { format: 'png' });
      return Buffer.from(data, 'base64');
    },
    failures() {
      return [...failures];
    },
    close,
  };
}

export async function launch(binary, { scale = 1, args = [] } = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'golem-cdp-'));
  const child = spawn(binary, [
    '--remote-debugging-port=0',
    `--user-data-dir=${dir}`,
    '--no-sandbox',
    '--no-first-run',
    '--hide-scrollbars',
    '--force-color-profile=srgb',
    ...args,
    'about:blank',
  ], { stdio: ['ignore', 'ignore', 'pipe'] });
  const exited = new Promise((resolve) => child.on('exit', resolve));
  let conn;
  try {
    conn = await connect(await devtoolsUrl(child.stderr));
  } catch (e) {
    child.kill('SIGKILL');
    await exited;
    await rm(dir, { recursive: true, force: true });
    throw e;
  }
  child.stderr.resume();
  const close = async () => {
    try {
      await Promise.race([conn.send('Browser.close'), new Promise((r) => setTimeout(r, 5000))]);
    } catch {
      // the browser may close the connection before it answers
    }
    conn.close();
    if (child.exitCode === null) child.kill('SIGKILL');
    await exited;
    await rm(dir, { recursive: true, force: true });
  };
  try {
    return await page(conn, { scale, close });
  } catch (e) {
    await close();
    throw e;
  }
}
