#!/usr/bin/env node
import { createHash } from "node:crypto";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { VOICE_SCRIPTS_DIR } from "./scripts.mjs";
import { listScripts, loadScript, timeline } from "./synth.mjs";
import { elevenLabsClient, wavFromPCM } from "./tts.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const WRANGLER_PATH = resolve(here, "../../worker/wrangler.jsonc");
export const VOICE_AUDIO_DIR = resolve(
  here,
  "../../fixtures/synthetic/voice/audio",
);
export const CACHE_DIR = resolve(here, "../../data/voice-cache");
export const SAMPLE_RATE = 16000;
export const MAX_CHARACTERS = 40_000;
// The Worker's speak route renders with these; the corpus sounds like the app.
export const MODEL = "eleven_v4_turbo";
export const SETTINGS = { stability: 0.6, similarity_boost: 0.75 };

const BYTES_PER_MS = (SAMPLE_RATE * 2) / 1000;

// The voice id the Worker ships with, from its top-level vars.
export function workerVoiceId(file = WRANGLER_PATH) {
  const match = readFileSync(file, "utf8").match(
    /"ELEVENLABS_VOICE_ID"\s*:\s*"([^"]+)"/,
  );
  if (!match) throw new Error(`no ELEVENLABS_VOICE_ID in ${file}`);
  return match[1];
}

export const clipKey = (text, { model = MODEL, voice } = {}) =>
  createHash("sha256").update(`${model}\n${voice}\n${text}`).digest("hex");

export function clipCache(dir) {
  const path = (key) => join(dir, `${key}.pcm`);
  return {
    has: (key) => existsSync(path(key)),
    read: (key) => readFileSync(path(key)),
    write(key, pcm) {
      mkdirSync(dir, { recursive: true });
      writeFileSync(path(key), pcm);
    },
  };
}

// Every utterance across the scripts with its cache key, and the character totals.
export function plan(scripts, cache, voice) {
  const items = scripts.flatMap((script) =>
    script.utterances.map((u, index) => {
      const key = clipKey(u.text, { voice });
      return {
        script: script.name,
        index,
        text: u.text,
        key,
        cached: cache.has(key),
      };
    }),
  );
  const characters = items.reduce((n, i) => n + i.text.length, 0);
  const uncached = items
    .filter((i) => !i.cached)
    .reduce((n, i) => n + i.text.length, 0);
  return { items, characters, uncached };
}

// Whole milliseconds, so the sample count agrees with the timeline exactly.
export function padToMillisecond(pcm) {
  const remainder = pcm.length % BYTES_PER_MS;
  return remainder === 0
    ? pcm
    : Buffer.concat([pcm, Buffer.alloc(BYTES_PER_MS - remainder)]);
}

export const silence = (seconds) =>
  Buffer.alloc(Math.round(seconds * 1000) * BYTES_PER_MS);

// The clips and the script's pauses as one PCM stream plus the sidecar timeline.
export function assemble(script, clips, { voice, model = MODEL } = {}) {
  if (clips.length !== script.utterances.length)
    throw new Error(
      `${script.name}: ${clips.length} clips for ${script.utterances.length} utterances`,
    );
  const padded = clips.map(padToMillisecond);
  const durations = padded.map((pcm) => pcm.length / 2 / SAMPLE_RATE);
  const pauses = script.utterances.map((u) => u.pauseAfter);
  const times = timeline(durations, pauses);
  const parts = [];
  padded.forEach((pcm, i) => parts.push(pcm, silence(pauses[i])));
  const pcm = Buffer.concat(parts);
  return {
    pcm,
    sidecar: {
      name: script.name,
      voice,
      model,
      sampleRate: SAMPLE_RATE,
      characters: script.utterances.reduce((n, u) => n + u.text.length, 0),
      seconds: pcm.length / 2 / SAMPLE_RATE,
      utterances: script.utterances.map((u, i) => ({
        index: i,
        text: u.text,
        start: times[i].start,
        end: times[i].end,
        pauseAfter: u.pauseAfter,
        ...(u.label ? { label: u.label } : {}),
      })),
    },
  };
}

