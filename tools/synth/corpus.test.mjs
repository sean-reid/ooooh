import assert from "node:assert/strict";
import { existsSync, readdirSync } from "node:fs";
import { basename, join } from "node:path";
import { test } from "node:test";
import { SCHEMA_PATH, estimateDuration } from "./synth.mjs";
import { validate } from "./validate.mjs";
import {
  AUDIO_DIR,
  afinfoDuration,
  hasTool,
  readJSON,
  scripts,
  wavDuration,
} from "./testing.mjs";

const schema = readJSON(SCHEMA_PATH);
const hasAfinfo = hasTool("afinfo");
const labelsOf = (script) =>
  script.utterances.map((u) => u.label).filter(Boolean);
const indexOfLabel = (script, kind) =>
  script.utterances.findIndex((u) => u.label === kind);
const speechSeconds = (script) =>
  script.utterances.reduce((sum, u) => sum + estimateDuration(u.text), 0);
const pauseSeconds = (script) =>
  script.utterances.reduce((sum, u) => sum + u.pauseAfter, 0);

test("the corpus has the ten archetypes", () => {
  assert.deepEqual(Object.keys(scripts), [
    "addressing-app",
    "debugging-design",
    "decision",
    "essay-planning",
    "false-ending",
    "flowing",
    "late-night",
    "personal-dilemma",
    "stuck",
    "two-threads",
  ]);
});

test("every checked-in script validates, is 3 to 8 minutes of speech, and pauses like a person", () => {
  for (const [name, script] of Object.entries(scripts)) {
    assert.deepEqual(validate(script, schema), [], name);
    assert.equal(script.name, name);
    const speech = speechSeconds(script);
    assert.ok(
      speech >= 180 && speech <= 480,
      `${name} has ${speech.toFixed(0)} s of speech`,
    );
    const pauses = script.utterances.map((u) => u.pauseAfter);
    assert.ok(
      pauses.every((p) => p >= 0.4 && p <= 40),
      `${name} pause out of range`,
    );
    const slow = Math.max(...pauses) >= 20;
    const shortGaps = pauses.filter((p) => p <= 1.5).length;
    assert.ok(
      shortGaps >= pauses.length / (slow ? 5 : 2),
      `${name} needs ${slow ? "some" : "mostly"} short gaps`,
    );
    const minutes = (speech + pauseSeconds(script)) / 60;
    assert.ok(
      pauses.filter((p) => p >= 3 && p <= 8).length >= minutes / 2,
      `${name} needs thinking pauses`,
    );
    const finished = script.utterances
      .map((u, i) => (u.label === "finished" ? i : -1))
      .filter((i) => i >= 0);
    assert.deepEqual(
      finished,
      [script.utterances.length - 1],
      `${name} must mark finished once, on the last line`,
    );
    assert.ok(
      /\b(um|uh)\b/i.test(script.utterances.map((u) => u.text).join(" ")),
      `${name} has no fillers`,
    );
  }
});

test("flowing earns at most one prompt, a deepen, and several leaves", () => {
  const labels = labelsOf(scripts.flowing).filter(
    (k) => k !== "leave" && k !== "finished",
  );
  assert.ok(
    labels.length <= 1 && labels.every((k) => k === "deepen"),
    labels.join(","),
  );
  assert.ok(labelsOf(scripts.flowing).filter((k) => k === "leave").length >= 3);
});

test("stuck carries reflect, clarify, then challenge in that order", () => {
  const s = scripts.stuck;
  assert.ok(indexOfLabel(s, "reflect") >= 0);
  assert.ok(indexOfLabel(s, "clarify") > indexOfLabel(s, "reflect"));
  assert.ok(indexOfLabel(s, "challenge") > indexOfLabel(s, "clarify"));
  assert.ok(
    indexOfLabel(s, "challenge") > s.utterances.length * 0.6,
    "challenge comes late",
  );
});

test("decision carries an early clarify, a decide, and a summarize after a long run", () => {
  const s = scripts.decision;
  assert.ok(
    indexOfLabel(s, "clarify") >= 0 &&
      indexOfLabel(s, "clarify") < s.utterances.length * 0.25,
  );
  assert.ok(indexOfLabel(s, "decide") > indexOfLabel(s, "clarify"));
  const summarize = indexOfLabel(s, "summarize");
  assert.ok(summarize > 0);
  const runBefore = s.utterances.slice(summarize - 6, summarize + 1);
  assert.ok(
    runBefore.every((u) => u.pauseAfter <= 1.5),
    "the run before summarize has no long pauses",
  );
});

test("essay planning carries deepen and summarize", () => {
  assert.ok(indexOfLabel(scripts["essay-planning"], "deepen") >= 0);
  assert.ok(indexOfLabel(scripts["essay-planning"], "summarize") >= 0);
});

