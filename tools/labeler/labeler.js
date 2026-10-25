import { parseCAF } from "./caf.mjs";
import {
  CLEAR_KEY,
  KINDS,
  buildLabels,
  countByKind,
  finalSegments,
  fixtureBaseName,
  kindForKey,
  labelsFromFile,
} from "./labels.mjs";

const transcriptEl = document.getElementById("transcript");
const statusEl = document.getElementById("status");
const clockEl = document.getElementById("clock");
const playheadEl = document.getElementById("playhead");
const exportBtn = document.getElementById("export");

let fixture = null;
let fixtureName = "";
let finals = [];
let labels = new Map();
let open = null;
let current = null;
let audioName = "";
let error = "";

const readJSON = (file) => file.text().then(JSON.parse);

const clock = (seconds) => {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
};

// Plays one AudioBuffer from an offset, to an optional end, with pause.
const player = {
  ctx: null,
  buffer: null,
  source: null,
  startedAt: 0,
  offset: 0,
  playing: false,
  context() {
    this.ctx ??= new AudioContext();
    return this.ctx;
  },
  load(buffer) {
    this.stop();
    this.buffer = buffer;
    this.offset = 0;
  },
  async play(from = this.offset, to = null) {
    if (!this.buffer) return;
    this.stop();
    const ctx = this.context();
    await ctx.resume();
    const source = ctx.createBufferSource();
    source.buffer = this.buffer;
    source.connect(ctx.destination);
    source.onended = () => {
      if (this.source !== source) return;
      this.offset = to ?? this.buffer.duration;
      this.source = null;
      this.playing = false;
      onPlayState();
    };
    source.start(0, from, to == null ? undefined : Math.max(0, to - from));
    this.source = source;
    this.startedAt = ctx.currentTime;
    this.offset = from;
    this.playing = true;
    onPlayState();
  },
  pause() {
    if (!this.playing) return;
    this.offset = this.position();
    this.stop();
    onPlayState();
  },
  stop() {
    if (this.source) {
      this.source.onended = null;
      this.source.stop();
      this.source = null;
    }
    this.playing = false;
  },
  position() {
    return this.playing
      ? this.offset + (this.ctx.currentTime - this.startedAt)
      : this.offset;
  },
  toggle() {
    if (!this.buffer) return false;
    if (this.playing) this.pause();
    else this.play(this.offset >= this.buffer.duration ? 0 : this.offset);
    return true;
  },
};

const playUtterance = (index) => {
  const segment = finals[index];
  if (!segment) return;
  setCurrent(index);
  player.play(segment.start, segment.end);
};

const rowFor = (index) => transcriptEl.children[index];

function setCurrent(index) {
  if (index == null || index < 0 || index >= finals.length) return;
  rowFor(current)?.classList.remove("current");
  current = index;
  rowFor(current).classList.add("current");
}

let playingIndex = null;

function utteranceAt(seconds) {
  let found = -1;
  for (let i = 0; i < finals.length && finals[i].start <= seconds; i++)
    found = i;
  return found;
}

function updatePlayhead(seconds) {
  if (!finals.length) return;
  const index = utteranceAt(seconds);
  const row = rowFor(Math.max(index, 0));
  let top = row.offsetTop;
  if (index >= 0) {
    const { start, end } = finals[index];
    const next = finals[index + 1];
    if (seconds <= end) {
      top += ((seconds - start) / (end - start || 1)) * row.offsetHeight;
    } else if (next) {
      const gap = (seconds - end) / (next.start - end || 1);
      const bottom = row.offsetTop + row.offsetHeight;
      top = bottom + Math.min(gap, 1) * (rowFor(index + 1).offsetTop - bottom);
    } else {
      top += row.offsetHeight;
    }
  }
  playheadEl.style.top = `${top}px`;
  playheadEl.hidden = false;
  clockEl.textContent = `${clock(seconds)} / ${clock(player.buffer.duration)}`;
  if (index !== playingIndex) {
    rowFor(playingIndex)?.classList.remove("playing");
    playingIndex = index;
    if (index >= 0 && player.playing) {
      row.classList.add("playing");
      setCurrent(index);
      const rect = row.getBoundingClientRect();
      if (rect.top < 0 || rect.bottom > innerHeight)
        row.scrollIntoView({ block: "center" });
    }
  }
}

function onPlayState() {
  if (player.playing) {
    const tick = () => {
      if (!player.playing) return;
      updatePlayhead(player.position());
      requestAnimationFrame(tick);
    };
    tick();
  } else {
    rowFor(playingIndex)?.classList.remove("playing");
    playingIndex = null;
    updatePlayhead(player.position());
  }
}

function kindPicker(index) {
  const picker = document.createElement("div");
  picker.className = "kinds";
  for (const { kind, key, meaning } of KINDS) {
    const button = document.createElement("button");
    button.title = meaning;
    button.innerHTML = `<kbd></kbd>`;
    button.firstChild.textContent = key;
    button.append(kind);
    button.addEventListener("click", (event) => {
      event.stopPropagation();
      setLabel(index, kind);
    });
    picker.append(button);
  }
  return picker;
}

function setLabel(index, kind) {
  if (kind == null) labels.delete(index);
  else labels.set(index, kind);
  open = null;
  render();
}

