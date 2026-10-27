// Renders every frame x locale from frames.html into out/<locale>/<id>.png, validates, prints the list.
// No product or layout decisions here: copy, crops and colours live in frames.data.js / frames.html.
// Usage (from this directory): npm install && node render.mjs
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import puppeteer from "puppeteer";
import { PNG } from "pngjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const repo = path.resolve(here, "../../..");
const outRoot = path.join(here, "out");
const tmpDir = path.join(here, ".tmp");
const pageURL = pathToFileURL(path.join(here, "frames.html")).href;
const allowedPrefix = pathToFileURL(repo).href + "/";

const sha = buf => createHash("sha256").update(buf).digest("hex");

/** Re-encode a Chrome PNG as 8-bit RGB (colour type 2); refuse any non-opaque pixel. */
function toRGB(buf, label) {
  const png = PNG.sync.read(buf);
  const d = png.data;
  for (let i = 3; i < d.length; i += 4) {
    if (d[i] !== 255) throw new Error(`${label}: transparent pixel at ${(i - 3) / 4}`);
  }
  return PNG.sync.write(png, { colorType: 2, inputHasAlpha: true, deflateLevel: 9, filterType: -1 });
}

/** Read the PNG header of a written file: exact size, 8-bit RGB (type 2), no tRNS chunk. */
function checkPNG(file, want) {
  const b = fs.readFileSync(file);
  const errs = [];
  if (b.readUInt32BE(0) !== 0x89504e47) return ["not a PNG"];
  const w = b.readUInt32BE(16), h = b.readUInt32BE(20), depth = b[24], type = b[25];
  if (w !== want.width || h !== want.height) errs.push(`size ${w}x${h}, expected ${want.width}x${want.height}`);
  if (depth !== 8 || type !== 2) errs.push(`bit depth ${depth} colour type ${type}, expected 8-bit RGB (2)`);
  for (let o = 8; o < b.length;) {
    const len = b.readUInt32BE(o), kind = b.toString("ascii", o + 4, o + 8);
    if (kind === "tRNS") errs.push("has tRNS (transparency) chunk");
    if (kind === "IEND") break;
    o += 12 + len;
  }
  return errs;
}

function atomicWrite(dest, buf) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.mkdirSync(tmpDir, { recursive: true });
  const tmp = path.join(tmpDir, `${path.basename(path.dirname(dest))}-${path.basename(dest)}`);
  fs.writeFileSync(tmp, buf);
  fs.renameSync(tmp, dest);
}

const browser = await puppeteer.launch({
  headless: "shell",
  args: ["--allow-file-access-from-files", "--force-color-profile=srgb", "--font-render-hinting=none",
    "--disable-lcd-text", "--hide-scrollbars", "--lang=sv-SE"],
});

/** Load frames.html with query, wait for readiness, return { png, checks, meta }. */
async function shoot(query, size) {
  const page = await browser.newPage();
  const errors = [];
  try {
    await page.setRequestInterception(true);
    page.on("request", req => {
      const url = req.url();
      if (url.startsWith(allowedPrefix) || url.startsWith("data:")) req.continue();
      else { errors.push(`blocked request ${url}`); req.abort(); }
    });
    page.on("requestfailed", req => { if (req.url().startsWith(allowedPrefix)) errors.push(`missing asset ${req.url()}`); });
    page.on("console", msg => { if (msg.type() === "error" || msg.type() === "warn") errors.push(`console ${msg.type()}: ${msg.text()}`); });
    page.on("pageerror", err => errors.push(`page error: ${err.message}`));
    await page.emulateTimezone("Europe/Stockholm");
    await page.emulateMediaFeatures([
      { name: "prefers-color-scheme", value: "light" },
      { name: "prefers-reduced-motion", value: "reduce" },
    ]);
    await page.setViewport({ width: size.width, height: size.height, deviceScaleFactor: 1 });
    await page.goto(`${pageURL}?${query}`, { waitUntil: "networkidle0" });
    await page.waitForFunction(() => window.__SCREENSHOT_READY__ === true, { timeout: 30000 });
    const checks = await page.evaluate(() => window.__CHECKS__);
    const meta = await page.evaluate(() => ({ gallery: window.__GALLERY__, frames: window.__FRAMES__, contact: window.__CONTACT_SIZE__ || null }));
    if (meta.contact) await page.setViewport({ width: meta.contact.width, height: meta.contact.height, deviceScaleFactor: 1 });
    const el = await page.$(".frame");
    const raw = await el.screenshot({ type: "png", omitBackground: false });
    return { png: Buffer.from(raw), checks: [...errors, ...checks], meta };
  } finally {
    await page.close();
  }
}

