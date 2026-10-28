import { blobPath } from "./orb-geometry.mjs";
import { JOURNEY, LAYERS, MOTION, PHASES, TINTS } from "./orb-tokens.mjs";

// The App Store Connect record does not exist yet; the placeholder becomes a link when this holds the URL.
const APP_STORE_URL = "";

const store = document.querySelector(".store");
if (APP_STORE_URL) {
  const link = document.createElement("a");
  link.className = store.className;
  link.href = APP_STORE_URL;
  link.textContent = "Download on the App Store";
  store.replaceWith(link);
}

const rgba = ([r, g, b], a) => `rgba(${r}, ${g}, ${b}, ${a})`;
const WHITE = [255, 255, 255];

// Fraction of the orb's side the canvas extends past its box on each edge; site.css sizes it to match.
const OVERFLOW = 0.25;
// Pixels per CSS pixel for the blurred layers; the blur hides the upscale.
const SOFT_SCALE = 0.5;
// The grain disc is built for the resting radius and scaled to the live one, so it covers the widest body.
const GRAIN_REACH = 1.2;

function onMedia(query, handler) {
  const list = matchMedia(query);
  if (list.addEventListener) list.addEventListener("change", handler);
  else if (list.addListener) list.addListener(handler);
  return list;
}

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

const clamp01 = (v) => Math.min(Math.max(v, 0), 1);
const ease = (t) => t * t * (3 - 2 * t);
const lerp = (a, b, t) => a + (b - a) * t;

class Orb {
  constructor(canvas) {
    this.canvas = canvas;
    this.phase = null;
    this.pulse = 0;
    this.ctx = canvas.getContext("2d");
    this.blurred = document.createElement("canvas");
    this.grain = document.createElement("canvas");
    this.grainPattern = this.ctx.createPattern(grainTile(), "repeat");
    this.size = 0;
    this.margin = 0;
    this.dpr = 1;
    this.clock = 0;
    this.breath = 0;
    this.pose = Object.assign({}, MOTION.resting);
    this.level = 0;
    this.pointer = null;
    this.lastScroll = window.scrollY;
    this.last = 0;
    this.raf = 0;
    this.visible = true;
    this.filters = "filter" in this.ctx;
    const dark = onMedia("(prefers-color-scheme: dark)", (e) => {
      this.tint = TINTS[e.matches ? "dark" : "light"];
      if (this.reduced) this.drawStill();
    });
    this.tint = TINTS[dark.matches ? "dark" : "light"];
    this.reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    if ("ResizeObserver" in window) {
      new ResizeObserver(() => this.resize()).observe(canvas);
    } else {
      window.addEventListener("resize", () => this.resize());
    }
    this.resize();
    if (this.reduced) return;
    this.bind();
    this.journey = new Journey(this);
    this.start();
  }

  resize() {
    const css = this.canvas.clientWidth;
    if (!css) return;
    this.size = css / (1 + 2 * OVERFLOW);
    this.margin = this.size * OVERFLOW;
    this.dpr = Math.min(devicePixelRatio || 1, 3);
    const px = Math.round(css * this.dpr);
    this.canvas.width = this.canvas.height = px;
    this.blurred.width = this.blurred.height = Math.ceil(css * SOFT_SCALE);
    this.buildGrain();
    if (this.reduced) this.drawStill();
  }

