import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { POINT_COUNT, VOICE, WOBBLE } from "./orb-geometry.mjs";
import { LAYERS, MOTION, TINTS } from "./orb-tokens.mjs";

const root = join(import.meta.dirname, "..");
const read = (path) => readFileSync(join(root, path), "utf8");
// DesignTokenTests writes this from the Swift constants with WRITE_DESIGN_TOKENS=1.
const tokens = JSON.parse(read("Packages/Tests/DesignTests/Fixtures/design-tokens.json"));

// --amber is Palette.accent: the orb's amber in the dark, deeper on the paper.
const CSS_TOKENS = {
  "--sky": "sky",
  "--raised": "skyRaised",
  "--ink": "ink",
  "--dim": "inkDim",
  "--amber": "accent",
};

function parseColor(value) {
  const hex = value.match(/^#([0-9a-f]{6})$/);
  if (hex) {
    const rgb = [0, 2, 4].map((i) => parseInt(hex[1].slice(i, i + 2), 16));
    return { rgb, alpha: 1 };
  }
  const rgba = value.match(/^rgba\((\d+), (\d+), (\d+), ([\d.]+)\)$/);
  assert.ok(rgba, value);
  return { rgb: rgba.slice(1, 4).map(Number), alpha: Number(rgba[4]) };
}

function declared(block) {
  const out = {};
  for (const [, name, value] of block.matchAll(/(--[a-z]+): ([^;]+);/g))
    if (name in CSS_TOKENS) out[CSS_TOKENS[name]] = parseColor(value);
  return out;
}

test("the blob geometry matches the Swift orb", () => {
  assert.deepEqual({ pointCount: POINT_COUNT, wobble: WOBBLE, voice: VOICE }, tokens.geometry);
});

test("the eight tints with their glow, blend, sheen, and rim start match", () => {
  assert.deepEqual(TINTS, tokens.tints);
});

test("the layer radii and gradient stops match", () => {
  assert.deepEqual(LAYERS, tokens.layers);
});

test("the motion taus and the resting and still poses match", () => {
  assert.deepEqual(MOTION, tokens.motion);
});

test("the orb's amber is the palette's", () => {
  for (const scheme of ["dark", "light"])
    assert.deepEqual(TINTS[scheme].amber, tokens.palette[scheme].amber.rgb);
});

test("site.css declares the palette once per scheme and matches Palette.swift", () => {
  const css = read("site/site.css");
  const roots = [...css.matchAll(/:root \{([^}]*)\}/g)];
  assert.equal(roots.length, 2);
  assert.ok(css.indexOf("@media (prefers-color-scheme: light)") < roots[1].index);
  const expected = (scheme) =>
    Object.fromEntries(
      Object.values(CSS_TOKENS).map((name) => [name, tokens.palette[scheme][name]]),
    );
  assert.deepEqual(declared(roots[0][1]), expected("dark"));
  assert.deepEqual(declared(roots[1][1]), expected("light"));
});

test("no other stylesheet declares the tokens", () => {
  for (const path of ["tools/store/store.css", "tools/store/art.css", "tools/labeler/labeler.css"])
    assert.ok(!/--(sky|raised|ink|dim|amber):/.test(read(path)), path);
  assert.match(
    read("tools/labeler/index.html"),
    /<link rel="stylesheet" href="\.\.\/\.\.\/site\/site\.css" \/>/,
  );
});