function render() {
  transcriptEl.replaceChildren();
  playheadEl.hidden = true;
  if (!fixture) {
    statusEl.textContent = error;
    return;
  }
  finals.forEach((segment, index) => {
    const row = document.createElement("div");
    row.className = "utt";
    if (labels.has(index)) row.classList.add("marked");
    if (current === index) row.classList.add("current");
    row.innerHTML =
      '<time></time><button class="play" title="Play this utterance">&#x25B8;</button><span></span><span class="tag"></span>';
    const [time, play, text, tag] = row.children;
    time.textContent = clock(segment.start);
    text.textContent = segment.text;
    tag.textContent = labels.get(index) ?? "";
    play.disabled = !player.buffer;
    row.addEventListener("click", () => toggleKinds(index));
    for (const control of [time, play]) {
      control.addEventListener("click", (event) => {
        event.stopPropagation();
        playUtterance(index);
      });
    }
    transcriptEl.append(row);
  });
  if (open != null) rowFor(open).after(kindPicker(open));
  exportBtn.disabled = labels.size === 0;
  const counts = countByKind(labels)
    .map(([kind, count]) => `${kind} ${count}`)
    .join(", ");
  const parts = [
    `${finals.length} utterances`,
    `${labels.size} labeled${counts ? ` (${counts})` : ""}`,
    audioName ? `audio ${audioName}` : "no audio",
  ];
  if (error) parts.push(error);
  statusEl.textContent = parts.join(", ");
  if (player.buffer) updatePlayhead(player.position());
  else clockEl.textContent = "";
}

function toggleKinds(index) {
  setCurrent(index);
  if (labels.has(index)) {
    labels.delete(index);
    open = null;
  } else {
    open = open === index ? null : index;
  }
  render();
}

function moveCurrent(step) {
  if (!finals.length) return;
  const next =
    current == null ? (step > 0 ? 0 : finals.length - 1) : current + step;
  if (next < 0 || next >= finals.length) return;
  setCurrent(next);
  rowFor(next).scrollIntoView({ block: "nearest" });
}

function handleKey(key) {
  if (key === " ") return player.toggle();
  if (!fixture) return false;
  if (key === "ArrowDown") return (moveCurrent(1), true);
  if (key === "ArrowUp") return (moveCurrent(-1), true);
  if (current == null) return false;
  if (key === "Enter") return (playUtterance(current), true);
  const kind = kindForKey(key);
  if (kind === undefined) return false;
  setLabel(current, kind);
  return true;
}

document.addEventListener("keydown", (event) => {
  if (event.metaKey || event.ctrlKey || event.altKey) return;
  if (handleKey(event.key)) event.preventDefault();
});

async function loadFixture(file) {
  fixture = await readJSON(file);
  fixtureName = fixtureBaseName(file.name);
  finals = finalSegments(fixture);
  labels = new Map();
  open = null;
  current = null;
  render();
}

async function loadLabels(file) {
  labels = labelsFromFile(await readJSON(file));
  render();
}

async function loadAudio(file) {
  const bytes = await file.arrayBuffer();
  const ctx = player.context();
  let buffer;
  if (/\.caf$/i.test(file.name)) {
    const pcm = parseCAF(bytes);
    buffer = ctx.createBuffer(
      pcm.channels.length,
      pcm.channels[0].length,
      pcm.sampleRate,
    );
    pcm.channels.forEach((samples, i) => buffer.copyToChannel(samples, i));
  } else {
    buffer = await ctx.decodeAudioData(bytes);
  }
  player.load(buffer);
  audioName = file.name;
  render();
}

const isAudio = (file) => /\.(caf|m4a|wav|mp3)$/i.test(file.name);

// Fixture before labels before audio, whatever order the files arrive in.
async function ingest(files) {
  error = "";
  const json = [];
  const audio = [];
  for (const file of files) (isAudio(file) ? audio : json).push(file);
  try {
    const parsed = await Promise.all(
      json.map(async (file) => [file, await readJSON(file)]),
    );
    for (const [file, data] of parsed)
      if (Array.isArray(data.segments)) await loadFixture(file);
    for (const [file, data] of parsed)
      if (Array.isArray(data.labels)) await loadLabels(file);
    for (const file of audio) await loadAudio(file);
  } catch (caught) {
    error = caught.message;
    render();
  }
}

const bindInput = (id, load) =>
  document.getElementById(id).addEventListener("change", async (event) => {
    const [file] = event.target.files;
    event.target.blur();
    if (!file) return;
    error = "";
    try {
      await load(file);
    } catch (caught) {
      error = caught.message;
      render();
    }
  });

bindInput("fixture", loadFixture);
bindInput("labels", loadLabels);
bindInput("audio", loadAudio);

document.addEventListener("dragover", (event) => {
  event.preventDefault();
  document.body.classList.add("dropping");
});
document.addEventListener("dragleave", () =>
  document.body.classList.remove("dropping"),
);
document.addEventListener("drop", (event) => {
  event.preventDefault();
  document.body.classList.remove("dropping");
  ingest([...event.dataTransfer.files]);
});

exportBtn.addEventListener("click", () => {
  const body = buildLabels(fixtureName, finals, labels);
  const blob = new Blob([JSON.stringify(body, null, 2)], {
    type: "application/json",
  });
  const link = document.createElement("a");
  link.href = URL.createObjectURL(blob);
  link.download = `${fixtureName}.labels.json`;
  link.click();
  URL.revokeObjectURL(link.href);
});