  buildGrain() {
    const r = this.size * LAYERS.body;
    const reach = r * GRAIN_REACH;
    const side = Math.ceil(2 * reach * this.dpr);
    this.grain.width = this.grain.height = side;
    const g = this.grain.getContext("2d");
    g.setTransform(this.dpr, 0, 0, this.dpr, side / 2, side / 2);
    g.fillStyle = this.grainPattern;
    g.fillRect(-reach, -reach, 2 * reach, 2 * reach);
    g.globalCompositeOperation = "destination-in";
    const fade = g.createRadialGradient(0, 0, 0, 0, 0, r * LAYERS.grain.end);
    for (const [at, alpha] of LAYERS.grainFade)
      fade.addColorStop(at, rgba(WHITE, alpha));
    g.fillStyle = fade;
    g.fillRect(-reach, -reach, 2 * reach, 2 * reach);
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
        if (this.journey) this.journey.scrolled();
      },
      { passive: true },
    );
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) this.stop();
      else this.start();
    });
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => {
        this.visible = entry.isIntersecting;
        if (this.visible) this.start();
        else this.stop();
      }).observe(this.canvas);
    }
  }

  start() {
    if (this.raf || document.hidden || !this.visible) return;
    this.last = 0;
    const tick = (now) => {
      this.raf = requestAnimationFrame(tick);
      // The route follows every frame where script drives it; only the painting holds to 60 a second.
      if (this.journey) this.journey.frame();
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
    const base = this.size * LAYERS.body;
    return Math.min(Math.max(1 - (dist - base) / (base * 2.6), 0), 1);
  }

  step(dt) {
    const level = this.measureLevel();
    const tau = level > this.breath ? MOTION.riseTau : MOTION.fallTau;
    this.breath += (level - this.breath) * (1 - Math.exp(-dt / tau));
    const k = 1 - Math.exp(-dt / MOTION.poseTau);
    const rest = this.phase ? PHASES[this.phase] : MOTION.resting;
    this.pulse += dt * 1.6;
    const swell = (rest.pulse || 0) * (0.5 + 0.5 * Math.sin(this.pulse));
    const target = {
      glow: rest.glow + swell + 0.55 * level,
      drift: rest.drift + 0.5 * level,
      speed: rest.speed + 0.4 * level,
    };
    for (const key of Object.keys(target))
      this.pose[key] += (target[key] - this.pose[key]) * k;
    this.clock += dt * this.pose.speed;
  }

  drawStill() {
    this.draw(0, 0.3, MOTION.still);
  }

  // Paints blurred fills at SOFT_SCALE and composites the square of half-side `reach` around the centre.
  soft(reach, paint, compose) {
    const { ctx, blurred, size, margin, dpr } = this;
    const c = size / 2;
    const half = Math.min(reach, c + margin);
    const x0 = c - half;
    const side = 2 * half;
    const s = blurred.getContext("2d");
    s.setTransform(SOFT_SCALE, 0, 0, SOFT_SCALE, margin * SOFT_SCALE, margin * SOFT_SCALE);
    s.clearRect(x0, x0, side, side);
    const blur = (radius) => {
      if (this.filters) s.filter = `blur(${(radius * SOFT_SCALE) / dpr}px)`;
    };
    paint(s, blur);
    if (this.filters) s.filter = "none";
    const sx = (x0 + margin) * SOFT_SCALE;
    const sw = side * SOFT_SCALE;
    ctx.save();
    if (compose) compose(ctx);
    ctx.drawImage(blurred, sx, sx, sw, sw, x0, x0, side, side);
    ctx.restore();
  }

  draw(clock, breath, pose) {
    const { ctx, tint, size, margin, dpr } = this;
    if (!size) return;
    ctx.setTransform(dpr, 0, 0, dpr, margin * dpr, margin * dpr);
    ctx.clearRect(-margin, -margin, size + 2 * margin, size + 2 * margin);
    const c = size / 2;
    const base = size * LAYERS.body * (1 + LAYERS.breathGrow * breath);
    const body = blobPath(ctx, c, c, {
      radius: base,
      clock,
      drift: pose.drift,
      breath,
    });
    const halo = blobPath(ctx, c, c, {
      radius: base * LAYERS.halo.radius,
      clock: clock * LAYERS.halo.clock,
      drift: pose.drift * LAYERS.halo.drift,
      breath: 0,
    });
    const under = blobPath(ctx, c, c, {
      radius: base * LAYERS.under.radius,
      clock,
      drift: pose.drift,
      breath,
    });

    const g = tint.glowAlpha * pose.glow;
    this.soft(base * 3.1, (s, blur) => {
      s.globalCompositeOperation = tint.glowBlend;
      blur(base * LAYERS.halo.blur);
      const haloFill = s.createRadialGradient(
        c,
        c,
        base * LAYERS.halo.start,
        c,
        c,
        base * LAYERS.halo.radius,
      );
      for (const [at, alpha] of LAYERS.haloStops)
        haloFill.addColorStop(at, rgba(tint.glow, alpha * g));
      s.fillStyle = haloFill;
      s.fill(halo);
      s.globalCompositeOperation = "source-over";
      blur(base * LAYERS.under.blur);
      const underFill = s.createRadialGradient(
        c,
        c,
        0,
        c,
        c,
        base * LAYERS.under.radius,
      );
      for (const [at, alpha] of LAYERS.underStops)
        underFill.addColorStop(at, rgba(tint.glow, alpha));
      s.fillStyle = underFill;
      s.fill(under);
    });

    const cx = c - base * LAYERS.core.x;
    const cy = c - base * LAYERS.core.y;
    const bodyFill = ctx.createRadialGradient(
      cx,
      cy,
      0,
      cx,
      cy,
      base * LAYERS.core.end,
    );
    bodyFill.addColorStop(0, rgba(tint.core, 1));
    bodyFill.addColorStop(LAYERS.core.warm, rgba(tint.warm, 1));
    bodyFill.addColorStop(tint.rimStart, rgba(tint.amber, 1));
    bodyFill.addColorStop(1, rgba(tint.rim, 1));
    ctx.fillStyle = bodyFill;
    ctx.fill(body);

    if (tint.sheen) {
      this.soft(
        base * GRAIN_REACH,
        (s, blur) => {
          const { sheen } = LAYERS;
          blur(base * sheen.blur);
          s.fillStyle = rgba(
            WHITE,
            (sheen.floor + sheen.glow * pose.glow) * tint.sheen,
          );
          s.beginPath();
          s.ellipse(
            cx,
            cy,
            base * sheen.width,
            base * sheen.height,
            0,
            0,
            Math.PI * 2,
          );
          s.fill();
        },
        (t) => t.clip(body),
      );
    }

    const reach = base * GRAIN_REACH;
    ctx.save();
    ctx.clip(body);
    ctx.globalCompositeOperation = "soft-light";
    ctx.globalAlpha = LAYERS.grain.alpha;
    ctx.drawImage(this.grain, c - reach, c - reach, 2 * reach, 2 * reach);
    ctx.restore();
  }
}

