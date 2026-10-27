#!/usr/bin/env node
import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  realpathSync,
  writeFileSync,
} from "node:fs";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { finalSegments } from "../labeler/labels.mjs";
import { wordCount } from "./synth.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const RECORDINGS_DIR = resolve(here, "../../data/recordings");
export const STYLE_PATH = resolve(here, "../../data/style.json");

// A gap this long or longer is a pause the speaker took, not a recognizer split.
export const PAUSE_FLOOR = 1;
export const LONG_PAUSE = 5;

const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));
const round = (value) => Math.round(value * 100) / 100;
const mean = (values) =>
  values.length ? values.reduce((a, b) => a + b, 0) / values.length : 0;
const share = (values, predicate) =>
  values.length ? values.filter(predicate).length / values.length : 0;

// Nearest rank, so every quantile is a value the data holds.
export function quantile(values, p) {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const rank = Math.min(
    sorted.length,
    Math.max(1, Math.ceil(p * sorted.length)),
  );
  return sorted[rank - 1];
}

export const distribution = (values) => ({
  count: values.length,
  min: round(quantile(values, 0)),
  p25: round(quantile(values, 0.25)),
  median: round(quantile(values, 0.5)),
  p75: round(quantile(values, 0.75)),
  p90: round(quantile(values, 0.9)),
  max: round(values.length ? Math.max(...values) : 0),
  mean: round(mean(values)),
});