test("personal dilemma is mostly leave with one reflect and long silences", () => {
  const s = scripts["personal-dilemma"];
  const labels = labelsOf(s).filter((k) => k !== "finished");
  assert.equal(labels.filter((k) => k === "reflect").length, 1);
  assert.ok(labels.filter((k) => k === "leave").length >= labels.length * 0.6);
  assert.ok(s.utterances.filter((u) => u.pauseAfter >= 15).length >= 3);
  assert.ok(
    s.utterances
      .filter((u) => u.pauseAfter >= 15)
      .every((u) => u.label === "leave"),
  );
});

test("late night pauses at least 20 s, marks every long pause leave, and finishes only at the end", () => {
  const s = scripts["late-night"];
  const long = s.utterances.filter((u) => u.pauseAfter >= 20);
  assert.ok(long.length >= 5, `${long.length} pauses of 20 s or more`);
  assert.ok(Math.max(...s.utterances.map((u) => u.pauseAfter)) >= 20);
  assert.ok(long.every((u) => u.label === "leave"));
  assert.deepEqual([...new Set(labelsOf(s))].sort(), ["finished", "leave"]);
});

test("debugging a design carries clarify and challenge", () => {
  assert.ok(indexOfLabel(scripts["debugging-design"], "clarify") >= 0);
  assert.ok(
    indexOfLabel(scripts["debugging-design"], "challenge") >
      indexOfLabel(scripts["debugging-design"], "clarify"),
  );
});

test("addressing the app has one recall and one wrapUp, in that order", () => {
  const s = scripts["addressing-app"];
  const labels = labelsOf(s);
  assert.equal(labels.filter((k) => k === "recall").length, 1);
  assert.equal(labels.filter((k) => k === "wrapUp").length, 1);
  assert.ok(indexOfLabel(s, "recall") < indexOfLabel(s, "wrapUp"));
  assert.match(s.utterances[indexOfLabel(s, "recall")].text, /what did I say/i);
  assert.match(s.utterances[indexOfLabel(s, "wrapUp")].text, /wrap up/i);
});

test("false ending says that is it early, keeps going for two minutes, and finishes only at the real end", () => {
  const s = scripts["false-ending"];
  const fake = s.utterances.findIndex((u) =>
    /okay I think that('s| is) it/i.test(u.text),
  );
  assert.ok(fake > 0 && fake < s.utterances.length - 1);
  assert.equal(s.utterances[fake].label, undefined);
  const after = s.utterances.slice(fake + 1);
  const seconds = after.reduce(
    (sum, u) => sum + estimateDuration(u.text) + u.pauseAfter,
    0,
  );
  assert.ok(seconds >= 100, `${seconds.toFixed(0)} s after the false ending`);
  assert.equal(labelsOf(s).filter((k) => k === "finished").length, 1);
});

test("two threads summarizes at the switch and reflects when the first thread returns", () => {
  const s = scripts["two-threads"];
  const summarize = indexOfLabel(s, "summarize");
  const reflect = indexOfLabel(s, "reflect");
  assert.ok(
    summarize > s.utterances.length * 0.25 &&
      summarize < s.utterances.length * 0.6,
  );
  assert.ok(reflect > summarize);
});

const rendered = existsSync(AUDIO_DIR)
  ? readdirSync(AUDIO_DIR)
      .filter((f) => f.endsWith(".wav"))
      .map((f) => basename(f, ".wav"))
  : [];

test(
  "say-mode audio lengths match the fixture timings",
  { skip: rendered.length === 0 && "no say-mode audio rendered" },
  () => {
    for (const name of rendered) {
      const fixture = readJSON(join(AUDIO_DIR, `${name}.fixture.json`));
      const script = scripts[name];
      const speech = fixture.segments.reduce(
        (sum, s) => sum + (s.end - s.start),
        0,
      );
      const expected = speech + pauseSeconds(script);
      const wav = wavDuration(join(AUDIO_DIR, `${name}.wav`));
      assert.ok(
        Math.abs(wav - expected) < 0.1,
        `${name}.wav is ${wav.toFixed(3)} s, fixture says ${expected.toFixed(3)} s`,
      );
      if (hasAfinfo) {
        const m4a = afinfoDuration(join(AUDIO_DIR, `${name}.m4a`));
        assert.ok(
          Math.abs(m4a - expected) < 0.1,
          `${name}.m4a is ${m4a.toFixed(3)} s, fixture says ${expected.toFixed(3)} s`,
        );
      }
      assert.ok(
        speech >= 120,
        `${name} rendered only ${speech.toFixed(0)} s of speech`,
      );
    }
  },
);

test(
  "rendered late night has a silence of at least 20 s",
  { skip: !rendered.includes("late-night") && "late-night not rendered" },
  () => {
    const fixture = readJSON(join(AUDIO_DIR, "late-night.fixture.json"));
    const gaps = fixture.segments
      .slice(1)
      .map((s, i) => s.start - fixture.segments[i].end);
    assert.ok(Math.max(...gaps) >= 20, `longest gap ${Math.max(...gaps)} s`);
  },
);
