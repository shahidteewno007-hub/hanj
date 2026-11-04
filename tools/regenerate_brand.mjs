// Hanj brand asset export for the Clean Cut mark (2026-11).
//
//   node tools/regenerate_brand.mjs           # write every file listed below
//   node tools/regenerate_brand.mjs --check   # write nothing; exit 1 if any file differs
//   dart run flutter_launcher_icons            # then the files the generator owns
//
// Renders the SVG masters in assets/icon/hanj_cut*.svg with the installed
// headless Chrome (or Edge; set CHROME to override) over the DevTools protocol,
// using Node's built-in WebSocket (Node 22+). No npm packages, nothing in
// pubspec. Each PNG is drawn at its exact pixel size on a transparent page,
// then written in place and listed with its sha256, so a rerun can be compared
// file by file.
//
// This writes the four flutter_launcher_icons inputs in assets/icon/ and
// everything the generator doesn't own. The generator then writes
// mipmap-*/ic_launcher.png, drawable-*/ic_launcher_{foreground,background,
// monochrome}.png, mipmap-anydpi-v26/ic_launcher.xml and the iOS AppIcon set,
// as it has since 2026-09-05 (49b84b8).
//
// The wing's masters (assets/icon/hanj_wing*.svg) and its exporters
// (tools/regenerate_*.py, Python + cairosvg) are left as they were, as its
// record.

import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { crc32, deflateSync } from 'node:zlib';

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const RES = 'android/app/src/main/res';
const CHECK = process.argv.includes('--check');

const SUMI = [0x12, 0x11, 0x10]; // #121110, Hanko's sumi: every tile and fill
const WHITE = '#FFFFFF';

// Android densities: adaptive layers (108 dp), legacy icons (48 dp) and the
// status-bar icon (24 dp).
const ADAPTIVE = [['mdpi', 108], ['hdpi', 162], ['xhdpi', 216], ['xxhdpi', 324], ['xxxhdpi', 432]];
const LEGACY = [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]];
const NOTIF = [['mdpi', 24], ['hdpi', 36], ['xhdpi', 48], ['xxhdpi', 72], ['xxxhdpi', 96]];

// The launcher shows the central 72 of an adaptive icon's 108 dp, so the
// foreground draws hanj_cut_icon.svg's 1024 tile at 2/3. The seal is then 39%
// of the layer and the flash's tips stop 32 dp from centre, inside the 33 dp
// safe zone: in the mask it looks as the icon master does.
const ADAPTIVE_SCALE = 2 / 3;
// Maskable PWA icons keep the wing's proportion, the seal at 46% of the
// image, which keeps the flash's tips at 35% radius, inside the 40% safe zone.
const MASKABLE_SCALE = (0.46 * 1024) / 600;
// The "any" PWA icons are rounded squares, radius 20%, as the wing's were.
const PWA_RADIUS = 0.2 * 1024;

// ── Masters ─────────────────────────────────────────────────────────────────

function paths(file) {
  const svg = readFileSync(join(ROOT, 'assets/icon', file), 'utf8');
  return [...svg.matchAll(/<path fill="([^"]+)" d="([^"]+)"\/>/g)].map(([, fill, d]) => ({ fill, d }));
}

const icon = paths('hanj_cut_icon.svg'); // tile, halves, flash on the 1024 grid
const mark = paths('hanj_cut.svg'); // halves, flash on the 24 grid
const small = paths('hanj_cut_small.svg'); // halves on the 16 grid, no flash
if (icon.length !== 3 || mark.length !== 2 || small.length !== 1) {
  throw new Error('A master in assets/icon/ no longer has the expected paths.');
}
const [tile, ...seal] = icon;

const draw = (ps, fill) => ps.map((p) => `<path fill="${fill ?? p.fill}" d="${p.d}"/>`).join('');
const about = (s, body, c = 512) =>
  `<g transform="translate(${c} ${c}) scale(${s}) translate(${-c} ${-c})">${body}</g>`;
const svg = (grid, size, body) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${grid} ${grid}" width="${size}" height="${size}">${body}</svg>`;

