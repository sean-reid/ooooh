#!/usr/bin/env node
import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  realpathSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import {
  elevenLabsClient,
  listSayVoices,
  pickSayVoice,
  sayUtterance,
  spliceClips,
  wavFromPCM,
} from "./tts.mjs";
import { validate } from "./validate.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const SCHEMA_PATH = resolve(
  here,
  "../../fixtures/synthetic/scripts/script.schema.json",
);
export const WORDS_PER_SECOND = 2.6;
export const UTTERANCE_OVERHEAD = 0.3;
export const MODES = ["say", "elevenlabs", "estimate"];

const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));
const writeJSON = (file, value) =>
  writeFileSync(file, JSON.stringify(value, null, 2) + "\n");

export function loadScript(file, schema = readJSON(SCHEMA_PATH)) {
  const script = readJSON(file);
  const errors = validate(script, schema);
  if (errors.length)
    throw new Error(`${file} fails the schema:\n  ${errors.join("\n  ")}`);
  return script;
}

export const wordCount = (text) =>
  text.trim().split(/\s+/).filter(Boolean).length;

export const estimateDuration = (text) =>
  Math.round((wordCount(text) / WORDS_PER_SECOND + UTTERANCE_OVERHEAD) * 1000) /
  1000;

// Accumulates in whole milliseconds so start and end never drift from the audio.
export function timeline(durations, pauses) {
  if (durations.length !== pauses.length)
    throw new Error("one pause per utterance");
  let clock = 0;
  return durations.map((duration, i) => {
    const start = clock;
    clock += Math.round(duration * 1000);
    const end = clock;
    clock += Math.round(pauses[i] * 1000);
    return { start: start / 1000, end: end / 1000 };
  });
}

export function buildFixture(script, durations) {
  const times = timeline(
    durations,
    script.utterances.map((u) => u.pauseAfter),
  );
  return {
    segments: script.utterances.map((u, i) => ({
      text: u.text,
      start: times[i].start,
      end: times[i].end,
      isFinal: true,
    })),
  };
}

export function buildLabels(script, fixture) {
  const labels = [];
  script.utterances.forEach((u, i) => {
    if (u.label)
      labels.push({ utterance: i, at: fixture.segments[i].end, kind: u.label });
  });
  return { fixture: script.name, labels };
}

async function renderClips(script, mode, voice, work) {
  const texts = script.utterances.map((u) => u.text);
  if (mode === "say") {
    const chosen = voice ?? script.voice ?? pickSayVoice(listSayVoices());
    return texts.map((text, i) => {
      const file = join(work, `${i}.wav`);
      return { file, duration: sayUtterance(text, chosen, file) };
    });
  }
  const client = elevenLabsClient({ voice: voice ?? script.voice });
  const clips = [];
  for (const [i, text] of texts.entries()) {
    const { pcm, duration } = await client.speak(text);
    const file = join(work, `${i}.wav`);
    writeFileSync(file, wavFromPCM(pcm));
    clips.push({ file, duration });
  }
  return clips;
}

export async function synthesize(
  scriptPath,
  { out, tts = "estimate", voice } = {},
) {
  if (!MODES.includes(tts))
    throw new Error(`--tts must be one of ${MODES.join(", ")}`);
  const script = loadScript(scriptPath);
  mkdirSync(out, { recursive: true });
  let durations;
  if (tts === "estimate") {
    durations = script.utterances.map((u) => estimateDuration(u.text));
  } else {
    const work = mkdtempSync(join(tmpdir(), `synth-${script.name}-`));
    try {
      const clips = await renderClips(script, tts, voice, work);
      durations = clips.map((clip) => clip.duration);
      spliceClips(
        clips.map((clip) => clip.file),
        script.utterances.map((u) => u.pauseAfter),
        {
          m4a: join(out, `${script.name}.m4a`),
          wav: join(out, `${script.name}.wav`),
        },
      );
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  }
  const fixture = buildFixture(script, durations);
  const labels = buildLabels(script, fixture);
  writeJSON(join(out, `${script.name}.fixture.json`), fixture);
  writeJSON(join(out, `${script.name}.labels.json`), labels);
  const last = fixture.segments.at(-1);
  return {
    name: script.name,
    fixture,
    labels,
    total: last.end + script.utterances.at(-1).pauseAfter,
  };
}

export const listScripts = (dir) =>
  readdirSync(dir)
    .filter((f) => f.endsWith(".json") && !f.endsWith(".schema.json"))
    .sort()
    .map((f) => join(dir, f));

const usage = `usage: node tools/synth/synth.mjs <script.json> --out <dir> [--tts say|elevenlabs|estimate] [--voice <name>]
       node tools/synth/synth.mjs --all <scripts dir> --out <dir> [--tts ...] [--voice ...]`;

export async function main(argv) {
  const { values, positionals } = parseArgs({
    args: argv,
    allowPositionals: true,
    options: {
      out: { type: "string" },
      tts: { type: "string", default: "estimate" },
      voice: { type: "string" },
      all: { type: "string" },
    },
  });
  if (!values.out || (positionals.length === 0 && !values.all)) {
    console.error(usage);
    return 2;
  }
  const scripts = values.all ? listScripts(values.all) : positionals;
  for (const script of scripts) {
    const result = await synthesize(script, {
      out: values.out,
      tts: values.tts,
      voice: values.voice,
    });
    console.log(
      `${result.name}: ${result.fixture.segments.length} utterances, ${result.labels.labels.length} labels, ${result.total.toFixed(1)} s (${values.tts})`,
    );
  }
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
