// Prototypes of the eight wallpaper styles chosen for Vibeshed, for porting to Swift.
// Each paints only from the theme palette and a seed, like WallpaperCanvas styles.
// Flow, Lens, Paper Cut, Automata and Growth are adapted from gart
// (https://github.com/igr/gart, (c) 2022 Igor Spasić, BSD 2-Clause License).

// Shared helpers that mirror WallpaperCanvas / ThemePalette / ThemeColor in Swift,
// so each prototype ports line-for-line.

// ---------- color ----------
class Color {
  constructor(r, g, b) { this.r = r; this.g = g; this.b = b; } // 0..1
  static hex(h) {
    const n = parseInt(h.replace('#', ''), 16);
    return new Color(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
  }
  mix(o, a) {
    a = Math.min(Math.max(a, 0), 1);
    return new Color(this.r + (o.r - this.r) * a, this.g + (o.g - this.g) * a, this.b + (o.b - this.b) * a);
  }
  get hsl() {
    const { r, g, b } = this, mx = Math.max(r, g, b), mn = Math.min(r, g, b), l = (mx + mn) / 2, d = mx - mn;
    if (d < 1e-5) return { h: 0, s: 0, l };
    const s = d / (1 - Math.abs(2 * l - 1));
    let h = mx === r ? 60 * (((g - b) / d) % 6) : mx === g ? 60 * ((b - r) / d + 2) : 60 * ((r - g) / d + 4);
    if (h < 0) h += 360;
    return { h, s: Math.min(s, 1), l };
  }
  static fromHSL(h, s, l) {
    h = ((h % 360) + 360) % 360; s = Math.min(Math.max(s, 0), 1); l = Math.min(Math.max(l, 0), 1);
    const c = (1 - Math.abs(2 * l - 1)) * s, x = c * (1 - Math.abs(((h / 60) % 2) - 1)), m = l - c / 2;
    const [r, g, b] = h < 60 ? [c, x, 0] : h < 120 ? [x, c, 0] : h < 180 ? [0, c, x] : h < 240 ? [0, x, c] : h < 300 ? [x, 0, c] : [c, 0, x];
    return new Color(r + m, g + m, b + m);
  }
  css(alpha = 1) {
    const f = v => Math.round(Math.min(Math.max(v, 0), 1) * 255);
    return `rgba(${f(this.r)},${f(this.g)},${f(this.b)},${alpha})`;
  }
  get rgb8() { return [this.r * 255, this.g * 255, this.b * 255]; }
}
Color.black = new Color(0, 0, 0);
Color.white = new Color(1, 1, 1);
const hueDistance = (a, b) => { const d = Math.abs(a - b) % 360; return Math.min(d, 360 - d); };

// ---------- palette (ThemePalette.resolve, the parts wallpapers use) ----------
function resolvePalette(def) {
  const c = {};
  for (const [k, v] of Object.entries(def.colors)) c[k] = Color.hex(v);
  const dark = def.mode === 'dark';
  const bg = c.background, fg = c.foreground;
  c.accent = c.accent || c.blue;
  c.orange = c.orange || c.yellow;
  c.dark_background = c.dark_background || bg.mix(Color.black, dark ? 0.25 : 0.04);
  c.darker_background = c.darker_background || bg.mix(Color.black, dark ? 0.5 : 0.08);
  return {
    mode: def.mode, name: def.name, isDark: dark,
    background: bg, foreground: fg, accent: c.accent,
    darkBackground: c.dark_background, darkerBackground: c.darker_background,
    red: c.red, orange: c.orange, yellow: c.yellow, green: c.green, cyan: c.cyan, blue: c.blue, magenta: c.magenta,
  };
}

// ---------- seeded randomness (stands in for SeededGenerator) ----------
function fnv1a32(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) { h ^= str.charCodeAt(i); h = Math.imul(h, 0x01000193); }
  return h >>> 0;
}
class Rng {
  constructor(seed) { this.s = seed >>> 0; }
  next() { // mulberry32
    let t = (this.s = (this.s + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }
  unit() { return this.next(); }
  between(a, b) { return a + (b - a) * this.next(); }
  int(n) { return Math.min(Math.floor(this.next() * n), n - 1); }
  pick(a) { return a[this.int(a.length)]; }
  bool() { return this.next() < 0.5; }
}

// ---------- ValueNoise, same construction as the Swift one ----------
class ValueNoise {
  constructor(seed) { this.seed = seed >>> 0; }
  lattice(x, y) {
    let h = this.seed ^ Math.imul(x | 0, 0x9e3779b1) ^ Math.imul(y | 0, 0x85ebca77);
    h = Math.imul(h ^ (h >>> 16), 0x7feb352d); h = Math.imul(h ^ (h >>> 15), 0x846ca68b); h ^= h >>> 16;
    return (h >>> 0) / 4294967296;
  }
  value(x, y) {
    const x0 = Math.floor(x), y0 = Math.floor(y);
    const s = v => v * v * v * (v * (v * 6 - 15) + 10);
    const fx = s(x - x0), fy = s(y - y0);
    const top = this.lattice(x0, y0) + (this.lattice(x0 + 1, y0) - this.lattice(x0, y0)) * fx;
    const bot = this.lattice(x0, y0 + 1) + (this.lattice(x0 + 1, y0 + 1) - this.lattice(x0, y0 + 1)) * fx;
    return top + (bot - top) * fy;
  }
  fractal(x, y, octaves = 4) {
    let t = 0, a = 0.5, f = 1, n = 0;
    for (let i = 0; i < octaves; i++) { t += this.value(x * f, y * f) * a; n += a; a *= 0.5; f *= 2.03; }
    return t / n;
  }
}

const smoothstep = (e0, e1, v) => { const p = Math.min(Math.max((v - e0) / (e1 - e0), 0), 1); return p * p * (3 - 2 * p); };
const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (v, a, b) => Math.min(Math.max(v, a), b);

// ---------- the canvas a style paints on (WallpaperCanvas) ----------
class Wall {
  constructor(canvas, palette, seed) {
    this.cv = canvas; this.ctx = canvas.getContext('2d');
    this.width = canvas.width; this.height = canvas.height;
    this.palette = palette; this.rng = new Rng(seed); this.noise = new ValueNoise(seed ^ 0xa5a55a5a);
    this.unit = this.height / 1000;
  }
  get isDark() { return this.palette.isDark; }
  get base() { return this.isDark ? this.palette.darkerBackground : this.palette.background; }
  get surface() { return this.isDark ? this.palette.background : this.palette.darkBackground; }
  get unitWidth() { return this.width / this.unit; }
  get unitHeight() { return 1000; }
  harmony(n) {
    const p = this.palette, ah = p.accent.hsl.h;
    const hues = [p.red, p.orange, p.yellow, p.green, p.cyan, p.blue, p.magenta]
      .filter(c => c !== p.accent && c.hsl.s > 0.12)
      .sort((a, b) => hueDistance(a.hsl.h, ah) - hueDistance(b.hsl.h, ah));
    return [p.accent, ...hues].slice(0, n);
  }
  muted(c, amount) { return c.mix(this.base, amount); }
  enterUnitSpace() { this.ctx.setTransform(this.unit, 0, 0, this.unit, 0, 0); } // canvas is already y-down
  hairline(units, px = 1) { return Math.max(units, px / this.unit); }
  fill(color) { const t = this.ctx.getTransform(); this.ctx.setTransform(1, 0, 0, 1, 0, 0); this.ctx.fillStyle = color.css(); this.ctx.fillRect(0, 0, this.width, this.height); this.ctx.setTransform(t); }
}
const cycling = (arr, i) => arr[((i % arr.length) + arr.length) % arr.length];

// ---------- shared helpers ----------

// Paints an RGB float buffer (sim resolution) onto the canvas, scaled up with smoothing.
function blitBuffer(w, buf, cols, rows) {
  const off = document.createElement('canvas');
  off.width = cols; off.height = rows;
  const octx = off.getContext('2d'), img = octx.createImageData(cols, rows);
  for (let i = 0; i < cols * rows; i++) {
    img.data[i * 4] = buf[i * 3]; img.data[i * 4 + 1] = buf[i * 3 + 1]; img.data[i * 4 + 2] = buf[i * 3 + 2]; img.data[i * 4 + 3] = 255;
  }
  octx.putImageData(img, 0, 0);
  const ctx = w.ctx;
  ctx.save(); ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.imageSmoothingEnabled = true; ctx.imageSmoothingQuality = 'high';
  ctx.drawImage(off, 0, 0, w.width, w.height);
  ctx.restore();
}

// A ramp through several colors, t in 0...1.
function rampOf(colors) {
  return t => {
    t = clamp(t, 0, 0.99999);
    const s = t * (colors.length - 1), i = Math.floor(s);
    return colors[i].mix(colors[i + 1], s - i);
  };
}

const STYLES = {};

// =====================================================================================
// FLOW — evenly spaced streamlines (Jobard & Lefer) through a noise field.
// gart: arts/flowforce/perl (look), gart/flow2/Streamlines.kt (placement + taper).
// =====================================================================================
function streamlines(angleAt, opts) {
  const { left, top, right, bottom, dSep, dTest, step, minLength, rng } = opts;
  const SELF_SKIP = 2 * dTest, seedRoom = Math.max(dTest, dSep * 0.99);
  const cols = Math.ceil((right - left) / dSep), rows = Math.ceil((bottom - top) / dSep);
  const grid = Array.from({ length: cols * rows }, () => []);
  const cellOf = (x, y) => clamp(Math.floor((y - top) / dSep), 0, rows - 1) * cols + clamp(Math.floor((x - left) / dSep), 0, cols - 1);
  const xs = [], ys = [], arcs = [], owners = [];
  const lines = [], seeds = [];
  const inside = (x, y) => x >= left && x < right && y >= top && y < bottom;
  const add = (x, y, arc, line) => { grid[cellOf(x, y)].push(xs.length); xs.push(x); ys.push(y); arcs.push(arc); owners.push(line); };
  const near = (x, y, fn) => {
    const cx = clamp(Math.floor((x - left) / dSep), 0, cols - 1), cy = clamp(Math.floor((y - top) / dSep), 0, rows - 1);
    for (let j = Math.max(cy - 1, 0); j <= Math.min(cy + 1, rows - 1); j++)
      for (let i = Math.max(cx - 1, 0); i <= Math.min(cx + 1, cols - 1); i++)
        for (const id of grid[j * cols + i]) if (fn(id) === false) return false;
    return true;
  };
  const isFree = (x, y, r, line, arc) => {
    const r2 = r * r;
    return near(x, y, id => {
      const dx = xs[id] - x, dy = ys[id] - y;
      if (dx * dx + dy * dy < r2 && (owners[id] !== line || Math.abs(arcs[id] - arc) > SELF_SKIP)) return false;
    });
  };
  // RK2 along the unit direction field
  const advance = (x, y, h) => {
    const a1 = angleAt(x, y);
    const mx = x + Math.cos(a1) * h * 0.5, my = y + Math.sin(a1) * h * 0.5;
    const a2 = angleAt(mx, my);
    return [x + Math.cos(a2) * h, y + Math.sin(a2) * h];
  };
  const walk = (sx, sy, h, line) => {
    let x = sx, y = sy, walked = 0;
    for (let n = 0; n < 100000; n++) {
      const [px, py] = advance(x, y, h);
      const len = Math.hypot(px - x, py - y);
      const arc = h > 0 ? walked + len : -(walked + len);
      if (!inside(px, py) || !isFree(px, py, dTest, line, arc)) break;
      walked += len; x = px; y = py; add(x, y, arc, line);
    }
    return walked;
  };
  const grow = (sx, sy) => {
    const line = lines.length, first = xs.length;
    add(sx, sy, 0, line);
    const ahead = walk(sx, sy, step, line);
    const mid = xs.length;
    const behind = walk(sx, sy, -step, line);
    const end = xs.length;
    if (end - first < 2 || ahead + behind < minLength) {
      for (let id = end - 1; id >= first; id--) grid[cellOf(xs[id], ys[id])].pop();
      xs.length = ys.length = arcs.length = owners.length = first;
      return;
    }
    const ids = [];
    for (let id = end - 1; id >= mid; id--) ids.push(id);
    for (let id = first; id < mid; id++) ids.push(id);
    lines.push(ids);
    for (let k = 0; k < ids.length; k++) {
      const a = ids[Math.max(k - 1, 0)], b = ids[Math.min(k + 1, ids.length - 1)];
      const len = Math.hypot(xs[b] - xs[a], ys[b] - ys[a]);
      if (len === 0) continue;
      const nx = -(ys[b] - ys[a]) / len * dSep, ny = (xs[b] - xs[a]) / len * dSep;
      seeds.push(xs[ids[k]] + nx, ys[ids[k]] + ny, xs[ids[k]] - nx, ys[ids[k]] - ny);
    }
  };
  // cover seeds: middles of a dSep grid in random order
  const order = Array.from({ length: cols * rows }, (_, i) => i);
  for (let i = order.length - 1; i > 0; i--) { const j = rng.int(i + 1); [order[i], order[j]] = [order[j], order[i]]; }
  let next = 0;
  for (;;) {
    let sx, sy;
    const n = seeds.length / 2;
    if (n > 0) {
      const k = rng.int(n);
      sx = seeds[2 * k]; sy = seeds[2 * k + 1];
      seeds[2 * k] = seeds[2 * n - 2]; seeds[2 * k + 1] = seeds[2 * n - 1]; seeds.length -= 2;
    } else if (next < order.length) {
      const o = order[next++];
      sx = left + (o % cols + 0.5) * dSep; sy = top + (Math.floor(o / cols) + 0.5) * dSep;
    } else break;
    if (inside(sx, sy) && isFree(sx, sy, seedRoom, -1, 0)) grow(sx, sy);
  }
  // clearance → taper (1 in the open, 0 where the line stopped against another)
  return lines.map((ids, line) => {
    const pts = ids.map(id => [xs[id], ys[id]]);
    const taper = ids.map(id => {
      let best = dSep * dSep;
      near(xs[id], ys[id], o => {
        if (owners[o] === line && Math.abs(arcs[o] - arcs[id]) <= SELF_SKIP) return;
        const dx = xs[o] - xs[id], dy = ys[o] - ys[id];
        best = Math.min(best, dx * dx + dy * dy);
      });
      return clamp((Math.sqrt(best) - dTest) / (dSep - dTest), 0, 1);
    });
    return { pts, taper };
  });
}

// A filled outline of a polyline whose width varies point by point, with round ends.
function ribbon(ctx, pts, widths) {
  const n = pts.length, L = [], R = [];
  for (let i = 0; i < n; i++) {
    const a = pts[Math.max(i - 1, 0)], b = pts[Math.min(i + 1, n - 1)];
    const len = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
    const nx = -(b[1] - a[1]) / len, ny = (b[0] - a[0]) / len, h = widths[i] / 2;
    L.push([pts[i][0] + nx * h, pts[i][1] + ny * h]); R.push([pts[i][0] - nx * h, pts[i][1] - ny * h]);
  }
  ctx.beginPath();
  ctx.moveTo(L[0][0], L[0][1]);
  for (let i = 1; i < n; i++) ctx.lineTo(L[i][0], L[i][1]);
  for (let i = n - 1; i >= 0; i--) ctx.lineTo(R[i][0], R[i][1]);
  ctx.closePath();
  ctx.fill();
  for (const i of [0, n - 1]) { ctx.beginPath(); ctx.arc(pts[i][0], pts[i][1], widths[i] / 2, 0, Math.PI * 2); ctx.fill(); }
}

STYLES.flow = function paintFlow(w) {
  w.enterUnitSpace();
  w.fill(w.base);
  const ctx = w.ctx, rng = w.rng, W = w.unitWidth, H = 1000;
  const freq = rng.between(0.0009, 0.0014), turns = rng.between(0.9, 1.3), ox = rng.between(0, 500), oy = rng.between(0, 500);
  const swirl = rng.between(0, Math.PI * 2);
  const angleAt = (x, y) => swirl + (w.noise.fractal(x * freq + ox, y * freq + oy, 3) - 0.5) * Math.PI * 2 * turns;
  const dSep = rng.between(12, 15);
  const lines = streamlines(angleAt, {
    left: -dSep * 2, top: -dSep * 2, right: W + dSep * 2, bottom: H + dSep * 2,
    dSep, dTest: dSep * 0.5, step: 1.5, minLength: dSep * 2, rng,
  });

  // perl: width follows a slow cosine across the page, color follows width
  const hues = w.harmony(4);
  const ramp = [w.muted(hues[2] || hues[1], 0.45), w.muted(hues[1], 0.2), hues[0], hues[0].mix(w.palette.foreground, 0.35)];
  const colorAt = t => { const s = clamp(t, 0, 0.999) * (ramp.length - 1), i = Math.floor(s); return ramp[i].mix(ramp[i + 1], s - i); };
  const waveK = rng.between(0.006, 0.012), phase = rng.between(0, Math.PI * 2);

  const disc = { x: W * rng.between(0.22, 0.78), y: H * rng.between(0.38, 0.68), r: rng.between(95, 135) };
  const discColor = w.isDark ? w.palette.foreground : w.palette.foreground.mix(w.palette.background, 0.1);
  let discDrawn = false;

  const middles = lines.map(l => l.pts[Math.floor(l.pts.length / 2)]);
  const order = lines.map((_, i) => i).sort((a, b) => middles[a][1] - middles[b][1]);
  for (const i of order) {
    const { pts, taper } = lines[i], m = middles[i];
    const t = Math.cos(m[0] * waveK + phase) * 0.5 + 0.5;
    const width = dSep * lerp(0.18, 0.82, t);
    const color = colorAt(t);
    if (rng.int(6) === 0) {
      // one line in six is a string of beads
      ctx.fillStyle = color.css(0.45);
      let acc = 0;
      for (let k = 1; k < pts.length; k++) {
        acc += Math.hypot(pts[k][0] - pts[k - 1][0], pts[k][1] - pts[k - 1][1]);
        if (acc >= width * 1.25) { acc = 0; ctx.beginPath(); ctx.arc(pts[k][0], pts[k][1], width * 0.5 * Math.max(taper[k], 0.3), 0, Math.PI * 2); ctx.fill(); }
      }
    } else {
      ctx.fillStyle = color.css();
      ribbon(ctx, pts, taper.map(tp => width * Math.max(Math.pow(tp, 0.6), 0.12)));
    }
    if (!discDrawn && m[1] > disc.y) {
      discDrawn = true;
      ctx.fillStyle = discColor.css();
      ctx.beginPath(); ctx.arc(disc.x, disc.y, disc.r, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = w.base.css(); ctx.lineWidth = 18;
      ctx.beginPath(); ctx.arc(disc.x, disc.y, disc.r + 9, 0, Math.PI * 2); ctx.stroke();
    }
  }
};

// =====================================================================================
// LENS — tilted bands and a sun seen through a gravitational lens.
// gart: arts/sf/src/sf/SF14.kt. Per pixel; edges are filtered analytically, no supersampling.
// =====================================================================================
STYLES.lens = function paintLens(w) {
  const W = w.width, H = w.height, u = w.unit, rng = w.rng, p = w.palette;
  const back = w.base.rgb8, ink = p.foreground.mix(w.base, w.isDark ? 0.18 : 0.1).rgb8, bold = p.accent.rgb8;
  const holeTone = w.isDark ? back : ink;
  const e = 240 * u * rng.between(0.85, 1.15), e2 = e * e, hole = e * 0.38;
  const lx = W * rng.between(0.3, 0.7), ly = H * rng.between(0.32, 0.68);
  const a = rng.between(0, Math.PI * 2), align = rng.between(0.3, 0.7);
  const sunX = lx + Math.cos(a) * align * e, sunY = ly + Math.sin(a) * align * e, sunR = 0.31 * e;
  const phase = rng.unit(), PITCH = 31 * u, DUTY = 0.32;
  const tilt = (rng.between(18, 42) * (rng.bool() ? 1 : -1)) * Math.PI / 180;
  const nx = -Math.sin(tilt), ny = Math.cos(tilt);
  const frac = v => v - Math.floor(v);
  const ramp = v => Math.floor(v) * DUTY + Math.min(frac(v), DUTY);
  const stripe = (v, fw) => fw < 1e-4 ? (frac(v) < DUTY ? 1 : 0) : clamp((ramp(v + fw / 2) - ramp(v - fw / 2)) / fw, 0, 1);
  const cover = d => clamp(0.5 - d, 0, 1);

  const img = w.ctx.createImageData(W, H), data = img.data;
  for (let py = 0; py < H; py++) {
    for (let px = 0; px < W; px++) {
      const x = px + 0.5, y = py + 0.5, dx = x - lx, dy = y - ly, r2 = dx * dx + dy * dy;
      const dark = cover(Math.sqrt(r2) - hole);
      let band = 0, sun = 0;
      if (dark < 1) {
        const k = e2 / r2, k2 = 2 * k / r2;
        const bx = x - k * dx, by = y - k * dy;
        const j11 = 1 - (k - k2 * dx * dx), j22 = 1 - (k - k2 * dy * dy), j12 = k2 * dx * dy;
        const uu = (bx * nx + by * ny) / PITCH + phase;
        const du = Math.hypot(j11 * nx + j12 * ny, j12 * nx + j22 * ny) / PITCH;
        band = stripe(uu, du);
        const sx = bx - sunX, sy = by - sunY, sd = Math.hypot(sx, sy);
        const gs = Math.hypot(j11 * sx + j12 * sy, j12 * sx + j22 * sy) / sd;
        sun = sd < 1e-4 || gs < 1e-6 ? (sd < sunR ? 1 : 0) : cover((sd - sunR) / gs);
      }
      const o = (py * W + px) * 4;
      for (let c = 0; c < 3; c++) data[o + c] = lerp(lerp(lerp(back[c], ink[c], band), bold[c], sun), holeTone[c], dark);
      data[o + 3] = 255;
    }
  }
  w.ctx.putImageData(img, 0, 0);
};

// =====================================================================================
// PAPER — stacked cut-paper sheets with soft shadows, parting around a disc.
// gart: arts/layers/src/strata/Strata.kt
// =====================================================================================
function bSpline(points, samples) {
  const out = [];
  for (let i = 0; i + 3 < points.length; i++) {
    const [p0, p1, p2, p3] = points.slice(i, i + 4);
    for (let s = 0; s < samples; s++) {
      const t = s / samples, t2 = t * t, t3 = t2 * t;
      const b0 = (1 - t) ** 3, b1 = 3 * t3 - 6 * t2 + 4, b2 = -3 * t3 + 3 * t2 + 3 * t + 1, b3 = t3;
      out.push([(b0 * p0[0] + b1 * p1[0] + b2 * p2[0] + b3 * p3[0]) / 6, (b0 * p0[1] + b1 * p1[1] + b2 * p2[1] + b3 * p3[1]) / 6]);
    }
  }
  out.push(points[points.length - 1]);
  return out;
}

STYLES.papercut = function paintPaperCut(w) {
  w.enterUnitSpace();
  const ctx = w.ctx, rng = w.rng, p = w.palette, W = w.unitWidth, H = 1000, u = w.unit;
  // cool sheets, warm sun: whichever side the accent is on keeps it
  const warm = c => { const h = c.hsl.h; return h < 75 || h > 320; };
  const hues = w.harmony(7);
  const sheet = warm(p.accent) ? (hues.find(c => !warm(c)) || p.blue) : p.accent;
  const sheet2 = hues.filter(c => !warm(c) && c !== sheet)[0] || p.cyan;
  const sun = warm(p.accent) ? p.accent : (p.orange !== p.yellow ? p.orange : p.red);
  const orb = [sun.mix(p.yellow, 0.55).mix(Color.white, w.isDark ? 0.12 : 0), sun, sun.mix(p.red, 0.45).mix(Color.black, 0.08)];
  const dark = w.isDark;
  const upperColor = t => dark ? sheet.mix(sheet2, t * 0.6).mix(w.base, lerp(0.08, 0.62, t))
                               : sheet.mix(sheet2, t * 0.6).mix(p.background, lerp(0.72, 0.15, t));
  const lowerColor = t => dark ? sheet2.mix(sheet, t * 0.4).mix(w.base, lerp(0.42, 0.66, t))
                               : sheet2.mix(sheet, t * 0.4).mix(Color.black, lerp(0.15, 0.32, t));
  const ground = dark ? [sheet2.mix(w.base, 0.8), w.base.mix(Color.black, 0.3)] : [sheet2.mix(Color.black, 0.35), sheet2.mix(Color.black, 0.5)];

  const s = 1000 / 1100;
  const P = {
    upper: 5, lower: 4, gap: 105 * s * rng.between(0.9, 1.1), wave: rng.between(150, 195),
    crest: rng.between(0.25, 0.75), drift: rng.between(-0.02, 0.02), bend: 0.16, jitter: 18 * s, opening: rng.between(0.44, 0.52),
    shade: 0.07, shadowY: 18 * s, shadowBlur: 18 * s, shadowAlpha: dark ? 0.46 : 0.3,
  };
  const ANCHORS = 12, margin = W * 0.18, span = W + margin * 2;
  const shared = Array.from({ length: ANCHORS }, () => rng.unit() * 2 - 1);
  const edge = (meanY, amplitude, layer, count, lower) => {
    const centered = layer - (count - 1) * 0.5;
    const crest = P.crest + (lower ? -0.022 : 0) + centered * P.drift;
    const secondaryPhase = rng.unit() * 0.16 - 0.08 + (lower ? 0.12 : 0);
    const pts = [];
    for (let k = 0; k < ANCHORS; k++) {
      const x = -margin + span * k / (ANCHORS - 1), uu = x / W;
      const dominant = -Math.cos(Math.PI * 2 * (uu - crest));
      const secondary = Math.sin(Math.PI * 4 * (uu - P.crest * 0.35 + secondaryPhase));
      const drift = P.jitter * (shared[k] * 0.68 + (rng.unit() * 2 - 1) * 0.32);
      pts.push([x, meanY + amplitude * (dominant + P.bend * secondary) + drift]);
    }
    return bSpline([pts[0], pts[0], ...pts, pts[pts.length - 1], pts[pts.length - 1]], 24);
  };
  const lighten = (c, a) => c.mix(Color.white, a), darken = (c, a) => c.mix(Color.black, a);
  const shadowRGB = dark ? [2, 7, 13] : darken(sheet, 0.6).rgb8.map(Math.round);
  const paper = (pts, color, shadowScale = 1) => {
    ctx.beginPath();
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (const q of pts) ctx.lineTo(q[0], q[1]);
    ctx.lineTo(W * 1.18, -H * 0.12); ctx.lineTo(-W * 0.18, -H * 0.12); ctx.closePath();
    const g = ctx.createLinearGradient(0, 0, W, H);
    g.addColorStop(0, lighten(color, P.shade * 0.55).css()); g.addColorStop(0.52, color.css()); g.addColorStop(1, darken(color, P.shade).css());
    ctx.fillStyle = g;
    ctx.shadowColor = `rgba(${shadowRGB.join(',')},${P.shadowAlpha * shadowScale})`;
    ctx.shadowOffsetY = P.shadowY * u; ctx.shadowBlur = P.shadowBlur * 2 * u; // canvas blur ≈ 2σ, in device px
    ctx.fill();
    ctx.shadowColor = 'transparent';
  };

  const gg = ctx.createLinearGradient(0, H * 0.6, W, H);
  gg.addColorStop(0, ground[0].css()); gg.addColorStop(1, ground[1].css());
  ctx.fillStyle = gg; ctx.fillRect(-10, -10, W + 20, H + 20);

  const lowerStart = H * P.opening + P.gap * 0.28;
  for (let layer = P.lower - 1; layer >= 0; layer--) {
    const t = layer / (P.lower - 1);
    paper(edge(lowerStart + layer * P.gap, P.wave * (0.64 + 0.12 * t), layer, P.lower, true), lowerColor(t));
  }

  // the disc, laid between the two families
  // the sun sits in the gap where the deepest front sheet rides highest (its crest), just under its edge
  const ry = H * rng.between(0.16, 0.2), rx = ry * rng.between(1.0, 1.12);
  const cx = W * (P.crest + rng.between(-0.04, 0.04)), cy = H * P.opening - P.wave + ry * rng.between(0.35, 0.7);
  const tilt = rng.between(-24, 24) * Math.PI / 180;
  ctx.save();
  ctx.translate(cx, cy); ctx.rotate(tilt);
  const og = ctx.createLinearGradient(-rx * 0.24, -ry, rx * 0.18, ry);
  orb.forEach((c, i) => og.addColorStop(i / (orb.length - 1), c.css()));
  ctx.fillStyle = og;
  ctx.shadowColor = `rgba(5,7,12,${P.shadowAlpha * 0.86})`; ctx.shadowOffsetY = P.shadowY * 0.62 * u; ctx.shadowBlur = P.shadowBlur * 2.3 * u;
  ctx.beginPath(); ctx.ellipse(0, 0, rx, ry, 0, 0, Math.PI * 2); ctx.fill();
  ctx.shadowColor = 'transparent';
  ctx.clip();
  for (const [edgeY, rise, alpha] of [[-ry * 0.16, ry * 0.24, 0.12], [ry * 0.3, ry * 0.28, 0.15]]) {
    const sp = rx * 1.34;
    ctx.beginPath(); ctx.ellipse(0, edgeY, sp, rise, 0, Math.PI, 0);
    ctx.lineTo(sp, edgeY + ry * 1.65); ctx.lineTo(-sp, edgeY + ry * 1.65); ctx.closePath();
    ctx.fillStyle = `rgba(255,232,180,${alpha})`; ctx.fill();
  }
  ctx.restore();

  const upperDeepY = H * P.opening;
  for (let layer = P.upper - 1; layer >= 0; layer--) {
    const t = layer / (P.upper - 1);
    paper(edge(upperDeepY - (P.upper - 1 - layer) * P.gap, P.wave * (0.34 + 0.66 * t), layer, P.upper, false), upperColor(t));
  }
};

// =====================================================================================
// AUTOMATA — panels of Wolfram's elementary cellular automata (3- and 5-cell rules),
// laid out by recursive division, each in two palette tones.
// gart: arts/rule/src/rule/Rule.kt, gart/cellular/rule/Rule.kt
// =====================================================================================
function automaton(rule, aside, cols, gens, rng) {
  const span = 2 * aside + 1, lookup = [];
  for (let v = 0; v < 2 ** span; v++) lookup.push(Math.floor(rule / 2 ** v) % 2 === 1);
  let row = Array.from({ length: cols }, () => rng.unit() < 0.5);
  const out = [];
  for (let g = 0; g < gens; g++) {
    out.push(row);
    const nr = new Array(cols);
    for (let x = 0; x < cols; x++) {
      let v = 0;
      for (let k = -aside; k <= aside; k++) v = v * 2 + (row[(x + k + cols) % cols] ? 1 : 0);
      nr[x] = lookup[v];
    }
    row = nr;
  }
  return out;
}

STYLES.automata = function paintAutomata(w) {
  w.enterUnitSpace();
  const ctx = w.ctx, rng = w.rng, p = w.palette, W = w.unitWidth, H = 1000;
  const rules = [[30, 1], [45, 1], [73, 1], [86, 1], [89, 1], [105, 1], [110, 1], [124, 1], [135, 1], [150, 1], [54, 1], [57, 1],
    [838, 2], [209218, 2], [774857, 2], [37788005, 2], [22047073, 2], [1069090987, 2]];
  const gap = 100 * (1000 / 1024);
  const divide = rects => rects.flatMap(r => {
    if (r.w < gap * 4 || r.h < gap * 4) return [r];
    const dw = (1 + rng.int(Math.floor(r.w / gap) - 1)) * gap, dh = (1 + rng.int(Math.floor(r.h / gap) - 1)) * gap;
    return [{ x: r.x, y: r.y, w: dw, h: dh }, { x: r.x + dw, y: r.y, w: r.w - dw, h: dh }, { x: r.x, y: r.y + dh, w: dw, h: r.h - dh }, { x: r.x + dw, y: r.y + dh, w: r.w - dw, h: r.h - dh }];
  });
  let rects = [{ x: 0, y: 0, w: W, h: H }];
  for (let k = 0; k < 3; k++) rects = divide(rects);
  const hues = w.harmony(5);
  const frame = w.isDark ? w.base.mix(Color.black, 0.3) : p.background;
  w.fill(frame);
  const cellSize = 4, border = 7;
  for (const r of rects) {
    const [rule, aside] = rng.pick(rules);
    const cols = Math.ceil(r.w / cellSize), gens = Math.ceil(r.h / cellSize);
    const grid = automaton(rule, aside, cols, gens + 40, rng).slice(40); // skip the start-up rows
    const on = rng.pick(hues), offBase = w.isDark ? w.muted(rng.pick(hues), 0.78) : p.background.mix(rng.pick(hues), 0.15);
    const onC = w.isDark ? on : on.mix(Color.black, 0.1);
    ctx.save();
    ctx.beginPath(); ctx.rect(r.x + border / 2, r.y + border / 2, r.w - border, r.h - border); ctx.clip();
    ctx.fillStyle = offBase.css(); ctx.fillRect(r.x, r.y, r.w, r.h);
    ctx.fillStyle = onC.css();
    for (let y = 0; y < gens; y++) for (let x = 0; x < cols; x++) if (grid[y][x]) ctx.fillRect(r.x + x * cellSize, r.y + y * cellSize, cellSize, cellSize);
    ctx.restore();
  }
};

// =====================================================================================
// CYCLIC — Griffeath's cyclic cellular automaton: N states in a ring; a cell moves on to
// the next state when enough neighbours already hold it. From noise, spirals take over.
// Fisch, Gravner & Griffeath, "Threshold-range scaling of excitable cellular automata" (1991).
// =====================================================================================
STYLES.cyclic = function paintCyclic(w) {
  const rng = w.rng, p = w.palette;
  const rules = [
    { name: 'spirals', range: 1, threshold: 1, states: 14, moore: false, steps: 420 },
    { name: 'cca', range: 1, threshold: 1, states: 14, moore: true, steps: 900 },
    { name: 'squarish', range: 2, threshold: 5, states: 9, moore: true, steps: 260 },
  ];
  const rule = w.cyclicRule ? rules.find(x => x.name === w.cyclicRule) : rng.pick([rules[0], rules[0], rules[1]]);
  const size = 4, cols = Math.ceil(w.unitWidth / size), rows = Math.ceil(1000 / size), n = cols * rows;
  let cur = new Uint8Array(n), nxt = new Uint8Array(n);
  for (let i = 0; i < n; i++) cur[i] = rng.int(rule.states);
  const offs = [];
  for (let j = -rule.range; j <= rule.range; j++) for (let i = -rule.range; i <= rule.range; i++) {
    if (!i && !j) continue;
    if (!rule.moore && Math.abs(i) + Math.abs(j) > rule.range) continue;
    offs.push([i, j]);
  }
  for (let s = 0; s < rule.steps; s++) {
    for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
      const i = y * cols + x, want = (cur[i] + 1) % rule.states;
      let count = 0;
      for (const [ox, oy] of offs) {
        const xx = (x + ox + cols) % cols, yy = (y + oy + rows) % rows;
        if (cur[yy * cols + xx] === want && ++count >= rule.threshold) break;
      }
      nxt[i] = count >= rule.threshold ? want : cur[i];
    }
    [cur, nxt] = [nxt, cur];
  }
  // the states go round the palette once, as a smooth cycle
  const hues = w.harmony(4);
  const ring = w.isDark
    ? [hues[0], w.muted(hues[1] || hues[0], 0.25), w.base.mix(hues[0], 0.12), w.muted(hues[2] || hues[0], 0.3)]
    : [hues[0].mix(p.background, 0.15), (hues[1] || hues[0]).mix(p.background, 0.45), p.background, (hues[2] || hues[0]).mix(p.background, 0.4)];
  const colors = Array.from({ length: rule.states }, (_, s) => {
    const t = s / rule.states * ring.length, i = Math.floor(t);
    return ring[i].mix(ring[(i + 1) % ring.length], smoothstep(0, 1, t - i));
  });
  w.enterUnitSpace();
  for (let y = 0; y < rows; y++) for (let x = 0; x < cols; x++) {
    w.ctx.fillStyle = colors[cur[y * cols + x]].css();
    w.ctx.fillRect(x * size, y * size, size + 0.05, size + 0.05);
  }
};

// =====================================================================================
// CHLADNI — sand on a vibrating plate: grains drift down the slope of |f| and pile up on
// the nodal lines, where the plate stands still. f mixes two square-plate modes,
// cos(nπx)cos(mπy) and cos(mπx)cos(nπy) (Ernst Chladni, 1787).
// =====================================================================================
STYLES.chladni = function paintChladni(w) {
  w.enterUnitSpace();
  const rng = w.rng, p = w.palette, ctx = w.ctx, W = w.unitWidth, H = 1000, A = W / H;
  let n = 2 + rng.int(6), m = 2 + rng.int(6);
  while (m === n) m = 2 + rng.int(6);
  const sign = rng.pick([-1, 1]);
  // the whole screen is the plate: x runs 0…aspect, y 0…1, and the two modes are mirror twins
  const f = (x, y) => Math.cos(n * Math.PI * x) * Math.cos(m * Math.PI * y) + sign * Math.cos(m * Math.PI * x) * Math.cos(n * Math.PI * y);
  w.fill(w.isDark ? w.base : p.background);
  const grains = 700000, X = new Float32Array(grains), Y = new Float32Array(grains);
  for (let i = 0; i < grains; i++) { X[i] = rng.unit() * A; Y[i] = rng.unit(); }
  const h = 1e-3;
  for (let s = 0; s < 80; s++) for (let i = 0; i < grains; i++) {
    const x = X[i], y = Y[i], v = f(x, y);
    const gx = (f(x + h, y) - v) / h, gy = (f(x, y + h) - v) / h;
    // down the slope of v², plus a shake that's strongest where the plate moves most
    const step = 0.0008, shake = 0.0014 * Math.min(Math.abs(v), 1);
    X[i] = clamp(x - step * v * gx + rng.between(-shake, shake), 0, A);
    Y[i] = clamp(y - step * v * gy + rng.between(-shake, shake), 0, 1);
  }
  const sand = w.isDark ? p.foreground.mix(hues0(w), 0.15) : p.foreground;
  ctx.fillStyle = sand.css(w.isDark ? 0.5 : 0.45);
  const dot = Math.max(0.9, 1.3 / w.unit);
  for (let i = 0; i < grains; i++) ctx.fillRect(X[i] * H, Y[i] * H, dot, dot);
  // a few grains of accent, like coloured sand mixed in
  ctx.fillStyle = p.accent.css(0.85);
  for (let i = 0; i < grains; i += 19) ctx.fillRect(X[i] * H, Y[i] * H, dot * 1.4, dot * 1.4);
};
function hues0(w) { return w.harmony(1)[0]; }

// =====================================================================================
// COMPLEX — an enhanced phase portrait of a complex function (Elias Wegert's domain
// coloring): the argument of f(z) goes once round a palette ring, log|f| adds shaded bands,
// and faint isochromatic lines mark the phase. Zeros and poles become pinwheels.
// gart: arts/z/src/z (Z1–Z11).
// =====================================================================================
const Cx = {
  mul: (a, b) => [a[0] * b[0] - a[1] * b[1], a[0] * b[1] + a[1] * b[0]],
  div: (a, b) => { const d = b[0] * b[0] + b[1] * b[1] || 1e-12; return [(a[0] * b[0] + a[1] * b[1]) / d, (a[1] * b[0] - a[0] * b[1]) / d]; },
  add: (a, b) => [a[0] + b[0], a[1] + b[1]],
  sin: a => [Math.sin(a[0]) * Math.cosh(a[1]), Math.cos(a[0]) * Math.sinh(a[1])],
  pow: (a, k) => { let r = [1, 0]; for (let i = 0; i < k; i++) r = Cx.mul(r, a); return r; },
};
STYLES.complex = function paintComplex(w) {
  const rng = w.rng, p = w.palette, W = w.width, H = w.height;
  const fns = [
    { name: 'rational', f: z => Cx.div(Cx.mul(Cx.add(Cx.mul(z, z), [-1, 0]), Cx.pow(Cx.add(z, [-2, -1]), 2)), Cx.add(Cx.mul(z, z), [2, 2])), span: 3.2 },
    { name: 'sinc', f: z => Cx.div(Cx.sin(z), z), span: 9 },
    { name: 'roots', f: z => Cx.div(Cx.add(Cx.pow(z, 5), [-1, 0]), Cx.add(Cx.mul(z, z), [0.4, 0.3])), span: 2.4 },
  ];
  const fn = w.complexFn ? fns.find(x => x.name === w.complexFn) : rng.pick(fns);
  const S = H / fn.span, cxo = rng.between(-0.3, 0.3) * fn.span, cyo = rng.between(-0.2, 0.2) * fn.span;
  const hues = w.harmony(4);
  const ringC = w.isDark
    ? [hues[0], w.muted(hues[1] || hues[0], 0.2), w.muted(hues[2] || hues[0], 0.35), w.muted(hues[3] || hues[0], 0.2)]
    : [hues[0].mix(p.background, 0.2), (hues[1] || hues[0]).mix(p.background, 0.35), (hues[2] || hues[0]).mix(p.background, 0.5), (hues[3] || hues[0]).mix(p.background, 0.35)];
  const ring = t => { t = ((t % 1) + 1) % 1; const s = t * ringC.length, i = Math.floor(s); return ringC[i].mix(ringC[(i + 1) % ringC.length], smoothstep(0, 1, s - i)); };
  const lut = Array.from({ length: 512 }, (_, i) => ring(i / 512).rgb8);
  const dark = w.base.rgb8;
  const img = w.ctx.createImageData(W, H), data = img.data;
  for (let py = 0; py < H; py++) for (let px = 0; px < W; px++) {
    const z = [(px + 0.5 - W / 2) / S + cxo, (H / 2 - py - 0.5) / S + cyo];
    const v = fn.f(z), mod = Math.hypot(v[0], v[1]), arg = Math.atan2(v[1], v[0]);
    const t = arg / (Math.PI * 2) + 0.5;
    const band = ((Math.log2(mod + 1e-12) % 1) + 1) % 1;       // modulus bands: a soft sawtooth
    const iso = ((t * 12) % 1);                                  // twelve isochromatic lines
    let shade = 0.72 + 0.28 * smoothstep(0, 0.92, band) - 0.28 * smoothstep(0.92, 1, band);
    shade *= 1 - 0.08 * (1 - smoothstep(0, 0.06, iso)) * (1 - smoothstep(0.94, 1, iso) * 0);
    const c = lut[Math.floor(t * 511)], o = (py * W + px) * 4;
    for (let ch = 0; ch < 3; ch++) data[o + ch] = lerp(dark[ch], c[ch], w.isDark ? shade : 0.35 + 0.65 * shade);
    data[o + 3] = 255;
  }
  w.ctx.putImageData(img, 0, 0);
};
// =====================================================================================
// GROWTH — differential growth: a ring of nodes that pull on their neighbours, push away
// from everyone nearby and split where they stretch; noise feeds extra splits. Every few
// steps the ring is drawn again, so the picture is the growth itself, oldest to newest.
// gart: arts/cell/src/rugae/Rugae.kt (after Anders Hoff's differential-line).
// =====================================================================================
STYLES.growth = function paintGrowth(w) {
  w.enterUnitSpace();
  const rng = w.rng, p = w.palette, ctx = w.ctx, W = w.unitWidth, H = 1000, s = 1000 / 1200;
  const ITER = 950, EVERY = 5, MAXN = 9000;
  const SPLIT = 9 * s, RAD = 44 * s, ATTR = 0.45, REP = 1.2, MAXSTEP = 1.9 * s, MARGIN = 40 * s, NS = 0.0042 / s;
  const cx = W * rng.between(0.4, 0.6), cy = H * rng.between(0.45, 0.55);
  let xs = [], ys = [];
  for (let k = 0; k < 50; k++) { const a = k / 50 * Math.PI * 2, r = rng.between(46, 50) * s; xs.push(cx + Math.cos(a) * r * 1.6); ys.push(cy + Math.sin(a) * r); }
  const gc = Math.ceil(W / RAD), gr = Math.ceil(H / RAD);
  const nox = rng.between(0, 100);
  const snaps = [];
  for (let it = 0; it < ITER; it++) {
    const n = xs.length;
    const grid = Array.from({ length: gc * gr }, () => []);
    const cell = (x, y) => clamp(Math.floor(y / RAD), 0, gr - 1) * gc + clamp(Math.floor(x / RAD), 0, gc - 1);
    for (let i = 0; i < n; i++) grid[cell(xs[i], ys[i])].push(i);
    const fx = new Float32Array(n), fy = new Float32Array(n);
    for (let i = 0; i < n; i++) {
      const pi = (i - 1 + n) % n, ni = (i + 1) % n;
      fx[i] += ((xs[pi] + xs[ni]) / 2 - xs[i]) * ATTR; fy[i] += ((ys[pi] + ys[ni]) / 2 - ys[i]) * ATTR;
      const gx = clamp(Math.floor(xs[i] / RAD), 0, gc - 1), gy = clamp(Math.floor(ys[i] / RAD), 0, gr - 1);
      for (let yy = Math.max(gy - 1, 0); yy <= Math.min(gy + 1, gr - 1); yy++) for (let xx = Math.max(gx - 1, 0); xx <= Math.min(gx + 1, gc - 1); xx++)
        for (const j of grid[yy * gc + xx]) {
          if (j === i) continue;
          const dr = Math.abs(i - j), ring = Math.min(dr, n - dr);
          if (ring <= 2) continue;
          const dx = xs[i] - xs[j], dy = ys[i] - ys[j], d = Math.hypot(dx, dy);
          if (d < 0.001 || d >= RAD) continue;
          const f = REP * (1 - d / RAD) / d;
          fx[i] += dx * f; fy[i] += dy * f;
        }
      fx[i] += rng.between(-0.12, 0.12); fy[i] += rng.between(-0.12, 0.12);
      if (xs[i] < MARGIN) fx[i] += (MARGIN - xs[i]) * 0.05; if (xs[i] > W - MARGIN) fx[i] -= (xs[i] - (W - MARGIN)) * 0.05;
      if (ys[i] < MARGIN) fy[i] += (MARGIN - ys[i]) * 0.05; if (ys[i] > H - MARGIN) fy[i] -= (ys[i] - (H - MARGIN)) * 0.05;
    }
    for (let i = 0; i < n; i++) { const l = Math.hypot(fx[i], fy[i]), k = l > MAXSTEP ? MAXSTEP / l : 1; xs[i] += fx[i] * k; ys[i] += fy[i] * k; }
    // split stretched edges
    if (n < MAXN) {
      const nx = [], ny = [];
      for (let i = 0; i < n; i++) {
        nx.push(xs[i]); ny.push(ys[i]);
        const j = (i + 1) % n;
        if (nx.length + (n - i) < MAXN && Math.hypot(xs[j] - xs[i], ys[j] - ys[i]) > SPLIT) { nx.push((xs[i] + xs[j]) / 2 + rng.between(-0.3, 0.3)); ny.push((ys[i] + ys[j]) / 2 + rng.between(-0.3, 0.3)); }
      }
      xs = nx; ys = ny;
      // growth hormone: random edges split where the noise is rich
      const feed = new Set();
      for (let k = 0; k < Math.max(3, Math.floor(xs.length / 40)); k++) {
        const i = rng.int(xs.length), j = (i + 1) % xs.length;
        const food = w.noise.fractal((xs[i] + xs[j]) / 2 * NS + nox, (ys[i] + ys[j]) / 2 * NS, 2);
        if (rng.unit() < food * food * 1.6) feed.add(i);
      }
      if (feed.size && xs.length + feed.size <= MAXN) {
        const fx2 = [], fy2 = [], m = xs.length;
        for (let i = 0; i < m; i++) {
          fx2.push(xs[i]); fy2.push(ys[i]);
          if (feed.has(i)) { const j = (i + 1) % m; fx2.push((xs[i] + xs[j]) / 2 + rng.between(-0.3, 0.3)); fy2.push((ys[i] + ys[j]) / 2 + rng.between(-0.3, 0.3)); }
        }
        xs = fx2; ys = fy2;
      }
    }
    if (it % EVERY === 0) snaps.push([Float32Array.from(xs), Float32Array.from(ys)]);
  }
  snaps.push([Float32Array.from(xs), Float32Array.from(ys)]);
  // draw: each snapshot a closed line, the palette swept twice from oldest to newest
  w.fill(w.base);
  const hues = w.harmony(4);
  const sweep = rampOf(w.isDark
    ? [w.muted(hues[1] || hues[0], 0.45), hues[0], w.muted(hues[2] || hues[0], 0.1), hues[3] || hues[0], w.muted(hues[1] || hues[0], 0.45)]
    : [(hues[1] || hues[0]).mix(p.background, 0.5), hues[0], (hues[2] || hues[0]).mix(Color.black, 0.15), hues[3] || hues[0], (hues[1] || hues[0]).mix(p.background, 0.5)]);
  ctx.lineJoin = 'round'; ctx.lineCap = 'round';
  const last = snaps.length - 1;
  snaps.forEach(([sx, sy], k) => {
    const t = k / last;
    ctx.strokeStyle = sweep((t * 2) % 1).css(lerp(0.6, 1, t));
    ctx.lineWidth = lerp(1.0, 1.5, t);
    ctx.beginPath();
    for (let i = 0; i < sx.length; i++) i ? ctx.lineTo(sx[i], sy[i]) : ctx.moveTo(sx[i], sy[i]);
    ctx.closePath(); ctx.stroke();
  });
  ctx.strokeStyle = (w.isDark ? p.foreground : p.foreground).css(0.95); ctx.lineWidth = 1.7;
  ctx.beginPath(); const [lx, ly] = snaps[last];
  for (let i = 0; i < lx.length; i++) i ? ctx.lineTo(lx[i], ly[i]) : ctx.moveTo(lx[i], ly[i]);
  ctx.closePath(); ctx.stroke();
};