// Moves the one orb along the page: seated in the hero, pinned in the lane beside the points
// (or small under the top edge on a narrow screen), then down onto the screenshot's orb spot,
// where it stays. The route is a list of scroll positions with the orb's place at each; the
// browser plays it as a scroll-driven animation when it can, else script evaluates it per frame.
class Journey {
  constructor(orb) {
    this.orb = orb;
    this.carrier = orb.canvas.parentElement;
    this.seat = this.carrier.parentElement;
    this.copy = document.querySelector(".copy");
    this.strip = document.querySelector(".strip");
    this.lane = document.querySelector(".lane");
    this.points = [...document.querySelectorAll(".point")];
    this.shot = document.querySelector(".phone img");
    this.native = CSS.supports("animation-timeline: scroll()");
    this.generation = 0;
    // The travelling orb becomes the screenshot's own, so the screenshot starts without one.
    for (const el of document.querySelectorAll(".phone source, .phone img"))
      for (const attr of ["srcset", "src"])
        if (el.hasAttribute(attr))
          el.setAttribute(attr, el.getAttribute(attr).replace(/(session-\w+-\d+)\./g, "$1-bare."));
    if (this.native) document.head.append((this.sheet = document.createElement("style")));
    document.body.classList.add("travels");
    if (window.scrollY === 0) orb.canvas.classList.add("cue");
    // A phone's toolbar collapsing only changes the height; nothing in the layout follows that.
    window.addEventListener("resize", () => {
      if (document.documentElement.clientWidth !== this.width) this.layout();
    });
    if (document.fonts) document.fonts.ready.then(() => this.layout());
    this.layout();
  }

  scrolled() {
    this.orb.canvas.classList.remove("cue");
    this.follow();
  }

  frame() {
    this.follow();
    this.orb.phase = this.phaseAt();
  }

  // Lets the carrier loose once the hold is over, and takes it back when the page returns to the hero.
  // Loose, it is fixed exactly where the seat held it, so the route runs on without a visible seam.
  follow() {
    this.carrier.classList.toggle("loose", window.scrollY >= this.dissolve);
    if (!this.native) this.place();
  }

  // Pins the seat and the copy where they sit, measures the room the copy has to hold still, and lays the route.
  // Both are measured unstuck: a page that loads scrolled has already pushed them.
  layout() {
    const hero = this.seat.parentElement;
    const pinned = [this.seat, this.copy];
    for (const el of pinned) el.style.position = "static";
    const seatTop = this.seat.offsetTop;
    const copyTop = this.copy.offsetTop;
    for (const el of pinned) el.style.position = "";
    this.seat.style.top = `${seatTop}px`;
    this.copy.style.top = `${copyTop}px`;
    this.dissolve = hero.offsetHeight - copyTop - this.copy.offsetHeight;
    this.width = document.documentElement.clientWidth;
    this.route = this.plan(seatTop);
    const half = this.carrier.clientWidth / 2;
    const [start] = this.route.stops;
    this.carrier.style.left = `${start.x - half}px`;
    this.carrier.style.top = `${start.y - half}px`;
    if (this.native) this.write();
    this.follow();
  }

  // Where the orb rests once the hero has gone: the lane's centre, or the top corner when there is no lane.
  rest(side) {
    const { clientWidth: vw, clientHeight: vh } = document.documentElement;
    if (this.lane.offsetParent) {
      const { lane } = JOURNEY;
      const box = this.lane.getBoundingClientRect();
      return { ...lane, x: box.left + box.width / 2, y: vh * lane.at, k: lane.side / side };
    }
    const { top } = JOURNEY;
    const half = top.side / 2;
    return { ...top, x: vw - top.inset - half, y: top.inset + half, k: top.side / side };
  }

