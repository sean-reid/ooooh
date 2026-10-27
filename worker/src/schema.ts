import {
  array,
  bool,
  num,
  obj,
  oneOf,
  optional,
  text,
  withDefault,
  type Validator,
} from "./validate";

export const interventionKinds = [
  "clarify",
  "deepen",
  "reflect",
  "decide",
  "summarize",
  "challenge",
] as const;
export type InterventionKind = (typeof interventionKinds)[number];

export const modes = ["exploring", "converging", "stuck", "finishing"] as const;
export const listNames = ["mainIdeas", "openQuestions", "uncertainties", "decisions"] as const;

/** The phone keeps 6 recent finals and 3 lines said; the caps take twice each. */
export const windows = { recent: 12, said: 12, compactBatch: 60 } as const;

/** One final is one utterance; the longest in the synthetic sessions runs 345 characters. */
const segmentText = text(1_000);
/** The phone holds 12 items a list and 6 recent topics; the caps take twice each. */
const items = (inner: Validator<Item>) => withDefault(array(inner, 24), []);
const sentence = text(500);

export const segment = obj({ text: segmentText, start: num, end: num });
export type Segment = ReturnType<typeof segment>;

const item = obj({ id: text(64), text: sentence, resolved: withDefault(bool, false) });
type Item = ReturnType<typeof item>;

export const intervention = obj({
  kind: oneOf(interventionKinds),
  text: sentence,
  at: num,
  takenUp: optional(bool),
});
export type Intervention = ReturnType<typeof intervention>;

export const compactState = obj({
  currentThread: withDefault(text(1_000), ""),
  mainIdeas: items(item),
  openQuestions: items(item),
  uncertainties: items(item),
  decisions: items(item),
  recentTopics: withDefault(array(text(100), 12), []),
  lastIntervention: optional(intervention),
  mode: withDefault(oneOf(modes), "exploring"),
});
export type CompactState = ReturnType<typeof compactState>;

export const existingIds = (state: CompactState) =>
  [...state.mainIdeas, ...state.openQuestions, ...state.uncertainties, ...state.decisions].map(
    (i) => i.id,
  );
