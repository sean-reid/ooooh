import { array, bool, num, obj, oneOf, optional, str, withDefault } from "./validate";

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

export const segment = obj({ text: str, start: num, end: num });
export type Segment = ReturnType<typeof segment>;

const item = obj({ id: str, text: str, resolved: withDefault(bool, false) });

export const intervention = obj({
  kind: oneOf(interventionKinds),
  text: str,
  at: num,
  takenUp: optional(bool),
});
export type Intervention = ReturnType<typeof intervention>;

export const compactState = obj({
  currentThread: withDefault(str, ""),
  mainIdeas: withDefault(array(item), []),
  openQuestions: withDefault(array(item), []),
  uncertainties: withDefault(array(item), []),
  decisions: withDefault(array(item), []),
  recentTopics: withDefault(array(str), []),
  lastIntervention: optional(intervention),
  mode: withDefault(oneOf(modes), "exploring"),
});
export type CompactState = ReturnType<typeof compactState>;

export const transcriptLines = (segments: Segment[]) =>
  segments.map((s) => `[${s.start.toFixed(0)}s] ${s.text}`).join("\n");

export const existingIds = (state: CompactState) =>
  [...state.mainIdeas, ...state.openQuestions, ...state.uncertainties, ...state.decisions].map(
    (i) => i.id,
  );