  // The route in viewport coordinates against the scroll position, each stop easing or running
  // straight into the next: hold on the seat, drift to the rest, hold, drop into the phone, then
  // ride the page with it.
  plan(seatTop) {
    const vh = document.documentElement.clientHeight;
    const scrolled = window.scrollY;
    const end = document.documentElement.scrollHeight - vh;
    const side = this.seat.clientWidth;
    const seat = this.seat.getBoundingClientRect();
    const start = { x: seat.left + seat.width / 2, y: seatTop + seat.height / 2, k: 1 };
    const rest = this.rest(side);
    const { phone } = JOURNEY;
    const shot = this.shot.getBoundingClientRect();
    const target = {
      x: shot.left + shot.width * phone.x,
      y: shot.top + scrolled + shot.height * phone.y,
      k: (shot.width * phone.radius) / (side * LAYERS.body),
    };
    const released = this.dissolve + vh * JOURNEY.drift;
    const landed = Math.min(Math.max(target.y - vh * rest.at, released + 2), end);
    const falling = Math.max(landed - vh * rest.reach, released + 1);
    const stop = (at, { x, y, k }, eased) => ({ at, x, y, k, eased });
    return {
      end,
      stops: [
        stop(0, start, false),
        stop(this.dissolve, start, true),
        stop(released, rest, false),
        stop(falling, rest, true),
        stop(landed, { x: target.x, y: target.y - landed, k: target.k }, false),
        stop(end, { x: target.x, y: target.y - end, k: target.k }, false),
      ],
    };
  }

  // Relative to the held position, which is where the carrier sits whether seated or loose.
  transform({ x, y, k }) {
    const [start] = this.route.stops;
    return `translate(${x - start.x}px, ${y - start.y}px) scale(${k})`;
  }

  // Lays the route down as keyframes on the root scroll timeline. Each layout gets a fresh name
  // so the browser restarts from the new frames rather than keeping the old ones.
  write() {
    const { end, stops } = this.route;
    const name = `route-${++this.generation}`;
    const pct = (at) => `${((100 * at) / end).toFixed(4)}%`;
    const easing = (stop) => (stop.eased ? "cubic-bezier(0.45, 0, 0.55, 1)" : "linear");
    const frames = stops.map(
      (s) => `${pct(s.at)} { transform: ${this.transform(s)}; animation-timing-function: ${easing(s)}; }`);
    const [, held, released, falling, landed] = stops;
    this.sheet.textContent = `
      @keyframes ${name} { ${frames.join(" ")} }
      @keyframes ${name}-copy { 0% { opacity: 1; } ${pct(held.at)} { opacity: 0; } 100% { opacity: 0; } }
      @keyframes ${name}-strip {
        ${pct(held.at)} { opacity: 0; } ${pct(released.at)} { opacity: 1; }
        ${pct(falling.at)} { opacity: 1; } ${pct(landed.at)} { opacity: 0; }
      }`;
    // The range is pinned in pixels: the page's own scroll range shrinks when a phone's toolbar
    // collapses, and percentages of it would slide every stop.
    for (const [el, suffix] of [[this.carrier, ""], [this.copy, "-copy"], [this.strip, "-strip"]]) {
      el.style.animation = `${name}${suffix} linear both`;
      el.style.animationTimeline = "scroll(root)";
      el.style.animationRange = `0px ${end}px`;
    }
  }

  // The script path: the same route, read at the current scroll position.
  place() {
    const { stops } = this.route;
    const s = window.scrollY;
    let i = 0;
    while (i < stops.length - 2 && s >= stops[i + 1].at) i++;
    const [a, b] = [stops[i], stops[i + 1]];
    const raw = clamp01((s - a.at) / Math.max(b.at - a.at, 1));
    const t = a.eased ? ease(raw) : raw;
    const here = { x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t), k: lerp(a.k, b.k, t) };
    this.carrier.style.transform = this.transform(here);
    const [, held, released, falling, landed] = stops;
    this.copy.style.opacity = 1 - clamp01(s / held.at);
    this.strip.style.opacity =
      clamp01((s - held.at) / (released.at - held.at)) * (1 - clamp01((s - falling.at) / (landed.at - falling.at)));
  }

  // The point whose block has reached the orb sets the pose; past the drop it is the question's.
  phaseAt() {
    const s = window.scrollY;
    const { stops } = this.route;
    const [, , , falling, landed] = stops;
    if (s >= (falling.at + landed.at) / 2) return "asking";
    const box = this.carrier.getBoundingClientRect();
    const y = box.top + box.height / 2;
    const names = Object.keys(PHASES);
    let current = null;
    this.points.forEach((point, i) => {
      if (point.getBoundingClientRect().top <= y) current = names[i];
    });
    return current;
  }
}

new Orb(document.querySelector(".orb"));
