import { KINDS } from "../labeler/labels.mjs";

export const MODEL = "claude-opus-5-5";

export const kindNames = KINDS.map((entry) => entry.kind);

// What the model returns: at most one label per utterance, each with a reason.
export const outputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["labels"],
  properties: {
    labels: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["utterance", "kind", "reason"],
        properties: {
          utterance: { type: "integer", minimum: 0 },
          kind: { type: "string", enum: kindNames },
          reason: { type: "string" },
        },
      },
    },
  },
};

export const system = `You label a transcript of one person thinking aloud on their own. A quiet listener sits with them and may say one short sentence in a pause, but only when it would help. The labels calibrate that listener, so label the way a thoughtful person would behave, not the way an eager one would.

The transcript is one line per utterance: its index, its start and end time, the pause after it, then the text. For each utterance decide whether the listener should say one short sentence in the pause right after it. Most utterances get no label. A session of thirty utterances usually earns two to five interventions.

The kinds:
${KINDS.map(({ kind, meaning }) => `- ${kind}: ${meaning}`).join("\n")}

Rules:
- One label per utterance at most, placed on the utterance whose pause the sentence would land in.
- leave marks a long pause the speaker is using well; the listener stays quiet there. Mark it when the pause is long and the speaker comes back with the thread moving.
- finished marks the pause where the session has really ended, so the listener may ask whether they are done. Mark the moment the speaker winds up the whole session, not the end of one thread, and leave a false ending unmarked if the speaker comes back with more.
- recall and wrapUp are only for lines where the speaker talks to the listener directly.
- The reason is one short line in plain words, naming what in the text made you choose the kind.

Return the labels sorted by utterance.`;

const clock = (seconds) => {
  const m = Math.floor(seconds / 60);
  const s = (seconds - m * 60).toFixed(3).padStart(6, "0");
  return `${m}:${s}`;
};

export const pauseAfter = (finals, index) =>
  index + 1 < finals.length
    ? finals[index + 1].start - finals[index].end
    : null;

export const pauseText = (finals, index) => {
  const pause = pauseAfter(finals, index);
  return pause == null ? "end" : `pause ${pause.toFixed(1)} s`;
};

export const timeSpan = (segment) =>
  `${clock(segment.start)} to ${clock(segment.end)}`;

// One line per utterance, times and the pause after it included.
export const transcriptLines = (finals) =>
  finals.map(
    (segment, index) =>
      `[${index}] ${timeSpan(segment)}, ${pauseText(finals, index)}: ${segment.text}`,
  );

export const userMessage = (finals) =>
  `Transcript, ${finals.length} utterances:\n${transcriptLines(finals).join("\n")}`;

// The model's JSON checked against the fixture: known kinds, utterances that exist,
// one label per utterance (the first wins), sorted by utterance.
export function readProposal(parsed, finals) {
  if (!parsed || !Array.isArray(parsed.labels))
    throw new Error("the model's answer has no labels array");
  const seen = new Set();
  const out = [];
  for (const entry of parsed.labels) {
    const { utterance, kind, reason } = entry ?? {};
    if (
      !Number.isInteger(utterance) ||
      utterance < 0 ||
      utterance >= finals.length
    )
      throw new Error(
        `label points at utterance ${utterance}, the fixture has ${finals.length}`,
      );
    if (!kindNames.includes(kind))
      throw new Error(
        `label on utterance ${utterance} has unknown kind ${kind}`,
      );
    if (seen.has(utterance)) continue;
    seen.add(utterance);
    out.push({ utterance, kind, reason: String(reason ?? "").trim() });
  }
  return out.sort((a, b) => a.utterance - b.utterance);
}

// The labels file with the reason beside each label; the eval ignores the extra key.
export const buildProposed = (fixtureName, finals, proposal) => ({
  fixture: fixtureName,
  labels: proposal.map(({ utterance, kind, reason }) => ({
    utterance,
    at: finals[utterance].end,
    kind,
    reason,
  })),
});