const iconSvg = (size) => svg(1024, size, draw(icon));
const foregroundSvg = (size) => svg(1024, size, about(ADAPTIVE_SCALE, draw(seal)));
const monochromeSvg = (size) => svg(1024, size, about(ADAPTIVE_SCALE, draw(seal, WHITE)));
const roundSvg = (size) => svg(1024, size,
  `<clipPath id="m"><circle cx="512" cy="512" r="512"/></clipPath><g clip-path="url(#m)">${draw(icon)}</g>`);
const pwaSvg = (size) => svg(1024, size,
  `<clipPath id="m"><rect width="1024" height="1024" rx="${PWA_RADIUS}"/></clipPath><g clip-path="url(#m)">${draw(icon)}</g>`);
const maskableSvg = (size) => svg(1024, size, draw([tile]) + about(MASKABLE_SCALE, draw(seal)));
// The status-bar icon: the small cut as a white silhouette in the 20 dp live
// area of a 24 dp icon. At xxxhdpi that is 5 px a unit, so the cut's edges
// land on whole pixels.
const notificationSvg = (size) => svg(24, size, `<g transform="translate(2 2) scale(1.25)">${draw(small, WHITE)}</g>`);
const markSvg = (size) => svg(24, size, draw(mark));
const smallSvg = (size) => svg(16, size, draw(small));

// ── Output list ─────────────────────────────────────────────────────────────

const jobs = [
  // flutter_launcher_icons inputs (pubspec.yaml)
  ['assets/icon/app_icon_1024.png', () => render(iconSvg(1024), 1024)],
  ['assets/icon/ic_launcher_foreground.png', () => render(foregroundSvg(1024), 1024)],
  ['assets/icon/ic_launcher_background.png', () => solidPng(1024, 1024, SUMI, true)],
  ['assets/icon/ic_launcher_monochrome.png', () => render(monochromeSvg(1024), 1024)],
  // Android files the generator doesn't write. The mipmap foreground,
  // background and round icons are packaged but nothing loads them
  // (ic_launcher_round.xml's comment says why); they're kept current so no
  // old mark is left in the APK.
  ...ADAPTIVE.map(([d, px]) => [`${RES}/mipmap-${d}/ic_launcher_foreground.png`, () => render(foregroundSvg(px), px)]),
  ...LEGACY.map(([d, px]) => [`${RES}/mipmap-${d}/ic_launcher_background.png`, () => solidPng(px, px, SUMI, false)]),
  ...LEGACY.map(([d, px]) => [`${RES}/mipmap-${d}/ic_launcher_round.png`, () => render(roundSvg(px), px)]),
  ...NOTIF.map(([d, px]) => [`${RES}/drawable-${d}/ic_notification.png`, () => render(notificationSvg(px), px)]),
  // The Android 7-11 splash (launch_background.xml): a plain sumi fill.
  [`${RES}/drawable/background.png`, () => solidPng(1, 1, SUMI, false)],
  [`${RES}/drawable-v21/background.png`, () => solidPng(1, 1, SUMI, false)],
  // Web
  ['web/favicon.svg', () => readFileSync(join(ROOT, 'assets/icon/hanj_cut_icon_small.svg'))],
  ['web/icons/Icon-192.png', () => render(pwaSvg(192), 192)],
  ['web/icons/Icon-512.png', () => render(pwaSvg(512), 512)],
  ['web/icons/Icon-maskable-192.png', () => render(maskableSvg(192), 192)],
  ['web/icons/Icon-maskable-512.png', () => render(maskableSvg(512), 512)],
  // Web push badge: Android Chrome keeps only its alpha.
  ['web/icons/badge-96.png', () => render(notificationSvg(96), 96)],
  // In-app (pubspec.yaml assets): the full cut for 48 px and up, the small
  // cut for 24 px and below (MARK-SIZES.md).
  ...[['', 96], ['2.0x/', 192], ['3.0x/', 288]].flatMap(([dir, px]) => [
    [`assets/images/${dir}hanj_cut.png`, () => render(markSvg(px), px)],
    [`assets/images/${dir}hanj_cut_small.png`, () => render(smallSvg(px), px)],
  ]),
];

// ── Headless Chrome over the DevTools protocol ──────────────────────────────

const BROWSERS = [
  process.env.CHROME,
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Google/Chrome/Application/chrome.exe',
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/usr/bin/google-chrome',
  '/usr/bin/chromium',
].filter(Boolean);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let send;
let frameId;

