// The checks of the HTML of golem in a browser (docs/adr/0234 section 3).
// Each takes the functions of a page (cdp.mjs or webdriver.mjs) and the
// URL of a page served by serve.mjs, and returns the list of its failures:
// an empty list passes. They read the same values in both browsers and
// apply the same criteria; the one difference is that the console errors
// and the failed loads, which WebDriver cannot give (failures() is null),
// are checked in Chromium only (I6).
import { capture, colorAt, inkBox } from './pixels.mjs';
import { decode } from './png.mjs';

const settle = `(async () => {
  await Promise.allSettled([...document.fonts].map((f) => f.load()));
  await document.fonts.ready;
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  return true;
})()`;

async function load(page, url) {
  await page.open(url);
  await page.evaluateAsync(settle);
}

// The rectangle of the document of a DOMRect, in the page.
const docRect = `(r) => ({ x: r.left + scrollX, y: r.top + scrollY, width: r.width, height: r.height })`;

// Selection and copy (I1): the string of a Range over the whole of each pre
// is its code, without the text of the line numbers (.ln) and the diff
// marks (.dm).
export async function selection(page, url) {
  await load(page, url);
  const blocks = await page.evaluate(`(() => [...document.querySelectorAll('pre')].map((pre) => {
    const range = document.createRange();
    range.selectNodeContents(pre);
    const sel = getSelection();
    sel.removeAllRanges();
    sel.addRange(range);
    const got = sel.toString();
    sel.removeAllRanges();
    const copy = pre.cloneNode(true);
    for (const e of copy.querySelectorAll('.ln, .dm')) e.remove();
    return { got, want: copy.textContent };
  }))()`);
  if (blocks.length === 0) return [`${url}: no pre`];
  return blocks.flatMap(({ got, want }, i) => (got === want ? [] : [`${url}: pre ${i + 1}: the selection is ${JSON.stringify(got)}, not the code ${JSON.stringify(want)}`]));
}

// pre and code: the white-space of each pre is pre or pre-wrap, the first of
// its font-family is FAMILY (the code font of style.toml), and a face of
// FAMILY is loaded in document.fonts.
export async function preCode(page, url, family) {
  await load(page, url);
  const r = await page.evaluate(`(() => ({
    pres: [...document.querySelectorAll('pre')].map((pre) => {
      const cs = getComputedStyle(pre);
      return { ws: cs.whiteSpace, family: cs.fontFamily.split(',')[0].trim().replace(/^["']|["']$/g, '') };
    }),
    faces: [...document.fonts].map((f) => ({ family: f.family.replace(/^["']|["']$/g, ''), status: f.status })),
  }))()`);
  const out = [];
  if (r.pres.length === 0) out.push(`${url}: no pre`);
  r.pres.forEach((p, i) => {
    if (p.ws !== 'pre' && p.ws !== 'pre-wrap') out.push(`${url}: pre ${i + 1}: white-space is ${p.ws}`);
    if (p.family !== family) out.push(`${url}: pre ${i + 1}: the first font-family is ${p.family}, not ${family}`);
  });
  if (!r.faces.some((f) => f.family === family && f.status === 'loaded')) out.push(`${url}: no loaded face of ${family} in document.fonts (${JSON.stringify(r.faces)})`);
  return out;
}

// The vertical dash: the ink of each element of SELECTOR, which holds dashes
// only, is taller than it is wide.
export async function verticalDash(page, url, selector) {
  await load(page, url);
  const rects = await page.evaluate(`[...document.querySelectorAll(${JSON.stringify(selector)})].map((e) => (${docRect})(e.getBoundingClientRect()))`);
  if (rects.length === 0) return [`${url}: no ${selector}`];
  const out = [];
  for (const [i, r] of rects.entries()) {
    const box = inkBox(await capture(page, r), r);
    if (!box) out.push(`${url}: ${selector} ${i + 1}: no ink`);
    else if (!(box.height > box.width)) out.push(`${url}: ${selector} ${i + 1}: the ink is ${box.width} wide and ${box.height} high, not taller than wide`);
  }
  return out;
}

// The text-emphasis-style of each of the ten shapes of golem-driver ADR
// 0019, as [fill, shape].
export const KENTEN = {
  sesame: ['filled', 'sesame'],
  'open-sesame': ['open', 'sesame'],
  dot: ['filled', 'dot'],
  'open-dot': ['open', 'dot'],
  circle: ['filled', 'circle'],
  'open-circle': ['open', 'circle'],
  'double-circle': ['filled', 'double-circle'],
  'open-double-circle': ['open', 'double-circle'],
  triangle: ['filled', 'triangle'],
  'open-triangle': ['open', 'triangle'],
};

