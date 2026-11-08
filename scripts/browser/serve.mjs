// Serves the files of a directory on 127.0.0.1, on a free port, to the
// browsers of the checks (docs/adr/0234 section 2). The browsers open its
// URLs, never file://: Chromium refuses fetch from file://, and 127.0.0.1
// is a secure context, where crypto.subtle computes SHA-256.
//
//   const server = await serve(root, { pages: { '/x/check.html': html } });
//   server.url  // http://127.0.0.1:PORT
//   await server.close();
//
// pages are served at their paths before the files of root. A path that
// leaves root, or names no file, is 404. Nothing is cached.
import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import { extname, join, normalize, sep } from 'node:path';

const TYPES = {
  '.css': 'text/css; charset=utf-8',
  '.html': 'text/html; charset=utf-8',
  '.jpg': 'image/jpeg',
  '.js': 'text/javascript; charset=utf-8',
  '.json': 'application/json',
  '.md': 'text/plain; charset=utf-8',
  '.mjs': 'text/javascript; charset=utf-8',
  '.otf': 'font/otf',
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.toml': 'text/plain; charset=utf-8',
  '.ttf': 'font/ttf',
  '.txt': 'text/plain; charset=utf-8',
  '.wasm': 'application/wasm',
  '.woff2': 'font/woff2',
  '.xhtml': 'application/xhtml+xml; charset=utf-8',
};

export function contentType(path) {
  return TYPES[extname(path).toLowerCase()] ?? 'application/octet-stream';
}

// The file under ROOT of the path of a URL, or null when it leaves ROOT.
export function fileOf(root, urlPath) {
  let path;
  try {
    path = decodeURIComponent(urlPath.split('?')[0]);
  } catch {
    return null;
  }
  const rel = normalize(path).replace(/^[/\\]+/, '');
  if (rel === '..' || rel.startsWith(`..${sep}`)) return null;
  return join(root, rel);
}

export async function serve(root, { pages = {} } = {}) {
  const server = createServer(async (req, res) => {
    const headers = { 'cache-control': 'no-store' };
    const path = req.url.split('?')[0];
    if (Object.hasOwn(pages, path)) {
      res.writeHead(200, { ...headers, 'content-type': contentType(path) });
      res.end(pages[path]);
      return;
    }
    const file = fileOf(root, req.url);
    try {
      if (file === null || !(await stat(file)).isFile()) throw new Error('not a file');
      const body = await readFile(file);
      res.writeHead(200, { ...headers, 'content-type': contentType(file) });
      res.end(body);
    } catch {
      res.writeHead(404, headers);
      res.end();
    }
  });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  return {
    url: `http://127.0.0.1:${server.address().port}`,
    close: () => new Promise((resolve) => {
      server.closeAllConnections();
      server.close(resolve);
    }),
  };
}
