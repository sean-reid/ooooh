import type { CompactState, Intervention, InterventionKind, Segment } from "./schema";

// No value imports: Node loads this file as is, so tools/judge measures the prompt the route sends.

export const wordLimit = 15;

export const phraseEffort = "low";

export const transcriptLines = (segments: Segment[]) =>
  segments.map((s) => `[${s.start.toFixed(0)}s] ${s.text}`).join("\n");

export const kindGuide: Record<InterventionKind, string> = {
  clarify: "name the one unclear thing they said and ask which sense of it they mean.",
  deepen: "name the thing they just said and ask for the reason behind it, or its cost.",
  reflect: "hand back one phrase they said, word for word, and nothing else.",
  decide: "name the two options they weighed, in their words, and ask which one it is.",
  summarize: "name the two or three threads they have open, in their words, as one sentence.",
  challenge: "name the one earlier claim this one cuts against and ask if it still holds.",
};

/** Frames the prompt forbids by name; `stockFrame` is the same list as a check on a line. */
export const forbiddenFrames = [
  "how does that sit",
  "what makes that important",
  "what sits underneath",
];

export const stockFrame =
  /\bhow does\b.{0,40}?\bsit\b|\bwhat makes\b.{0,40}?\bimportant\b|\bwhat sits (under|underneath|beneath)\b/i;

export const exemplars: Record<InterventionKind, string> = {
  clarify: "When you say the build is slow, slow how?",
  deepen: "Why does Friday count, and not the Monday after?",
  reflect: "Slow was fine, three times now.",
  decide: "The small team or the big one, which did you land on?",
  summarize: "Estimation, the cost, and who sits in the room, three threads open.",
  challenge: "Earlier the cheaper path was safe, now it is the risk?",
};

export const phraseRules = `You write the one sentence a quiet thinking companion says to someone thinking aloud. They are not talking to you. They are working something out and you occasionally hand them a question.

Rules, all of them hard:
- One sentence, under ${wordLimit} words, the named thing counted in. Most land under 12.
- A question, or a reflection of the speaker's own words back to them.
- Never advice. Never praise. Never the word "I".
- Plain words the speaker used, not new vocabulary.
- The sentence names one thing the speaker said in their last two utterances, in their words; decide and summarize name two or three. A line that is only about "that" or "it" fails.
- Never these frames, or anything shaped like them: ${forbiddenFrames.map((f) => `"${f}"`).join(", ")}.
- No preamble, no quotes, no markdown. Output the sentence and nothing else.

Kinds, and what each question is for:
${Object.entries(kindGuide)
  .map(([kind, guide]) => `- ${kind}: ${guide}`)
  .join("\n")}`;

export const phraseSystem = `${phraseRules}

Examples, one per kind, from other sessions. They show the standard, not a template: every noun in them came from that session, and yours come from this one.
${Object.entries(exemplars)
  .map(([kind, line]) => `- ${kind}: ${line}`)
  .join("\n")}`;

export type PhraseInput = {
  kind: InterventionKind;
  state: CompactState;
  recent: Segment[];
  lastIntervention?: Intervention;
};

export const phraseUserMessage = (input: PhraseInput) => {
  const last = input.lastIntervention ?? input.state.lastIntervention;
  const lines = [
    `Kind: ${input.kind}`,
    `Mode: ${input.state.mode}`,
    `Current thread: ${input.state.currentThread || "(none yet)"}`,
    `Open questions: ${input.state.openQuestions.map((q) => q.text).join(" | ") || "none"}`,
    `Main ideas: ${input.state.mainIdeas.map((q) => q.text).join(" | ") || "none"}`,
    `Uncertainties: ${input.state.uncertainties.map((q) => q.text).join(" | ") || "none"}`,
    last ? `Last thing said to them (${last.kind}): ${last.text}` : "Nothing said to them yet.",
    `Recent words, the last two are the ones to name from:\n${transcriptLines(input.recent)}`,
  ];
  return lines.join("\n");
};

export const wordCount = (text: string) => text.trim().split(/\s+/).filter(Boolean).length;

export function truncateToLimit(text: string, limit = wordLimit): string {
  const words = text.trim().split(/\s+/).filter(Boolean);
  const head = words.slice(0, limit);
  for (let i = head.length - 1; i >= 0; i--) {
    if (/[.?!]["')]?$/.test(head[i])) return head.slice(0, i + 1).join(" ");
  }
  return head.join(" ").replace(/[,;:\s]+$/, "") + ".";
}
