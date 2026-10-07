// Renders prototypes to PNG with headless Chromium.
//   npm i playwright && npx playwright install chromium   (once, in a scratch folder is fine)
//   node render.mjs flow,lens tokyoNight,gruvbox,rosePineDawn 2560 1600 [variation]
import fs from 'fs';
import path from 'path';
import { chromium } from 'playwright';

const dir = path.dirname(new URL(import.meta.url).pathname);
const themes = JSON.parse(fs.readFileSync(path.join(dir, 'themes.json')));
const [styles, slugs] = [process.argv[2].split(','), process.argv[3].split(',')];
const [width, height, variation] = [+process.argv[4] || 2560, +process.argv[5] || 1600, +process.argv[6] || 0];
const out = path.join(dir, 'out');
fs.mkdirSync(out, { recursive: true });
const browser = await chromium.launch();
const page = await browser.newPage();
page.on('pageerror', e => console.log('pageerror:', e.message));
await page.goto('file://' + path.join(dir, 'index.html'));
for (const style of styles) for (const slug of slugs) {
  const r = await page.evaluate(([s, t, sl, w, h, v]) => window.render(s, t, sl, w, h, v), [style, themes[slug], slug, width, height, variation]);
  const file = path.join(out, `${style}-${slug}${variation ? '-v' + variation : ''}.png`);
  fs.writeFileSync(file, Buffer.from(r.png.split(',')[1], 'base64'));
  console.log(`${style} ${slug} ${r.ms} ms -> ${path.relative(dir, file)}`);
}
await browser.close();
