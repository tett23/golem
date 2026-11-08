// The text of the outlined SVG figures of the developer manual (docs/adr/0234
// section 4): the source (images/src/NAME.svg, with its text and the fonts
// of the manual) and the outline that scripts/manual/outline-figures.sh
// made of it (images/NAME.svg) are drawn at the same size, twice the size
// of the SVG in CSS pixels, and captured. For each text element of the
// source, the box of getBBox() widened by PAD is the place where the ink of
// that text is looked for in both images; the centres and the sizes of the
// two boxes of ink differ by at most 1 CSS pixel (I4), and their numbers of
// ink pixels by at most the fraction INK_LIMIT of the larger.
//
// The page is served from images/src/ of the root, so that the fonts of
// the source (../../fonts/) are those of ROOT/fonts.
import { capture, inkBox } from './pixels.mjs';

export const PAD = 2;
export const SCALE = 2;
// The largest difference of the numbers of ink pixels, as a fraction of the
// larger. On 2026-11-08 the six figures of the developer manual differed by
// at most 11.35% in Chromium 157.0.8103.38 and 18.96% in Safari 27.2
// (docs/ci-timings/2026-11-08-browser-workflow.md); one limit for both
// browsers, just above the larger (docs/adr/0234 section 4).
export const INK_LIMIT = 0.2;

export const HARNESS = `<!DOCTYPE html>
<html><head><meta charset="utf-8"/><style>
html, body { margin: 0; padding: 0; background: #fff; scrollbar-width: none; }
::-webkit-scrollbar { display: none; }
#fig { position: absolute; left: 0; top: 0; }
#fig > svg { display: block; }
</style></head><body><div id="fig"></div><script>
// Shows the SVG of the path P at SCALE times its size; its width and height.
window.showSvg = async (p, scale) => {
  const text = await (await fetch(p)).text();
  const svg = new DOMParser().parseFromString(text, 'image/svg+xml').documentElement;
  const w = parseFloat(svg.getAttribute('width')); const h = parseFloat(svg.getAttribute('height'));
  if (!svg.getAttribute('viewBox')) svg.setAttribute('viewBox', '0 0 ' + w + ' ' + h);
  svg.setAttribute('width', String(w * scale)); svg.setAttribute('height', String(h * scale));
  const fig = document.getElementById('fig');
  fig.replaceChildren(document.importNode(svg, true));
  await Promise.allSettled([...document.fonts].map((f) => f.load()));
  await document.fonts.ready;
  await new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)));
  return [w * scale, h * scale];
};
// The boxes of getBBox() of the text elements, in CSS pixels of the document.
window.textBoxes = () => [...document.querySelectorAll('#fig text')].map((t) => {
  const b = t.getBBox(); const m = t.getScreenCTM();
  const pts = [[b.x, b.y], [b.x + b.width, b.y], [b.x, b.y + b.height], [b.x + b.width, b.y + b.height]]
    .map(([x, y]) => [m.a * x + m.c * y + m.e + scrollX, m.b * x + m.d * y + m.f + scrollY]);
  const xs = pts.map((p) => p[0]); const ys = pts.map((p) => p[1]);
  return { text: t.textContent, x: Math.min(...xs), y: Math.min(...ys), width: Math.max(...xs) - Math.min(...xs), height: Math.max(...ys) - Math.min(...ys) };
});
</script></body></html>`;

// The comparison of the ink of one text in the source A and the outline B
// (CSS pixels): the failures of I4 and of the ink limit, and the measures.
export function compareInk(a, b, limit = INK_LIMIT) {
  if (!a || !b) return { failures: [`ink: ${a ? 'none in the outline' : 'none in the source'}`], measures: null };
  const centre = Math.max(Math.abs((a.x + a.width / 2) - (b.x + b.width / 2)), Math.abs((a.y + a.height / 2) - (b.y + b.height / 2)));
  const measures = {
    centre,
    size: Math.max(Math.abs(a.width - b.width), Math.abs(a.height - b.height)),
    ink: Math.abs(a.area - b.area) / Math.max(a.area, b.area),
  };
  const failures = [];
  if (measures.centre > 1) failures.push(`the centres differ by ${measures.centre} CSS px`);
  if (measures.size > 1) failures.push(`the sizes differ by ${measures.size} CSS px`);
  if (measures.ink > limit) failures.push(`the ink differs by ${(measures.ink * 100).toFixed(1)}% (limit ${(limit * 100).toFixed(1)}%)`);
  return { failures, measures };
}

// The check of the figures NAMES under the URL BASE of a server of the
// root, whose images/src/__svg-text.html is HARNESS. It returns the
// failures and, for each figure, the largest of each measure.
export async function svgText(page, base, names, { limit = INK_LIMIT } = {}) {
  const failures = [];
  const measured = {};
  await page.open(`${base}/images/src/__svg-text.html`);
  for (const name of names) {
    const [w, h] = await page.evaluateAsync(`showSvg(${JSON.stringify(`${name}.svg`)}, ${SCALE})`);
    const boxes = await page.evaluate('textBoxes()');
    const src = await capture(page, { x: 0, y: 0, width: w, height: h });
    const [w2, h2] = await page.evaluateAsync(`showSvg(${JSON.stringify(`../${name}.svg`)}, ${SCALE})`);
    if (w2 !== w || h2 !== h) { failures.push(`${name}: the outline is ${w2} x ${h2}, the source ${w} x ${h}`); continue; }
    const out = await capture(page, { x: 0, y: 0, width: w, height: h });
    const worst = { centre: 0, size: 0, ink: 0 };
    if (boxes.length === 0) failures.push(`${name}: no text in the source`);
    for (const box of boxes) {
      const r = { x: box.x - PAD, y: box.y - PAD, width: box.width + 2 * PAD, height: box.height + 2 * PAD };
      const c = compareInk(inkBox(src, r), inkBox(out, r), limit);
      for (const f of c.failures) failures.push(`${name}: "${box.text}": ${f}`);
      if (c.measures) for (const k of Object.keys(worst)) worst[k] = Math.max(worst[k], c.measures[k]);
    }
    measured[name] = worst;
  }
  return { failures, measured };
}
