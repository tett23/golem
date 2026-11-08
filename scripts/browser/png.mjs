// A PNG decoder for the checks (docs/adr/0234): the screenshots of the
// browsers and the figures of the tRNS check. Every colour type and bit
// depth of PNG, tRNS, no interlace (Adam7 is refused).
//
//   decode(bytes) -> { width, height, rgba }
//
// rgba has 4 bytes per pixel, row after row. 16-bit samples keep their
// high byte; the alpha of tRNS compares the whole samples first, so a
// 16-bit colour that is transparent is alpha 0 and one that differs from
// it in the low byte only is 255.
import { inflateSync } from 'node:zlib';

const SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const CHANNELS = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 };

function paeth(a, b, c) {
  const p = a + b - c;
  const pa = Math.abs(p - a);
  const pb = Math.abs(p - b);
  const pc = Math.abs(p - c);
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}

// The rows of the image without their filters.
function unfilter(data, height, stride, bpp) {
  const out = Buffer.alloc(height * stride);
  for (let y = 0; y < height; y++) {
    const type = data[y * (stride + 1)];
    const line = data.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1));
    const row = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= bpp ? out[row + x - bpp] : 0;
      const b = y > 0 ? out[row - stride + x] : 0;
      const c = x >= bpp && y > 0 ? out[row - stride + x - bpp] : 0;
      const v = line[x];
      let r;
      switch (type) {
        case 0: r = v; break;
        case 1: r = v + a; break;
        case 2: r = v + b; break;
        case 3: r = v + ((a + b) >> 1); break;
        case 4: r = v + paeth(a, b, c); break;
        default: throw new Error(`png: unknown filter ${type}`);
      }
      out[row + x] = r & 255;
    }
  }
  return out;
}

export function decode(bytes) {
  const buf = Buffer.from(bytes);
  if (!buf.subarray(0, 8).equals(SIGNATURE)) throw new Error('png: not a PNG');
  let off = 8;
  let ihdr = null;
  let plte = null;
  let trns = null;
  const idat = [];
  while (off < buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString('latin1', off + 4, off + 8);
    const body = buf.subarray(off + 8, off + 8 + len);
    if (type === 'IHDR') ihdr = { width: body.readUInt32BE(0), height: body.readUInt32BE(4), depth: body[8], color: body[9], interlace: body[12] };
    else if (type === 'PLTE') plte = body;
    else if (type === 'tRNS') trns = body;
    else if (type === 'IDAT') idat.push(body);
    else if (type === 'IEND') break;
    off += 12 + len;
  }
  if (!ihdr) throw new Error('png: no IHDR');
  const { width, height, depth, color, interlace } = ihdr;
  if (interlace !== 0) throw new Error('png: interlaced PNG is not read');
  const channels = CHANNELS[color];
  if (!channels) throw new Error(`png: colour type ${color}`);
  const bitsPerPixel = channels * depth;
  const stride = Math.ceil((width * bitsPerPixel) / 8);
  const raw = unfilter(inflateSync(Buffer.concat(idat)), height, stride, Math.max(1, bitsPerPixel >> 3));
  // the screenshots: 8-bit RGBA, and 8-bit RGB without tRNS
  if (depth === 8 && color === 6) return { width, height, rgba: new Uint8Array(raw.buffer, raw.byteOffset, raw.length) };
  if (depth === 8 && color === 2 && !trns) {
    const rgba = new Uint8Array(width * height * 4);
    for (let i = 0, j = 0; i < raw.length; i += 3, j += 4) {
      rgba[j] = raw[i]; rgba[j + 1] = raw[i + 1]; rgba[j + 2] = raw[i + 2]; rgba[j + 3] = 255;
    }
    return { width, height, rgba };
  }
  const sample = (y, i) => { // the I-th sample of row Y, whole
    if (depth === 16) return raw.readUInt16BE(y * stride + i * 2);
    if (depth === 8) return raw[y * stride + i];
    const bit = i * depth;
    return (raw[y * stride + (bit >> 3)] >> (8 - depth - (bit & 7))) & ((1 << depth) - 1);
  };
  const to8 = (v) => (depth === 16 ? v >> 8 : depth === 8 ? v : Math.round((v * 255) / ((1 << depth) - 1)));
  const rgba = new Uint8Array(width * height * 4);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const o = (y * width + x) * 4;
      const s = (k) => sample(y, x * channels + k);
      let r; let g; let b; let a = 255;
      if (color === 3) {
        const i = s(0);
        r = plte[i * 3]; g = plte[i * 3 + 1]; b = plte[i * 3 + 2];
        if (trns && i < trns.length) a = trns[i];
      } else if (color === 0 || color === 4) {
        const v = s(0);
        r = g = b = to8(v);
        if (color === 4) a = to8(s(1));
        else if (trns && trns.length === 2 && v === trns.readUInt16BE(0)) a = 0;
      } else {
        const [vr, vg, vb] = [s(0), s(1), s(2)];
        r = to8(vr); g = to8(vg); b = to8(vb);
        if (color === 6) a = to8(s(3));
        else if (trns && trns.length === 6 && vr === trns.readUInt16BE(0) && vg === trns.readUInt16BE(2) && vb === trns.readUInt16BE(4)) a = 0;
      }
      rgba[o] = r; rgba[o + 1] = g; rgba[o + 2] = b; rgba[o + 3] = a;
    }
  }
  return { width, height, rgba };
}