async function launch() {
  const exe = BROWSERS.find((p) => existsSync(p));
  if (!exe) throw new Error('No Chrome or Edge found; set CHROME to its path.');
  const profile = mkdtempSync(join(tmpdir(), 'hanj-brand-'));
  const proc = spawn(exe, [
    '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check',
    '--disable-extensions', '--hide-scrollbars', '--force-color-profile=srgb',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank',
  ], { stdio: 'ignore' });

  // Chrome writes its port to DevToolsActivePort once it's listening.
  const portFile = join(profile, 'DevToolsActivePort');
  let port;
  for (let i = 0; i < 300 && !port; i++) {
    await sleep(50);
    if (existsSync(portFile)) port = readFileSync(portFile, 'utf8').split('\n')[0].trim();
  }
  if (!port) throw new Error('Chrome did not start its DevTools endpoint.');
  const targets = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
  const ws = new WebSocket(targets.find((t) => t.type === 'page').webSocketDebuggerUrl);
  await new Promise((ok, fail) => { ws.onopen = ok; ws.onerror = fail; });

  let nextId = 0;
  const pending = new Map();
  ws.onmessage = (e) => {
    const m = JSON.parse(e.data);
    const p = pending.get(m.id);
    if (!p) return;
    pending.delete(m.id);
    if (m.error) p.fail(new Error(`${p.method}: ${m.error.message}`));
    else p.ok(m.result);
  };
  send = (method, params = {}) => new Promise((ok, fail) => {
    const id = ++nextId;
    pending.set(id, { ok, fail, method });
    ws.send(JSON.stringify({ id, method, params }));
  });

  await send('Emulation.setDefaultBackgroundColorOverride', { color: { r: 0, g: 0, b: 0, a: 0 } });
  frameId = (await send('Page.getFrameTree')).frameTree.frame.id;

  return () => {
    ws.close();
    proc.kill();
    try { rmSync(profile, { recursive: true, force: true, maxRetries: 10, retryDelay: 200 }); } catch {}
  };
}

async function render(markup, w, h = w) {
  await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false });
  await send('Page.setDocumentContent', {
    frameId,
    html: `<!doctype html><style>html,body{margin:0;background:transparent;overflow:hidden}svg{display:block}</style>${markup}`,
  });
  // Two frames, so the new content has been painted before the capture.
  await send('Runtime.evaluate', {
    expression: 'new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r)))',
    awaitPromise: true,
  });
  const { data } = await send('Page.captureScreenshot', {
    format: 'png', clip: { x: 0, y: 0, width: w, height: h, scale: 1 }, captureBeyondViewport: false,
  });
  return Buffer.from(data, 'base64');
}

// A solid colour needs no rasteriser: write the PNG directly.
function solidPng(w, h, [r, g, b], alpha) {
  const ch = alpha ? 4 : 3;
  const row = Buffer.alloc(1 + w * ch); // filter byte 0, then the pixels
  for (let x = 0; x < w; x++) row.set(alpha ? [r, g, b, 255] : [r, g, b], 1 + x * ch);
  const chunk = (type, data) => {
    const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
    const out = Buffer.alloc(body.length + 8);
    out.writeUInt32BE(data.length, 0);
    body.copy(out, 4);
    out.writeUInt32BE(crc32(body), body.length + 4);
    return out;
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = alpha ? 6 : 2; // RGBA or RGB
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(Buffer.concat(Array(h).fill(row)), { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Run ─────────────────────────────────────────────────────────────────────

const close = await launch();
let differs = 0;
try {
  for (const [rel, make] of jobs) {
    const bytes = await make();
    const sha = createHash('sha256').update(bytes).digest('hex');
    const file = join(ROOT, rel);
    const same = existsSync(file) && createHash('sha256').update(readFileSync(file)).digest('hex') === sha;
    if (!same) differs++;
    if (!CHECK && !same) {
      mkdirSync(dirname(file), { recursive: true });
      writeFileSync(file, bytes);
    }
    console.log(`${sha.slice(0, 16)}  ${same ? 'same   ' : CHECK ? 'DIFFERS' : 'written'}  ${rel}`);
  }
} finally {
  close();
}
console.log(`\n${jobs.length} files, ${differs} ${CHECK ? 'differ' : 'written'}.`);
if (!CHECK) console.log('Next: dart run flutter_launcher_icons');
if (CHECK && differs) process.exit(1);
