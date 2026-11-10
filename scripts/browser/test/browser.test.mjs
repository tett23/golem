// The checks of html-checks.mjs and svg-text.mjs on the small pages of
// test/pages, in the browser of BROWSER (chromium or safari; the tests are
// skipped without it). The same test functions run in both browsers (I6):
// the chromium job of .github/workflows/browser.yml runs them with
// BROWSER=chromium, the safari job with BROWSER=safari (docs/adr/0234).
//
//   BROWSER=chromium node --test scripts/browser/test/
import { after, before, describe, test } from 'node:test';
import assert from 'node:assert/strict';
import { cp, mkdir, mkdtemp, rm, symlink } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { openBrowser } from '../browsers.mjs';
import * as html from '../html-checks.mjs';
import { serve } from '../serve.mjs';
import { HARNESS, svgText } from '../svg-text.mjs';

const BROWSER = process.env.BROWSER;
const ROOT = fileURLToPath(new URL('../../../', import.meta.url));
const skip = BROWSER ? false : 'BROWSER is not set';

// test/pages with the files the repository has elsewhere: a PNG with tRNS
// and the fonts
async function pagesRoot() {
  const dir = await mkdtemp(join(tmpdir(), 'golem-browser-test-'));
  await cp(fileURLToPath(new URL('pages', import.meta.url)), dir, { recursive: true });
  await cp(join(ROOT, 'modules/golem-driver/test/fixtures/figures/images/trns-rgb.png'), join(dir, 'trns-rgb.png'));
  await cp(join(ROOT, 'modules/golem-driver/test/fixtures/kanikosen/fonts/NotoSerifJP-Regular.otf'), join(dir, 'ja.otf'));
  await mkdir(join(dir, 'svg/fonts'), { recursive: true });
  await cp(join(ROOT, 'modules/golem-font/test/fonts/SourceSansPro-Regular.otf'), join(dir, 'svg/fonts/latin.otf'));
  return dir;
}

// The tests of one page of the browser at a devicePixelRatio (Safari has
// the one of its screen).
function suite(scale) {
  describe(`${BROWSER} at devicePixelRatio ${scale}`, { skip }, () => {
    let dir; let server; let svg; let page;
    const u = (p) => `${server.url}/${p}`;
    before(async () => {
      dir = await pagesRoot();
      // a link to a file outside the root, which the server does not
      // serve (docs/adr ADR 0288)
      await symlink(fileURLToPath(import.meta.url), join(dir, 'outside.mjs'));
      server = await serve(dir);
      svg = await serve(join(dir, 'svg'), { pages: { '/images/src/__svg-text.html': HARNESS } });
      page = await openBrowser(BROWSER, { scale });
      await page.setWindowSize(1024, 768);
    });
    after(async () => {
      await page?.close();
      await server?.close();
      await svg?.close();
      if (dir) await rm(dir, { recursive: true, force: true });
    });

    test('S1: the server answers 404 for a link under its root to a file outside it (docs/adr ADR 0288)', async () => {
      assert.equal((await fetch(u('outside.mjs'))).status, 404);
    });
    test('I1: line numbers and diff marks of user-select: none are not selected', async () => {
      assert.deepEqual(await html.selection(page, u('select-ok.html')), []);
    });
    test('I1: an empty code block passes', async () => {
      assert.deepEqual(await html.selection(page, u('select-empty.html')), []);
    });
    test('I1: line numbers that are not user-select: none fail', async () => {
      const f = await html.selection(page, u('select-selectable.html'));
      assert.equal(f.length, 1);
      assert.match(f[0], /the selection is "1main = pure \(\)"/);
    });

    test('I2: a page without images passes', async () => {
      assert.deepEqual(await html.pages(page, [u('page-ok.html')]), []);
    });
    test('I2: an image that does not exist fails', async () => {
      const f = await html.pages(page, [u('page-missing-image.html')]);
      assert.ok(f.some((x) => /the image no-such-image\.png is not loaded/.test(x)), f.join('\n'));
    });
    test('I2: a font that cannot be loaded fails', async () => {
      const f = await html.pages(page, [u('page-missing-font.html')]);
      assert.ok(f.some((x) => /the font "?missing"? is error/.test(x)), f.join('\n'));
    });
    test('I2, I6: console.error after the load fails in Chromium and passes in Safari', async () => {
      const f = await html.pages(page, [u('page-console-error.html')]);
      if (page.failures() === null) assert.deepEqual(f, []);
      else assert.ok(f.some((x) => /console\.error: an error after the load/.test(x)), f.join('\n'));
    });

    test('I3: the transparent pixels of tRNS show the ground', async () => {
      assert.deepEqual(await html.trns(page, u('trns-ok.html')), []);
    });
    test('I3: colour painted over the transparent pixels fails', async () => {
      const f = await html.trns(page, u('trns-painted.html'));
      assert.ok(f.length > 0 && f.every((x) => /the transparent pixel/.test(x)), f.join('\n'));
    });

    test('the dashes of vertical-rl are taller than wide', async () => {
      assert.deepEqual(await html.verticalDash(page, u('dash-vertical.html'), 'p.dash'), []);
    });
    test('dashes laid on their side fail', async () => {
      const f = await html.verticalDash(page, u('dash-horizontal.html'), 'p.dash');
      assert.equal(f.length, 1);
      assert.match(f[0], /not taller than wide/);
    });

    test('I4: text moved by 1 CSS pixel passes', async () => {
      const r = await svgText(page, svg.url, ['shift1']);
      assert.deepEqual(r.failures, []);
    });
    test('I4: text moved by 2 CSS pixels fails', async () => {
      const r = await svgText(page, svg.url, ['shift2']);
      assert.ok(r.failures.some((x) => /the centres differ by 2 CSS px/.test(x)), r.failures.join('\n'));
    });
  });
}

suite(1);
// I4, I6: the same results at devicePixelRatio 2, which only Chromium lets
// the checks choose
if (BROWSER === 'chromium') suite(2);
