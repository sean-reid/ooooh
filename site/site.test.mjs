import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import {
  POINT_COUNT,
  blobPoints,
  radiusAt,
  smoothClosed,
} from "./orb-geometry.mjs";

const here = import.meta.dirname;
const pages = ["index.html", "privacy.html", "terms.html"];
const read = (name) => readFileSync(join(here, name), "utf8");
const count = (html, re) => (html.match(re) ?? []).length;
const leftovers = ["lorem", "TODO", String.fromCodePoint(0x2014)];

for (const name of pages) {
  test(`${name} exists with one h1 and no leftovers`, () => {
    assert.ok(existsSync(join(here, name)));
    const html = read(name);
    assert.equal(count(html, /<h1[\s>]/g), 1);
    for (const bad of leftovers) assert.ok(!html.includes(bad), `found ${bad}`);
    assert.ok(/<link rel="stylesheet" href="site.css"/.test(html));
  });
}

for (const name of ["privacy.html", "terms.html"]) {
  test(`${name} carries a last-updated date and a way back`, () => {
    const html = read(name);
    assert.match(html, /Last updated <time datetime="\d{4}-\d{2}-\d{2}">/);
    assert.match(html, /<a class="back" href="\.\/">/);
  });
}

test("the privacy page names each provider", () => {
  const html = read("privacy.html");
  for (const provider of ["TypeSafe", "Anthropic", "ElevenLabs"])
    assert.ok(html.includes(provider), provider);
});

test("the landing page links the documents from the footer and carries the store constant", () => {
  const html = read("index.html");
  const footer = html.slice(html.indexOf("<footer"), html.indexOf("</footer>"));
  assert.match(footer, /href="privacy.html"/);
  assert.match(footer, /href="terms.html"/);
  assert.match(html, /<canvas\s+class="orb"/);
  assert.match(read("landing.mjs"), /^const APP_STORE_URL = "[^"]+";$/m);
  for (const image of ["session-dark.png", "session-light.png"]) {
    assert.ok(existsSync(join(here, "images", image)), image);
    assert.ok(html.includes(`images/${image}`), image);
  }
});

test("the blob stays within its wobble band", () => {
  const params = { radius: 100, clock: 3.7, drift: 1, breath: 1 };
  const band = 100 * (0.055 + 0.04 + 0.025 + 0.035);
  for (let i = 0; i < 360; i++) {
    const r = radiusAt((i / 360) * Math.PI * 2, params);
    assert.ok(Math.abs(r - 100) <= band + 1e-9, `theta ${i}: ${r}`);
  }
  const still = blobPoints({ radius: 100, clock: 9, drift: 0, breath: 0 });
  for (const [x, y] of still)
    assert.ok(Math.abs(Math.hypot(x, y) - 100) < 1e-9);
});

test("stretch squeezes x and extends y", () => {
  const points = blobPoints({
    radius: 100,
    clock: 0,
    drift: 0,
    breath: 0,
    stretch: 1.18,
  });
  const xs = points.map(([x]) => Math.abs(x));
  const ys = points.map(([, y]) => Math.abs(y));
  assert.ok(Math.max(...xs) < 100 && Math.max(...ys) > 100);
});

test("the Catmull-Rom path is closed and passes through every point", () => {
  const points = blobPoints({
    radius: 80,
    clock: 1.2,
    drift: 0.8,
    breath: 0.4,
  });
  assert.equal(points.length, POINT_COUNT);
  const segments = smoothClosed(points);
  assert.equal(segments.length, POINT_COUNT);
  segments.forEach((segment, i) => {
    const [, , , , x, y] = segment;
    const next = points[(i + 1) % POINT_COUNT];
    assert.deepEqual([x, y], next);
    assert.ok(segment.every(Number.isFinite));
  });
  const [, , , , lastX, lastY] = segments.at(-1);
  assert.deepEqual([lastX, lastY], points[0]);
});

test("every page declares the favicon, touch icon, and manifest, and the files exist", () => {
  for (const page of ["index.html", "privacy.html", "terms.html"]) {
    const html = readFileSync(join(here, page), "utf8");
    assert.match(html, /rel="icon"[^>]*href="images\/icon-32.png"/);
    assert.match(
      html,
      /rel="apple-touch-icon"[^>]*href="images\/icon-180.png"/,
    );
    assert.match(html, /rel="manifest" href="site.webmanifest"/);
  }
  for (const file of [
    "images/icon-32.png",
    "images/icon-180.png",
    "images/icon-512.png",
    "site.webmanifest",
  ]) {
    assert.ok(existsSync(join(here, file)), file);
  }
});

test("every page carries Open Graph and Twitter tags and the card is 1200 by 630", () => {
  for (const page of ["index.html", "privacy.html", "terms.html"]) {
    const html = readFileSync(join(here, page), "utf8");
    assert.match(html, /property="og:title"/);
    assert.match(html, /property="og:image" content="https:\/\/ooooh.app\/images\/og.png"/);
    assert.match(html, /name="twitter:card" content="summary_large_image"/);
  }
  const png = readFileSync(join(here, "images/og.png"));
  assert.equal(png.readUInt32BE(16), 1200);
  assert.equal(png.readUInt32BE(20), 630);
});
