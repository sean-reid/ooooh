import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import {
  countFillers,
  countRepeats,
  distribution,
  gaps,
  listRecordings,
  main,
  measure,
  quantile,
  runs,
  sessionStats,
  styleSheet,
} from "./style.mjs";
import { tempDir } from "./testing.mjs";

// Four utterances: a recognizer split at 0.2 s, a real pause of 1.5 s, a long one of 6 s.
const fixture = {
  segments: [
    { text: "Okay so um, the the plan", start: 0, end: 2, isFinal: true },
    { text: "is to move house.", start: 2.2, end: 4, isFinal: true },
    { text: "Is that even right?", start: 5.5, end: 7, isFinal: true },
    { text: "partial words", start: 7, end: 8, isFinal: false },
    {
      text: "Yeah, okay. I think that's it.",
      start: 13,
      end: 15,
      isFinal: true,
    },
  ],
};
const labels = {
  fixture: "tiny",
  labels: [
    { utterance: 2, at: 7, kind: "leave" },
    { utterance: 3, at: 15, kind: "finished" },
  ],
};

test("quantile is nearest rank and distribution rounds to two places", () => {
  assert.equal(quantile([3, 1, 2], 0.5), 2);
  assert.equal(quantile([1, 2, 3, 4], 0.25), 1);
  assert.equal(quantile([1, 2, 3, 4], 0.75), 3);
  assert.equal(quantile([], 0.5), 0);
  assert.deepEqual(distribution([1, 2, 2.345]), {
    count: 3,
    min: 1,
    p25: 1,
    median: 2,
    p75: 2.35,
    p90: 2.35,
    max: 2.35,
    mean: 1.78,
  });
});

test("fillers count um, uh, you know, like with a comma, and sentence-initial so", () => {
  assert.equal(
    countFillers("Um, so I think, like, you know, uh, it's fine. So yes."),
    5,
  );
  assert.equal(countFillers("I like it, so what"), 0);
});

test("repeats count a word said twice in a row", () => {
  assert.equal(countRepeats("the the plan is is to go"), 2);
  assert.equal(countRepeats("The plan. The plan is set"), 0);
});

test("gaps and runs ignore partials and join utterances split under a second", () => {
  const finals = fixture.segments.filter((s) => s.isFinal);
  assert.deepEqual(gaps(finals), [0.2, 1.5, 6]);
  assert.deepEqual(runs(finals), [10, 4, 6]);
});

test("sessionStats measures one recording", () => {
  const stats = sessionStats(fixture, labels);
  assert.equal(stats.utterances, 4);
  assert.equal(stats.words, 20);
  assert.equal(stats.seconds, 15);
  assert.deepEqual(stats.wordsPerUtterance, [6, 4, 4, 6]);
  assert.deepEqual(stats.pauses, [0.2, 1.5, 6]);
  assert.equal(stats.fillers, 1);
  assert.equal(stats.repeats, 1);
  assert.equal(stats.abandoned, 0);
  assert.equal(stats.questions, 1);
  assert.deepEqual(stats.ending, {
    words: 6,
    question: false,
    closer: true,
    gapBefore: 6,
  });
  assert.deepEqual(stats.labels, { leave: 1, finished: 1 });
});

test("abandoned sentences are an open utterance followed by a fresh capital", () => {
  const stats = sessionStats(
    {
      segments: [
        { text: "I was going to say that we", start: 0, end: 2, isFinal: true },
        { text: "Actually no, scrap that.", start: 2.5, end: 4, isFinal: true },
        { text: "and then more", start: 4.5, end: 5, isFinal: true },
      ],
    },
    null,
  );
  assert.equal(stats.abandoned, 1);
  assert.deepEqual(stats.labels, {});
});

test("styleSheet aggregates sessions into rates and distributions", () => {
  const one = sessionStats(fixture, labels);
  const style = styleSheet([one, one]);
  assert.equal(style.sessions, 2);
  assert.deepEqual(style.session, {
    meanSeconds: 15,
    meanUtterances: 4,
    meanWords: 20,
    wordsPerMinute: 80,
  });
  assert.equal(style.wordsPerUtterance.count, 8);
  assert.equal(style.wordsPerRun.median, 6);
  assert.equal(style.pauses.shareUnderOneSecond, 0.33);
  assert.equal(style.pauses.perSessionOverOneSecond, 2);
  assert.equal(style.pauses.perSessionOverFiveSeconds, 1);
  assert.equal(style.pauses.overOneSecond.min, 1.5);
  assert.equal(style.fillersPer100Words, 5);
  assert.equal(style.restartsPer100Words, 5);
  assert.equal(style.questionsPerUtterance, 0.25);
  assert.deepEqual(style.endings, {
    meanWords: 6,
    questionShare: 0,
    closerShare: 1,
    meanGapBefore: 6,
  });
  assert.deepEqual(style.labelsPerSession, { leave: 1, finished: 1 });
  assert.throws(() => styleSheet([]), /no sessions/);
});

test("measure reads a recordings directory and main writes the sheet", async (t) => {
  const dir = tempDir(t);
  writeFileSync(join(dir, "a.json"), JSON.stringify(fixture));
  writeFileSync(join(dir, "a.labels.json"), JSON.stringify(labels));
  writeFileSync(join(dir, "a.labels.proposed.json"), "{}");
  writeFileSync(join(dir, "b.json"), JSON.stringify(fixture));
  const listed = listRecordings(dir);
  assert.deepEqual(
    listed.map((r) => [r.name, r.labels !== null]),
    [
      ["a", true],
      ["b", false],
    ],
  );
  const style = measure(dir);
  assert.equal(style.sessions, 2);
  assert.deepEqual(style.labelsPerSession, { leave: 0.5, finished: 0.5 });
  const out = join(dir, "nested", "style.json");
  assert.equal(await main(["--recordings", dir, "--out", out]), 0);
  assert.ok(existsSync(out));
  assert.deepEqual(JSON.parse(readFileSync(out, "utf8")), style);
  assert.throws(() => measure(tempDir(t)), /no recordings/);
});