// A computed text-emphasis-style as [fill, shape]: filled is the default
// of the fill; anything else is [value].
export function emphasis(value) {
  const words = value.trim().split(/\s+/).filter((w) => w !== '');
  const fill = words.includes('open') ? 'open' : 'filled';
  const shapes = words.filter((w) => w !== 'open' && w !== 'filled');
  return shapes.length === 1 ? [fill, shapes[0]] : [value];
}

// Kenten: every one of the ten shapes is on the page, and the computed
// text-emphasis-style of each element of class kenten-<shape> is that of the
// shape. Only the property that golem writes is read, never a prefixed one.
export async function kenten(page, url) {
  await load(page, url);
  const els = await page.evaluate(`[...document.querySelectorAll('.kenten')].map((e) => ({
    cls: [...e.classList].filter((c) => c.startsWith('kenten-')),
    style: getComputedStyle(e).getPropertyValue('text-emphasis-style'),
  }))`);
  const out = [];
  const seen = new Set();
  for (const e of els) {
    const shape = e.cls.map((c) => c.slice(7)).find((s) => Object.hasOwn(KENTEN, s));
    if (!shape) { out.push(`${url}: a kenten of no known shape (${e.cls.join(' ')})`); continue; }
    seen.add(shape);
    const got = emphasis(e.style);
    if (got.join(' ') !== KENTEN[shape].join(' ')) out.push(`${url}: kenten-${shape}: text-emphasis-style is "${e.style}", not "${KENTEN[shape].join(' ')}"`);
  }
  for (const s of Object.keys(KENTEN)) if (!seen.has(s)) out.push(`${url}: no kenten-${s}`);
  return out;
}

// Paragraph rules: each p whose ::before or ::after has a border on the
// block start has, between the edge of the paragraph and its text, ink that
// is a line along the line direction: above and below the text in a
// horizontal book, right and left of it in vertical-rl.
export async function paragraphRules(page, url) {
  await load(page, url);
  const ps = await page.evaluate(`[...document.querySelectorAll('p')].map((p) => {
    const w = (pseudo) => parseFloat(getComputedStyle(p, pseudo).getPropertyValue('border-block-start-width')) || 0;
    const range = document.createRange();
    range.selectNodeContents(p);
    const rs = [...range.getClientRects()].filter((r) => r.width > 0 && r.height > 0);
    const text = rs.length === 0 ? null : {
      x: Math.min(...rs.map((r) => r.left)) + scrollX, y: Math.min(...rs.map((r) => r.top)) + scrollY,
      right: Math.max(...rs.map((r) => r.right)) + scrollX, bottom: Math.max(...rs.map((r) => r.bottom)) + scrollY,
    };
    return { before: w('::before'), after: w('::after'), mode: getComputedStyle(p).writingMode, box: (${docRect})(p.getBoundingClientRect()), text };
  }).filter((p) => p.before > 0 || p.after > 0)`);
  if (ps.length === 0) return [`${url}: no paragraph with rules`];
  const out = [];
  for (const [i, p] of ps.entries()) {
    const name = `${url}: the paragraph with rules ${i + 1}`;
    if (!p.text) { out.push(`${name}: no text`); continue; }
    const img = await capture(page, p.box);
    const b = p.box;
    const vertical = p.mode.startsWith('vertical');
    // the bands between the edge of the paragraph and its text, before and after
    const bands = vertical
      ? { before: { x: p.text.right, y: b.y, width: b.x + b.width - p.text.right, height: b.height }, after: { x: b.x, y: b.y, width: p.text.x - b.x, height: b.height } }
      : { before: { x: b.x, y: b.y, width: b.width, height: p.text.y - b.y }, after: { x: b.x, y: p.text.bottom, width: b.width, height: b.y + b.height - p.text.bottom } };
    for (const side of ['before', 'after']) {
      if (p[side] === 0) continue;
      const band = bands[side];
      const ink = band.width > 0 && band.height > 0 ? inkBox(img, band) : null;
      if (!ink) out.push(`${name}: no rule ${side} the text (${vertical ? 'vertical' : 'horizontal'})`);
      else if (vertical ? !(ink.height > ink.width) : !(ink.width > ink.height)) out.push(`${name}: the ink ${side} the text is not a line along the lines (${ink.width} x ${ink.height})`);
    }
  }
  return out;
}