// Renders a script's clips in order, one request per uncached utterance.
export async function renderClips(script, { client, cache, voice, log }) {
  const clips = [];
  for (const [i, u] of script.utterances.entries()) {
    const key = clipKey(u.text, { voice });
    if (cache.has(key)) {
      clips.push(cache.read(key));
      continue;
    }
    const { pcm } = await client.speak(u.text);
    cache.write(key, pcm);
    clips.push(pcm);
    log?.(
      `${script.name} ${i + 1}/${script.utterances.length}: ${u.text.length} characters`,
    );
  }
  return clips;
}

export async function renderScript(script, options) {
  const clips = await renderClips(script, options);
  const { pcm, sidecar } = assemble(script, clips, options);
  mkdirSync(options.out, { recursive: true });
  writeFileSync(
    join(options.out, `${script.name}.wav`),
    wavFromPCM(pcm, SAMPLE_RATE),
  );
  writeFileSync(
    join(options.out, `${script.name}.timeline.json`),
    JSON.stringify(sidecar, null, 2) + "\n",
  );
  return sidecar;
}

const usage = `usage: node tools/synth/voice.mjs [--scripts <dir>] [--out <dir>] [--max-characters 40000] [--cache <dir>]
Renders every script through ElevenLabs with the Worker's voice into <out>/<name>.wav and <name>.timeline.json.
Needs ELEVENLABS_API_KEY. Rendered utterances are cached under --cache by text, so a rerun costs nothing.`;

export async function main(argv, { client, log = console.error } = {}) {
  const { values } = parseArgs({
    args: argv,
    options: {
      scripts: { type: "string", default: VOICE_SCRIPTS_DIR },
      out: { type: "string", default: VOICE_AUDIO_DIR },
      "max-characters": { type: "string", default: String(MAX_CHARACTERS) },
      cache: { type: "string", default: CACHE_DIR },
      help: { type: "boolean", default: false },
    },
  });
  if (values.help) {
    console.log(usage);
    return 0;
  }
  const budget = Number(values["max-characters"]);
  if (!Number.isInteger(budget) || budget < 0)
    throw new Error("--max-characters takes a whole number of characters");
  const voice = workerVoiceId();
  const scripts = listScripts(values.scripts).map((file) => loadScript(file));
  if (scripts.length === 0) throw new Error(`no scripts in ${values.scripts}`);
  const cache = clipCache(values.cache);
  const { items, characters, uncached } = plan(scripts, cache, voice);
  console.log(
    `${scripts.length} scripts, ${items.length} utterances, ${characters} characters, ` +
      `${uncached} to render (${items.filter((i) => i.cached).length} utterances cached), voice ${voice}, ${MODEL}`,
  );
  if (uncached > budget) {
    console.error(
      `refusing: ${uncached} characters to render is over the --max-characters budget of ${budget}`,
    );
    return 2;
  }
  client ??= elevenLabsClient({
    voice,
    model: MODEL,
    settings: SETTINGS,
    sampleRate: SAMPLE_RATE,
  });
  let rendered = 0;
  for (const script of scripts) {
    const before = plan([script], cache, voice).uncached;
    const sidecar = await renderScript(script, {
      client,
      cache,
      voice,
      out: values.out,
      log,
    });
    rendered += before;
    console.log(
      `${script.name}: ${sidecar.utterances.length} utterances, ${sidecar.seconds.toFixed(1)} s, ${before} characters rendered`,
    );
  }
  console.log(`rendered ${rendered} characters, wrote ${values.out}`);
  return 0;
}

if (
  process.argv[1] &&
  realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      console.error(error.message);
      process.exit(1);
    },
  );
}
