// The checks of .github/workflows/browser.yml in one browser (docs/adr/0234):
//
//   node run.mjs BROWSER html INPUTS
//       the checks of html-checks.mjs: INPUTS/horizontal, INPUTS/vertical
//       and INPUTS/figures are the HTML of build-fixtures.sh, and
//       INPUTS/manual/html and INPUTS/manual-dev/html those of the manuals
//   node run.mjs BROWSER svg IMAGES FONTS
//       the check of svg-text.mjs: IMAGES is manual-dev/images (the
//       outlined figures and src/), FONTS the fonts of the manual
//
// BROWSER is chromium or safari (browsers.mjs). Each check prints ok or
// FAIL with its failures; the exit code is 1 when one failed. With
// BROWSER_VERSION_FILE, the browserVersion of the WebDriver session of
// Safari is written there as soon as the session is made.
import { cp, mkdtemp, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, relative } from 'node:path';
import process from 'node:process';
import { openBrowser } from './browsers.mjs';
import * as html from './html-checks.mjs';
import { serve } from './serve.mjs';
import { HARNESS, svgText } from './svg-text.mjs';

// The family that golem gives to the latin font of [fonts.code] in the
// @font-face of style.css (scripts/browser/fixtures/horizontal/style.toml).
const CODE_FAMILY = 'golem-code-latin';

async function xhtmlUnder(dir) {
  const out = [];
  for (const e of await readdir(dir, { withFileTypes: true, recursive: true })) {
    if (e.isFile() && e.name.endsWith('.xhtml')) out.push(join(e.parentPath, e.name));
  }
  return out.sort();
}

async function report(name, failures) {
  console.log(`${failures.length === 0 ? 'ok' : 'FAIL'}: ${name}`);
  for (const f of failures) console.log(`  ${f}`);
  return failures.length === 0;
}

async function htmlChecks(page, inputs) {
  const server = await serve(inputs);
  const u = (p) => `${server.url}/${p}`;
  try {
    const results = [];
    results.push(await report('selection and copy (I1)', await html.selection(page, u('horizontal/book.xhtml'))));
    results.push(await report('pre and code', await html.preCode(page, u('horizontal/book.xhtml'), CODE_FAMILY)));
    results.push(await report('the vertical dash', await html.verticalDash(page, u('vertical/book.xhtml'), 'p.ps-dash')));
    results.push(await report('kenten', await html.kenten(page, u('horizontal/book.xhtml'))));
    results.push(await report('paragraph rules, horizontal', await html.paragraphRules(page, u('horizontal/book.xhtml'))));
    results.push(await report('paragraph rules, vertical', await html.paragraphRules(page, u('vertical/book.xhtml'))));
    results.push(await report('tRNS (I3)', await html.trns(page, u('figures/figures.xhtml'))));
    const manuals = [];
    for (const m of ['manual/html', 'manual-dev/html']) for (const f of await xhtmlUnder(join(inputs, m))) manuals.push(u(relative(inputs, f).split('\\').join('/')));
    if (manuals.length === 0) results.push(await report('the manuals (I2)', ['no page of the manuals']));
    else results.push(await report(`the ${manuals.length} pages of the manuals (I2)`, await html.pages(page, manuals)));
    return results.every(Boolean);
  } finally {
    await server.close();
  }
}

async function svgCheck(page, images, fonts) {
  const root = await mkdtemp(join(tmpdir(), 'golem-svg-'));
  try {
    await cp(images, join(root, 'images'), { recursive: true });
    await cp(fonts, join(root, 'fonts'), { recursive: true });
    const names = (await readdir(join(root, 'images', 'src'))).filter((f) => f.endsWith('.svg')).map((f) => f.slice(0, -4)).sort();
    const server = await serve(root, { pages: { '/images/src/__svg-text.html': HARNESS } });
    try {
      const { failures, measured } = await svgText(page, server.url, names);
      for (const [n, m] of Object.entries(measured)) console.log(`  ${n}: centre ${m.centre.toFixed(2)} px, size ${m.size.toFixed(2)} px, ink ${(m.ink * 100).toFixed(2)}%`);
      return report(`the text of the ${names.length} outlined figures (I4)`, names.length === 0 ? ['no figure'] : failures);
    } finally {
      await server.close();
    }
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

const [browser, check, ...args] = process.argv.slice(2);
const usage = () => {
  process.stderr.write('usage: node run.mjs chromium|safari html INPUTS | node run.mjs chromium|safari svg IMAGES FONTS\n');
  process.exit(2);
};
if (!['chromium', 'safari'].includes(browser)) usage();
if (!((check === 'html' && args.length === 1) || (check === 'svg' && args.length === 2))) usage();
const page = await openBrowser(browser);
let passed = false;
try {
  if (page.browserVersion && process.env.BROWSER_VERSION_FILE) await writeFile(process.env.BROWSER_VERSION_FILE, `${page.browserVersion}\n`);
  console.log(`${browser}${page.browserVersion ? ` ${page.browserVersion}` : ''}`);
  await page.setWindowSize(1024, 768);
  passed = check === 'html' ? await htmlChecks(page, ...args) : await svgCheck(page, ...args);
} finally {
  await page.close();
}
process.exitCode = passed ? 0 : 1;