const tokens = (text) =>
  text
    .toLowerCase()
    .split(/\s+/)
    .map((w) => w.replace(/[^a-z0-9']/g, ""))
    .filter(Boolean);

export function countFillers(text) {
  const lower = text.toLowerCase();
  let count = 0;
  count += (lower.match(/\b(um+|uh+|erm|hmm+)\b/g) ?? []).length;
  count += (lower.match(/\byou know\b/g) ?? []).length;
  count += (lower.match(/\blike,/g) ?? []).length;
  count += (lower.match(/(^|[.?!]\s*)so\b/g) ?? []).length;
  return count;
}

export function countRepeats(text) {
  const words = tokens(text);
  let count = 0;
  for (let i = 1; i < words.length; i++) {
    if (words[i] === words[i - 1] && /^[a-z]/.test(words[i])) count += 1;
  }
  return count;
}

const endsSentence = (text) => /[.?!]["')]?\s*$/.test(text);
const startsSentence = (text) => /^\s*[A-Z]/.test(text);

const CLOSERS =
  /\b(okay|ok|alright|anyway|yeah|done|that's it|that is it|i think|enough|stop|wrap)\b/i;

export function gaps(finals) {
  return finals
    .slice(1)
    .map((segment, i) => round(Math.max(0, segment.start - finals[i].end)));
}

// Speech runs: consecutive utterances joined when the gap is under PAUSE_FLOOR.
export function runs(finals) {
  const out = [];
  let words = 0;
  finals.forEach((segment, i) => {
    words += wordCount(segment.text);
    const gap =
      i + 1 < finals.length ? finals[i + 1].start - segment.end : Infinity;
    if (gap >= PAUSE_FLOOR) {
      out.push(words);
      words = 0;
    }
  });
  return out;
}

export function sessionStats(fixture, labels) {
  const finals = finalSegments(fixture);
  if (finals.length === 0) throw new Error("fixture has no final segments");
  const texts = finals.map((s) => s.text);
  const words = texts.map(wordCount);
  const totalWords = words.reduce((a, b) => a + b, 0);
  const pauses = gaps(finals);
  const abandoned = finals.filter(
    (s, i) =>
      i + 1 < finals.length &&
      !endsSentence(s.text) &&
      startsSentence(finals[i + 1].text),
  ).length;
  const last = finals.at(-1);
  const counts = {};
  for (const label of labels?.labels ?? []) {
    counts[label.kind] = (counts[label.kind] ?? 0) + 1;
  }
  return {
    utterances: finals.length,
    words: totalWords,
    seconds: round(last.end),
    wordsPerUtterance: words,
    wordsPerRun: runs(finals),
    pauses,
    fillers: texts.reduce((sum, t) => sum + countFillers(t), 0),
    repeats: texts.reduce((sum, t) => sum + countRepeats(t), 0),
    abandoned,
    questions: finals.filter((s) => s.text.includes("?")).length,
    ending: {
      words: wordCount(last.text),
      question: last.text.includes("?"),
      closer: CLOSERS.test(last.text),
      gapBefore: round(pauses.at(-1) ?? 0),
    },
    labels: counts,
  };
}

const per100 = (count, words) => (words ? round((count / words) * 100) : 0);

export function styleSheet(sessions) {
  if (sessions.length === 0) throw new Error("no sessions to measure");
  const all = (key) => sessions.flatMap((s) => s[key]);
  const sum = (key) => sessions.reduce((a, s) => a + s[key], 0);
  const words = sum("words");
  const pauses = all("pauses");
  const realPauses = pauses.filter((p) => p >= PAUSE_FLOOR);
  const labelCounts = {};
  for (const s of sessions) {
    for (const [kind, n] of Object.entries(s.labels)) {
      labelCounts[kind] = round((labelCounts[kind] ?? 0) + n / sessions.length);
    }
  }
  return {
    sessions: sessions.length,
    session: {
      meanSeconds: round(mean(sessions.map((s) => s.seconds))),
      meanUtterances: round(mean(sessions.map((s) => s.utterances))),
      meanWords: round(mean(sessions.map((s) => s.words))),
      wordsPerMinute: round(words / (sum("seconds") / 60)),
    },
    wordsPerUtterance: distribution(all("wordsPerUtterance")),
    wordsPerRun: distribution(all("wordsPerRun")),
    pauses: {
      ...distribution(pauses),
      shareUnderOneSecond: round(share(pauses, (p) => p < PAUSE_FLOOR)),
      perSessionOverOneSecond: round(realPauses.length / sessions.length),
      perSessionOverFiveSeconds: round(
        pauses.filter((p) => p >= LONG_PAUSE).length / sessions.length,
      ),
      overOneSecond: distribution(realPauses),
    },
    fillersPer100Words: per100(sum("fillers"), words),
    restartsPer100Words: per100(sum("repeats") + sum("abandoned"), words),
    repeatsPer100Words: per100(sum("repeats"), words),
    abandonedPerUtterance: round(sum("abandoned") / sum("utterances")),
    questionsPerUtterance: round(sum("questions") / sum("utterances")),
    endings: {
      meanWords: round(mean(sessions.map((s) => s.ending.words))),
      questionShare: round(share(sessions, (s) => s.ending.question)),
      closerShare: round(share(sessions, (s) => s.ending.closer)),
      meanGapBefore: round(mean(sessions.map((s) => s.ending.gapBefore))),
    },
    labelsPerSession: labelCounts,
  };
}

export function listRecordings(dir) {
  return readdirSync(dir)
    .filter(
      (f) =>
        f.endsWith(".json") &&
        !f.endsWith(".labels.json") &&
        !f.endsWith(".labels.proposed.json"),
    )
    .sort()
    .map((f) => {
      const name = basename(f, ".json");
      const labels = join(dir, `${name}.labels.json`);
      return {
        name,
        fixture: join(dir, f),
        labels: existsSync(labels) ? labels : null,
      };
    });
}

export function measure(dir) {
  const recordings = listRecordings(dir);
  if (recordings.length === 0) throw new Error(`no recordings in ${dir}`);
  return styleSheet(
    recordings.map((r) =>
      sessionStats(readJSON(r.fixture), r.labels ? readJSON(r.labels) : null),
    ),
  );
}

const usage = `usage: node tools/synth/style.mjs [--recordings <dir>] [--out <style.json>]
Reads the real recordings and writes a style sheet of statistics, no text.`;

export async function main(argv) {
  const { values } = parseArgs({
    args: argv,
    options: {
      recordings: { type: "string", default: RECORDINGS_DIR },
      out: { type: "string", default: STYLE_PATH },
      help: { type: "boolean", default: false },
    },
  });
  if (values.help) {
    console.log(usage);
    return 0;
  }
  const style = measure(values.recordings);
  mkdirSync(dirname(values.out), { recursive: true });
  writeFileSync(values.out, JSON.stringify(style, null, 2) + "\n");
  console.log(
    `${style.sessions} sessions, ${style.session.meanSeconds} s and ${style.session.meanWords} words each, ` +
      `${style.fillersPer100Words} fillers per 100 words, ${style.pauses.perSessionOverFiveSeconds} pauses over 5 s per session`,
  );
  console.log(`wrote ${values.out}`);
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
