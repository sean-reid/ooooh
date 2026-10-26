// Fixed per scheme rather than adaptive so the painter can mix them; OrbPainter.swift holds the same eight.
export const TINTS = {
  dark: {
    core: [255, 245, 219],
    warm: [255, 219, 143],
    amber: [250, 189, 88],
    rim: [237, 145, 43],
    glow: [250, 189, 88],
    glowAlpha: 0.5,
    glowBlend: "source-over",
    sheen: 1,
    rimStart: 0.78,
  },
  light: {
    core: [255, 242, 204],
    warm: [255, 209, 115],
    amber: [250, 189, 88],
    rim: [219, 120, 26],
    glow: [237, 168, 87],
    glowAlpha: 0.7,
    glowBlend: "multiply",
    sheen: 0,
    rimStart: 0.84,
  },
};

// Layer radii as multiples of the body radius, and gradient stops as [location, alpha] pairs.
export const LAYERS = {
  body: 0.26,
  breathGrow: 0.12,
  halo: { radius: 1.9, clock: 0.7, drift: 0.5, blur: 0.3, start: 0.4 },
  haloStops: [
    [0, 1],
    [0.4, 0.45],
    [0.75, 0.12],
    [1, 0],
  ],
  under: { radius: 1.14, blur: 0.12 },
  underStops: [
    [0, 0.55],
    [0.8, 0.35],
    [1, 0],
  ],
  core: { x: 0.06, y: 0.08, end: 1.25, warm: 0.42 },
  sheen: { blur: 0.22, width: 0.4, height: 0.32, floor: 0.1, glow: 0.15 },
  grain: { alpha: 0.12, end: 1.1 },
  grainFade: [
    [0, 0.05],
    [0.55, 0.35],
    [1, 1],
  ],
};

// Seconds for the breath to follow a louder level, a quieter one, and for the pose to follow;
// then the pose at rest and the one reduced motion draws.
export const MOTION = {
  riseTau: 0.12,
  fallTau: 0.45,
  poseTau: 0.3,
  resting: { glow: 0.45, drift: 0.5, speed: 0.6 },
  still: { glow: 0.7, drift: 0.4, speed: 0 },
};
