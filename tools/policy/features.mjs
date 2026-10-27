/** Seconds since the last prompt is capped here, and reads as the cap before the first prompt. */
export const sincePromptCap = 300;

export const cueNames = [
  "hangingQuestion",
  "trailsOff",
  "unnamedDecision",
  "contradictsEarlier",
  "repeatsPoint",
];

export const featureNames = [
  ...cueNames,
  "goodMoment",
  "seemsFinished",
  "momentum",
  "articulation",
  "pauseLength",
  "speechDensity",
  "logSeconds",
  "logSincePrompt",
  "promptsSoFar",
  "wordsSoFar",
];

export const requiredColumns = [
  "fixture",
  "at",
  "pauseLength",
  "speechDensity",
  "promptsSoFar",
  "secondsSincePrompt",
  "wordsSoFar",
  "goodMoment",
  ...cueNames,
  "momentum",
  "articulation",
  "seemsFinished",
  "decision",
  "label",
];

/** Throws naming the columns the CSV lacks, so an older eval build fails loudly. */
export function checkColumns(columns) {
  const missing = requiredColumns.filter((name) => !columns.includes(name));
  if (missing.length)
    throw new Error(`the CSV lacks columns: ${missing.join(", ")}`);
}

const number = (text) =>
  text === "" || text === undefined ? null : Number(text);

/** The feature vector in `featureNames` order. A cue Jev left out reads as 0. */
export function featureVector(row) {
  const since = number(row.secondsSincePrompt);
  return [
    ...cueNames.map((name) => number(row[name]) ?? 0),
    number(row.goodMoment),
    number(row.seemsFinished),
    number(row.momentum),
    number(row.articulation),
    number(row.pauseLength),
    number(row.speechDensity),
    Math.log(1 + number(row.at)),
    Math.log(1 + Math.min(since ?? sincePromptCap, sincePromptCap)),
    number(row.promptsSoFar),
    number(row.wordsSoFar),
  ];
}

export const isSpeak = (row) => row.label === "speak";
export const isLeave = (row) => row.label === "leave";

/** Whether the shipped governor decided to prompt at this check. */
export const baselineSpeaks = (row) => row.decision.startsWith("prompt:");

/** Session names in the order they first appear. */
export const sessions = (rows) => [...new Set(rows.map((row) => row.fixture))];
