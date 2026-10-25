// The kinds the eval scores, in the schema's order, with the key that sets
// each one in the labeler and the meaning shown on hover.
export const KINDS = [
  {
    kind: "clarify",
    key: "c",
    meaning:
      "A question in the pause after this utterance would help pin down a vague or tangled point.",
  },
  {
    kind: "deepen",
    key: "d",
    meaning:
      "A question in the pause after this utterance would open up something worth going further into.",
  },
  {
    kind: "reflect",
    key: "r",
    meaning:
      "Hearing this back in their own words during the pause after it would help the speaker.",
  },
  {
    kind: "decide",
    key: "e",
    meaning:
      "The speaker is weighing options; a question in the pause after this utterance could land a decision.",
  },
  {
    kind: "summarize",
    key: "s",
    meaning:
      "The speaker has covered a lot; a short recap in the pause after this utterance would help.",
  },
  {
    kind: "challenge",
    key: "h",
    meaning:
      "This utterance makes a claim or assumption that deserves a gentle test in the pause after it.",
  },
  {
    kind: "finished",
    key: "f",
    meaning: "The pause after this utterance is the real end of the session.",
  },
  {
    kind: "leave",
    key: "l",
    meaning:
      "The pause after this utterance is long and productive; any prompt in it is an intrusion.",
  },
  {
    kind: "recall",
    key: "q",
    meaning:
      "The speaker asks the app to repeat or remind them of something said earlier.",
  },
  {
    kind: "wrapUp",
    key: "w",
    meaning: "The speaker tells the app to finish, stop, or produce the notes.",
  },
];

export const CLEAR_KEY = "x";

const byKey = new Map(KINDS.map((entry) => [entry.key, entry.kind]));

// A kind for a label key, null for the clear key, undefined for any other.
export function kindForKey(key) {
  if (key === CLEAR_KEY) return null;
  return byKey.get(key);
}

// The name the eval pairs with <name>.labels.json in a corpus directory.
export const fixtureBaseName = (fileName) =>
  fileName.replace(/(\.fixture)?\.json$/, "");

export const finalSegments = (fixture) =>
  fixture.segments.filter((segment) => segment.isFinal);

// The labels file the eval reads: utterance index, end time, kind.
export function buildLabels(fixtureName, finals, labels) {
  return {
    fixture: fixtureName,
    labels: [...labels.entries()]
      .sort((a, b) => a[0] - b[0])
      .map(([utterance, kind]) => ({
        utterance,
        at: finals[utterance].end,
        kind,
      })),
  };
}

export const labelsFromFile = (data) =>
  new Map(data.labels.map((entry) => [entry.utterance, entry.kind]));

// [kind, count] pairs in KINDS order, kinds with no labels left out.
export function countByKind(labels) {
  const counts = new Map();
  for (const kind of labels.values())
    counts.set(kind, (counts.get(kind) ?? 0) + 1);
  return KINDS.filter(({ kind }) => counts.has(kind)).map(({ kind }) => [
    kind,
    counts.get(kind),
  ]);
}
