import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
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

const here = dirname(fileURLToPath(import.meta.url));
const readJSON = (file) =>
  JSON.parse(readFileSync(resolve(here, file), "utf8"));
const schema = readJSON("../../fixtures/synthetic/scripts/script.schema.json");
const schemaKinds = schema.properties.utterances.items.properties.label.enum;

test("the picker offers exactly the schema's kinds, in its order", () => {
  assert.deepEqual(
    KINDS.map((entry) => entry.kind),
    schemaKinds,
  );
  for (const entry of KINDS) assert.ok(entry.meaning.length > 20, entry.kind);
});

test("one lowercase key per kind, none shared with clear", () => {
  const expected = {
    c: "clarify",
    d: "deepen",
    r: "reflect",
    e: "decide",
    s: "summarize",
    h: "challenge",
    f: "finished",
    l: "leave",
    q: "recall",
    w: "wrapUp",
  };
  assert.deepEqual(
    Object.fromEntries(KINDS.map((entry) => [entry.key, entry.kind])),
    expected,
  );
  assert.equal(new Set(KINDS.map((entry) => entry.key)).size, KINDS.length);
  assert.equal(CLEAR_KEY, "x");
  assert.ok(!(CLEAR_KEY in expected));
  assert.equal(kindForKey("c"), "clarify");
  assert.equal(kindForKey("x"), null);
  assert.equal(kindForKey("z"), undefined);
  assert.equal(kindForKey("C"), undefined);
});

test("export rebuilds the committed labels file from its own load", () => {
  const fixture = readJSON(
    "../../fixtures/synthetic/estimate/decision.fixture.json",
  );
  const file = readJSON(
    "../../fixtures/synthetic/estimate/decision.labels.json",
  );
  const finals = finalSegments(fixture);
  const labels = labelsFromFile(file);
  const out = buildLabels("decision", finals, labels);
  assert.deepEqual(out, file);
  assert.deepEqual(Object.keys(out), ["fixture", "labels"]);
  for (const entry of out.labels) {
    assert.deepEqual(Object.keys(entry), ["utterance", "at", "kind"]);
    assert.ok(schemaKinds.includes(entry.kind), entry.kind);
    assert.equal(entry.at, finals[entry.utterance].end);
  }
});

test("the export name pairs with the fixture the way the eval does", () => {
  assert.equal(fixtureBaseName("decision.fixture.json"), "decision");
  assert.equal(fixtureBaseName("2026-10-25-083012.json"), "2026-10-25-083012");
  assert.equal(fixtureBaseName("notes.fixture.v2.json"), "notes.fixture.v2");
});

test("export sorts by utterance and counts per kind follow the picker order", () => {
  const finals = [
    { text: "a", start: 0, end: 1, isFinal: true },
    { text: "b", start: 2, end: 3, isFinal: true },
    { text: "c", start: 4, end: 5, isFinal: true },
  ];
  const labels = new Map([
    [2, "finished"],
    [0, "clarify"],
    [1, "clarify"],
  ]);
  const out = buildLabels("tiny", finals, labels);
  assert.deepEqual(
    out.labels.map((entry) => entry.utterance),
    [0, 1, 2],
  );
  assert.deepEqual(countByKind(labels), [
    ["clarify", 2],
    ["finished", 1],
  ]);
  assert.deepEqual(countByKind(new Map()), []);
});
