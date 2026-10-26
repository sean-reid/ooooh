export const POINT_COUNT = 48;

export function radiusAt(theta, { radius, clock, drift, breath }) {
  const wobble =
    drift *
    (0.055 * Math.sin(2 * theta + clock * 0.7) +
      0.04 * Math.sin(3 * theta - clock * 0.47 + 1.3) +
      0.025 * Math.sin(5 * theta + clock * 1.1 + 2.1));
  const voice = breath * 0.035 * Math.sin(4 * theta - clock * 2.3 + 0.7);
  return radius * (1 + wobble + voice);
}

export function blobPoints(params) {
  const sq = Math.sqrt(params.stretch === undefined ? 1 : params.stretch);
  const points = [];
  for (let i = 0; i < POINT_COUNT; i++) {
    const theta = (i / POINT_COUNT) * 2 * Math.PI;
    const r = radiusAt(theta, params);
    points.push([(Math.cos(theta) * r) / sq, Math.sin(theta) * r * sq]);
  }
  return points;
}

// Catmull-Rom through every point as cubic Beziers, each [c1x, c1y, c2x, c2y, x, y].
export function smoothClosed(points) {
  const n = points.length;
  const segments = [];
  for (let i = 0; i < n; i++) {
    const p0 = points[(i + n - 1) % n];
    const p1 = points[i];
    const p2 = points[(i + 1) % n];
    const p3 = points[(i + 2) % n];
    segments.push([
      p1[0] + (p2[0] - p0[0]) / 6,
      p1[1] + (p2[1] - p0[1]) / 6,
      p2[0] - (p3[0] - p1[0]) / 6,
      p2[1] - (p3[1] - p1[1]) / 6,
      p2[0],
      p2[1],
    ]);
  }
  return segments;
}

export function blobPath(ctx, cx, cy, params) {
  const points = blobPoints(params);
  const path = new Path2D();
  path.moveTo(cx + points[0][0], cy + points[0][1]);
  for (const [c1x, c1y, c2x, c2y, x, y] of smoothClosed(points)) {
    path.bezierCurveTo(cx + c1x, cy + c1y, cx + c2x, cy + c2y, cx + x, cy + y);
  }
  path.closePath();
  return path;
}