const failures = [];
const written = [];
const manifest = {
  tools: { node: process.version, puppeteer: JSON.parse(fs.readFileSync(path.join(here, "node_modules/puppeteer/package.json"), "utf8")).version, browser: await browser.version() },
  canvas: null, frameOrder: [], inputs: {}, outputs: {}, contactSheets: {},
};

try {
  const probe = await shoot("locale=sv&frame=01", { width: 1320, height: 2868 });
  const { gallery, frames } = probe.meta;
  const canvas = { width: gallery.canvas.width, height: gallery.canvas.height };
  manifest.canvas = canvas;
  manifest.frameOrder = frames.map(f => f.id);

  for (const locale of gallery.locales) {
    const outDir = path.join(outRoot, locale);
    const expected = new Set(frames.map(f => `${f.id}.png`));
    if (fs.existsSync(outDir)) for (const name of fs.readdirSync(outDir)) if (!expected.has(name)) fs.rmSync(path.join(outDir, name));
    const capDir = path.join(here, "captures", locale);
    for (const name of fs.existsSync(capDir) ? fs.readdirSync(capDir).sort() : []) {
      manifest.inputs[`captures/${locale}/${name}`] = sha(fs.readFileSync(path.join(capDir, name)));
    }

    for (const f of frames) {
      const label = `${locale}/${f.id}`;
      const q = `locale=${encodeURIComponent(locale)}&frame=${encodeURIComponent(f.id)}`;
      const a = await shoot(q, canvas);
      const b = await shoot(q, canvas);
      failures.push(...a.checks.map(c => `${label}: ${c}`));
      const rgbA = toRGB(a.png, label), rgbB = toRGB(b.png, label);
      const hash = sha(rgbA);
      if (hash !== sha(rgbB)) failures.push(`${label}: nondeterministic render (two fresh pages differ)`);
      const rel = `out/${locale}/${f.id}.png`;
      atomicWrite(path.join(here, rel), rgbA);
      failures.push(...checkPNG(path.join(here, rel), canvas).map(e => `${rel}: ${e}`));
      manifest.outputs[rel] = { sha256: hash, screen: f.screen, headline: f.headline[locale], subline: f.subline?.[locale] ?? null };
      written.push(rel);
    }

    const contact = await shoot(`locale=${encodeURIComponent(locale)}&contact=1`, canvas);
    failures.push(...contact.checks.map(c => `contact ${locale}: ${c}`));
    const rel = `out/contact-${locale}.png`;
    const rgb = toRGB(contact.png, rel);
    atomicWrite(path.join(here, rel), rgb);
    manifest.contactSheets[rel] = sha(rgb);
  }
} finally {
  await browser.close();
  fs.rmSync(tmpDir, { recursive: true, force: true });
}

manifest.renderFailures = failures;
fs.mkdirSync(outRoot, { recursive: true });
fs.writeFileSync(path.join(outRoot, "manifest.json"), JSON.stringify(manifest, null, 2) + "\n");

for (const rel of written) {
  const o = manifest.outputs[rel];
  console.log(`${rel}  ${manifest.canvas.width}x${manifest.canvas.height} RGB no-alpha  ${o.sha256.slice(0, 12)}  "${o.headline}"`);
}
if (failures.length) {
  console.error(`\n${failures.length} failure(s):`);
  for (const f of failures) console.error(`  ${f}`);
  process.exit(1);
}
console.log(`\nOK: ${written.length} frames validated (exactly ${manifest.canvas.width}x${manifest.canvas.height}, 8-bit RGB, no alpha, deterministic).`);