// The colour of the ground behind an element: the first background that is
// not transparent, from its parent up, or white.
const ground = `(e) => {
  for (let n = e.parentElement; n; n = n.parentElement) {
    const m = /rgba?\\((\\d+), (\\d+), (\\d+)(?:, ([\\d.]+))?\\)/.exec(getComputedStyle(n).backgroundColor);
    if (m && (m[4] === undefined || Number(m[4]) === 1)) return [Number(m[1]), Number(m[2]), Number(m[3])];
  }
  return [255, 255, 255];
}`;

// tRNS (I3): in each img of a PNG with tRNS, the pixels that tRNS makes
// transparent show the ground of the page. The image is enlarged eight
// times with image-rendering: pixelated, so that the centre of each of its
// pixels is far from the others; a colour within TOLERANCE of the ground
// passes.
export async function trns(page, url, tolerance = 2) {
  await load(page, url);
  const imgs = await page.evaluate(`(() => {
    const out = [];
    for (const img of document.querySelectorAll('img')) {
      if (!/\\.png$/i.test(new URL(img.src).pathname)) continue;
      img.style.width = (img.naturalWidth * 8) + 'px';
      img.style.height = (img.naturalHeight * 8) + 'px';
      img.style.imageRendering = 'pixelated';
      out.push({ img, src: img.src });
    }
    return out.map(({ img, src }) => ({ src, ground: (${ground})(img) }));
  })()`);
  await page.evaluateAsync(settle);
  const rects = await page.evaluate(`[...document.querySelectorAll('img')].filter((i) => /\\.png$/i.test(new URL(i.src).pathname)).map((i) => (${docRect})(i.getBoundingClientRect()))`);
  const out = [];
  let checked = 0;
  for (const [k, { src, ground: bg }] of imgs.entries()) {
    const png = decode(Buffer.from(await (await fetch(src)).arrayBuffer()));
    const clear = [];
    for (let i = 0; i < png.width * png.height; i++) if (png.rgba[i * 4 + 3] === 0) clear.push(i);
    if (clear.length === 0) continue;
    checked++;
    const r = rects[k];
    const img = await capture(page, r);
    for (const i of clear) {
      const px = i % png.width; const py = Math.floor(i / png.width);
      const c = colorAt(img, r.x + ((px + 0.5) * r.width) / png.width, r.y + ((py + 0.5) * r.height) / png.height);
      if (c.some((v, j) => Math.abs(v - bg[j]) > tolerance)) out.push(`${url}: ${src}: the transparent pixel (${px}, ${py}) is rgb(${c.join(', ')}), not the ground rgb(${bg.join(', ')})`);
    }
  }
  if (checked === 0) out.push(`${url}: no PNG with transparent pixels`);
  return out;
}

// The values of a page that say a load failed (I2): images not complete or
// of no width, style sheets without sheet, faces not loaded, and links to
// # whose id is not on the page.
const pageValues = `(async () => {
  await Promise.allSettled([...document.fonts].map((f) => f.load()));
  await document.fonts.ready;
  const out = [];
  for (const img of document.images) if (!img.complete || img.naturalWidth === 0) out.push('the image ' + img.getAttribute('src') + ' is not loaded');
  for (const l of document.querySelectorAll('link[rel~="stylesheet"]')) if (!l.sheet) out.push('the style sheet ' + l.getAttribute('href') + ' is not loaded');
  for (const f of document.fonts) if (f.status !== 'loaded') out.push('the font ' + f.family + ' is ' + f.status);
  for (const a of document.querySelectorAll('a[href^="#"]')) {
    const id = decodeURIComponent(a.getAttribute('href').slice(1));
    if (id !== '' && !document.getElementById(id)) out.push('the link to #' + id + ' has no target');
  }
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  return out;
})()`;

// The pages of the manuals (I2): every value above, and in Chromium the
// console errors and Network.loadingFailed too.
export async function pages(page, urls) {
  const out = [];
  for (const url of urls) {
    await page.open(url);
    for (const f of await page.evaluateAsync(pageValues)) out.push(`${url}: ${f}`);
    for (const f of page.failures() ?? []) out.push(`${url}: ${f}`);
  }
  return out;
}
