// The page of a browser by its name (docs/adr/0234 section 2): chromium is
// the chrome-headless-shell of scripts/browser/fetch-chromium.sh (CHROMIUM
// chooses another), driven by cdp.mjs; safari is the Safari of the machine,
// driven by safaridriver (SAFARIDRIVER chooses another) through
// webdriver.mjs. The checks receive the page and do not ask which it is.
import { fileURLToPath } from 'node:url';
import { launch as cdp } from './cdp.mjs';
import { launch as webdriver } from './webdriver.mjs';

export const BROWSERS = ['chromium', 'safari'];

// The arguments with which a check launches Chromium (docs/adr/0239 I3):
// svg, the check of the outlined figures, without the hinting that puts
// the advances of glyphs on pixels, which the paths of the outlines do not
// get; html as the Chrome of the users is.
export function chromiumArgs(check) {
  return check === 'svg' ? ['--font-render-hinting=none'] : [];
}

export function chromiumPath() {
  return process.env.CHROMIUM || fileURLToPath(new URL('../../third_party/chromium/chrome-headless-shell-linux64/chrome-headless-shell', import.meta.url));
}

export async function openBrowser(name, { scale = 1, args = [] } = {}) {
  if (name === 'chromium') return cdp(chromiumPath(), { scale, args });
  if (name === 'safari') return webdriver(process.env.SAFARIDRIVER || 'safaridriver');
  throw new Error(`unknown browser: ${name} (${BROWSERS.join(' or ')})`);
}
