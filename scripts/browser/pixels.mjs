// The pixels of a page for the checks (docs/adr/0234): an image of a
// rectangle of the document, made of screenshots of the viewport, and the
// ink in it. The image is in the pixels of the device; its scale is the
// devicePixelRatio, which Safari does not let the checks choose, so every
// result is turned back into CSS pixels before it is compared.
import { decode } from './png.mjs';

const frame = 'new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true))))';

// An image { width, height, rgba, scale, x, y } of the rectangle of the
// document X, Y, W, H (CSS pixels), from screenshots of the viewport of
// PAGE scrolled over it.
export async function capture(page, rect) {
  // whole CSS pixels, so that the pixels of the tiles fall on those of the image
  const x = Math.max(0, Math.floor(rect.x));
  const y = Math.max(0, Math.floor(rect.y));
  const width = Math.ceil(rect.x + rect.width) - x;
  const height = Math.ceil(rect.y + rect.height) - y;
  const view = await page.evaluate(`(() => {
    document.documentElement.style.scrollBehavior = 'auto';
    return [innerWidth, innerHeight, devicePixelRatio];
  })()`);
  const [vw, vh, scale] = view;
  const w = Math.max(1, Math.ceil(width * scale));
  const h = Math.max(1, Math.ceil(height * scale));
  const out = { width: w, height: h, rgba: new Uint8Array(w * h * 4).fill(255), scale, x, y };
  for (let ty = y; ty < y + height; ty += vh) {
    for (let tx = x; tx < x + width; tx += vw) {
      const [sx, sy] = await page.evaluate(`(() => { scrollTo({ left: ${tx}, top: ${ty}, behavior: 'instant' }); return [scrollX, scrollY]; })()`);
      await page.evaluateAsync(frame);
      const shot = decode(await page.screenshot());
      // the part of the tile [tx, tx + vw) x [ty, ty + vh) in the rectangle
      const x0 = Math.max(tx, x); const x1 = Math.min(tx + vw, x + width);
      const y0 = Math.max(ty, y); const y1 = Math.min(ty + vh, y + height);
      for (let py = Math.floor((y0 - y) * scale); py < Math.ceil((y1 - y) * scale) && py < h; py++) {
        const sy2 = Math.round((y + py / scale - sy) * scale);
        if (sy2 < 0 || sy2 >= shot.height) continue;
        for (let px = Math.floor((x0 - x) * scale); px < Math.ceil((x1 - x) * scale) && px < w; px++) {
          const sx2 = Math.round((x + px / scale - sx) * scale);
          if (sx2 < 0 || sx2 >= shot.width) continue;
          const s = (sy2 * shot.width + sx2) * 4;
          const o = (py * w + px) * 4;
          out.rgba[o] = shot.rgba[s]; out.rgba[o + 1] = shot.rgba[s + 1]; out.rgba[o + 2] = shot.rgba[s + 2]; out.rgba[o + 3] = 255;
        }
      }
    }
  }
  return out;
}

// The colour [r, g, b] of the pixel of IMG at the point X, Y of the
// document (CSS pixels).
export function colorAt(img, x, y) {
  const px = Math.min(img.width - 1, Math.max(0, Math.floor((x - img.x) * img.scale)));
  const py = Math.min(img.height - 1, Math.max(0, Math.floor((y - img.y) * img.scale)));
  const o = (py * img.width + px) * 4;
  return [img.rgba[o], img.rgba[o + 1], img.rgba[o + 2]];
}

// Ink: a pixel darker than this luminance (0 to 255). The text and the
// rules of the checks are dark on a light ground.
export const INK = 160;
const luminance = (r, g, b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

// The bounding box of the ink of IMG in the rectangle of the document R
// (CSS pixels), in CSS pixels, with the number of ink pixels (of the
// device) and that number in CSS pixels (count / scale^2); null without
// ink.
export function inkBox(img, r) {
  const s = img.scale;
  const px0 = Math.max(0, Math.floor((r.x - img.x) * s));
  const py0 = Math.max(0, Math.floor((r.y - img.y) * s));
  const px1 = Math.min(img.width, Math.ceil((r.x + r.width - img.x) * s));
  const py1 = Math.min(img.height, Math.ceil((r.y + r.height - img.y) * s));
  let minX = Infinity; let minY = Infinity; let maxX = -1; let maxY = -1; let count = 0;
  for (let py = py0; py < py1; py++) {
    for (let px = px0; px < px1; px++) {
      const o = (py * img.width + px) * 4;
      if (luminance(img.rgba[o], img.rgba[o + 1], img.rgba[o + 2]) < INK) {
        count++;
        if (px < minX) minX = px;
        if (px > maxX) maxX = px;
        if (py < minY) minY = py;
        if (py > maxY) maxY = py;
      }
    }
  }
  if (count === 0) return null;
  return {
    x: img.x + minX / s,
    y: img.y + minY / s,
    width: (maxX - minX + 1) / s,
    height: (maxY - minY + 1) / s,
    count,
    area: count / (s * s),
  };
}
