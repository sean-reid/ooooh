import type { CompactState, Intervention, InterventionKind, Segment } from "./schema";

// No value imports: Node loads this file as is, so tools/judge measures the prompt the route sends.

export const wordLimit = 15;

export const phraseEffort = "low";

export const transcriptLines = (segments: Segment[]) =>
  segments.map((s) => `[${s.start.toFixed(0)}s] ${s.text}`).join("\n");

export const kindGuide: Record<InterventionKind, string> = {
  clarify: "ask which part of the unclear thing they mean.",
  deepen: "ask what sits under the thing they just said.",
  reflect: "hand back the phrase they keep returning to.",
  decide: "ask whether the thing they are weighing is settled.",
  summarize: "name the two or three threads they have open, as one sentence.",
  challenge: "ask what would make their claim wrong.",
};

export const phraseSystem = `You write the one sentence a quiet thinking companion says to someone thinking aloud. They are not talking to you. They are working something out and you occasionally hand them a question.

Rules, all of them hard:
- One sentence, under ${wordLimit} words.
- A question, or a reflection of the speaker's own words back to them.
- Never advice. Never praise. Never the word "I".
- Plain words the speaker used, not new vocabulary.
- No preamble, no quotes, no markdown. Output the sentence and nothing else.

Kinds:
${Object.entries(kindGuide)
  .map(([kind, guide]) => `- ${kind}: ${guide}`)
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
    `Recent words:\n${transcriptLines(input.recent)}`,
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
