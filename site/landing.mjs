import { blobPath } from "./orb-geometry.mjs";

// The App Store Connect record does not exist yet; this becomes the real link when it does.
const APP_STORE_URL = "#";

const store = document.querySelector(".store");
store.href = APP_STORE_URL;
if (APP_STORE_URL !== "#") store.textContent = "Download on the App Store";

const TINTS = {
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

const rgba = ([r, g, b], a) => `rgba(${r}, ${g}, ${b}, ${a})`;

function grainTile() {
  const size = 160;
  const tile = document.createElement("canvas");
  tile.width = tile.height = size;
  const ctx = tile.getContext("2d");
  const image = ctx.createImageData(size, size);
  let state = 0x6f6f6f68;
  for (let i = 0; i < image.data.length; i += 4) {
    state ^= state << 13;
    state ^= state >>> 17;
    state ^= state << 5;
    const v = 72 + ((state >>> 0) % 112);
    image.data[i] = image.data[i + 1] = image.data[i + 2] = v;
    image.data[i + 3] = 255;
  }
  ctx.putImageData(image, 0, 0);
  return tile;
}

class Orb {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.layer = document.createElement("canvas");
    this.grain = this.ctx.createPattern(grainTile(), "repeat");
    this.size = 0;
    this.dpr = 1;
    this.clock = 0;
    this.breath = 0;
    this.pose = { glow: 0.45, drift: 0.5, speed: 0.6 };
    this.level = 0;
    this.pointer = null;
    this.lastScroll = window.scrollY;
    this.last = 0;
    this.raf = 0;
    this.filters = "filter" in this.ctx;
    const dark = matchMedia("(prefers-color-scheme: dark)");
    this.tint = TINTS[dark.matches ? "dark" : "light"];
    dark.addEventListener("change", (e) => {
      this.tint = TINTS[e.matches ? "dark" : "light"];
      if (this.reduced) this.drawStill();
    });
    this.reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    new ResizeObserver(() => this.resize()).observe(canvas);
    this.resize();
    if (this.reduced) {
      canvas.classList.add("still");
      return;
    }
    this.bind();
    this.start();
  }

  resize() {
    const css = this.canvas.clientWidth;
    if (!css) return;
    this.size = css;
    this.dpr = Math.min(devicePixelRatio || 1, 3);
    const px = Math.round(css * this.dpr);
    this.canvas.width = this.canvas.height = px;
    this.layer.width = this.layer.height = px;
    if (this.reduced) this.drawStill();
  }

  bind() {
    const move = (e) => {
      this.pointer = { x: e.clientX, y: e.clientY };
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerdown", move, { passive: true });
    window.addEventListener("pointerup", () => (this.pointer = null), {
      passive: true,
    });
    window.addEventListener("pointercancel", () => (this.pointer = null), {
      passive: true,
    });
    document.addEventListener("pointerleave", () => (this.pointer = null));
    window.addEventListener(
      "scroll",
      () => {
        const y = window.scrollY;
        this.clock += (y - this.lastScroll) * 0.004;
        this.lastScroll = y;
      },
      { passive: true },
    );
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) this.stop();
      else this.start();
    });
  }

  start() {
    if (this.raf || document.hidden) return;
    this.last = 0;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      if (now - this.last < 1000 / 60 - 2) return;
      const dt = this.last ? Math.min((now - this.last) / 1000, 0.1) : 0;
      this.last = now;
      this.step(dt);
      this.draw(this.clock, this.breath, this.pose);
    };
    this.raf = requestAnimationFrame(tick);
  }

  stop() {
    cancelAnimationFrame(this.raf);
    this.raf = 0;
  }

  measureLevel() {
    if (!this.pointer) return 0;
    const rect = this.canvas.getBoundingClientRect();
    const dx = this.pointer.x - (rect.left + rect.width / 2);
    const dy = this.pointer.y - (rect.top + rect.height / 2);
    const dist = Math.hypot(dx, dy);
    const base = rect.width * 0.26;
    return Math.min(Math.max(1 - (dist - base) / (base * 2.6), 0), 1);
  }

  step(dt) {
    const level = this.measureLevel();
    const tau = level > this.breath ? 0.12 : 0.45;
    this.breath += (level - this.breath) * (1 - Math.exp(-dt / tau));
    const k = 1 - Math.exp(-dt / 0.3);
    const target = {
      glow: 0.45 + 0.55 * level,
      drift: 0.5 + 0.5 * level,
      speed: 0.6 + 0.4 * level,
    };
    for (const key of Object.keys(target))
      this.pose[key] += (target[key] - this.pose[key]) * k;
    this.clock += dt * this.pose.speed;
  }

  drawStill() {
    this.draw(0, 0.3, { glow: 0.7, drift: 0.4, speed: 0 });
  }

  blur(ctx, radius) {
    if (this.filters) ctx.filter = `blur(${radius}px)`;
  }

  draw(clock, breath, pose) {
    const { ctx, tint, size, dpr } = this;
    if (!size) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, size, size);
    const c = size / 2;
    const base = size * 0.26 * (1 + 0.12 * breath);
    const body = blobPath(ctx, c, c, {
      radius: base,
      clock,
      drift: pose.drift,
      breath,
    });
    const halo = blobPath(ctx, c, c, {
      radius: base * 1.9,
      clock: clock * 0.7,
      drift: pose.drift * 0.5,
      breath: 0,
    });
    const under = blobPath(ctx, c, c, {
      radius: base * 1.14,
      clock,
      drift: pose.drift,
      breath,
    });

    ctx.save();
    ctx.globalCompositeOperation = tint.glowBlend;
    this.blur(ctx, base * 0.3);
    const g = tint.glowAlpha * pose.glow;
    const haloFill = ctx.createRadialGradient(
      c,
      c,
      base * 0.4,
      c,
      c,
      base * 1.9,
    );
    haloFill.addColorStop(0, rgba(tint.glow, g));
    haloFill.addColorStop(0.4, rgba(tint.glow, 0.45 * g));
    haloFill.addColorStop(0.75, rgba(tint.glow, 0.12 * g));
    haloFill.addColorStop(1, rgba(tint.glow, 0));
    ctx.fillStyle = haloFill;
    ctx.fill(halo);
    ctx.restore();

    ctx.save();
    this.blur(ctx, base * 0.12);
    const underFill = ctx.createRadialGradient(c, c, 0, c, c, base * 1.14);
    underFill.addColorStop(0, rgba(tint.glow, 0.55));
    underFill.addColorStop(0.8, rgba(tint.glow, 0.35));
    underFill.addColorStop(1, rgba(tint.glow, 0));
    ctx.fillStyle = underFill;
    ctx.fill(under);
    ctx.restore();

    const cx = c - base * 0.06;
    const cy = c - base * 0.08;
    const bodyFill = ctx.createRadialGradient(cx, cy, 0, cx, cy, base * 1.25);
    bodyFill.addColorStop(0, rgba(tint.core, 1));
    bodyFill.addColorStop(0.42, rgba(tint.warm, 1));
    bodyFill.addColorStop(tint.rimStart, rgba(tint.amber, 1));
    bodyFill.addColorStop(1, rgba(tint.rim, 1));
    ctx.fillStyle = bodyFill;
    ctx.fill(body);

    if (tint.sheen) {
      ctx.save();
      ctx.clip(body);
      this.blur(ctx, base * 0.22);
      ctx.fillStyle = `rgba(255, 255, 255, ${(0.1 + 0.15 * pose.glow) * tint.sheen})`;
      ctx.beginPath();
      ctx.ellipse(cx, cy, base * 0.4, base * 0.32, 0, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }

    const layer = this.layer.getContext("2d");
    layer.setTransform(dpr, 0, 0, dpr, 0, 0);
    layer.clearRect(0, 0, size, size);
    layer.fillStyle = this.grain;
    layer.fill(body);
    layer.globalCompositeOperation = "destination-in";
    const fade = layer.createRadialGradient(c, c, 0, c, c, base * 1.1);
    fade.addColorStop(0, "rgba(255, 255, 255, 0.05)");
    fade.addColorStop(0.55, "rgba(255, 255, 255, 0.35)");
    fade.addColorStop(1, "rgba(255, 255, 255, 1)");
    layer.fillStyle = fade;
    layer.fill(body);
    layer.globalCompositeOperation = "source-over";
    ctx.save();
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.globalCompositeOperation = "soft-light";
    ctx.globalAlpha = 0.12;
    ctx.drawImage(this.layer, 0, 0);
    ctx.restore();
  }
}

new Orb(document.querySelector(".orb"));
