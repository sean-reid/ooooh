import { kindGuide, transcriptLines } from "../../worker/src/phrasing.ts";

export const judgeModel = "claude-opus-5-5";
export const judgeMaxTokens = 8000;

export const criteria = {
  ownWords: "uses the speaker's own words",
  oneThing: "lands on the one thing they were circling",
  notAdvice: "is a question or a reflection, not advice or praise",
  fitsKind: "does what the kind calls for",
  welcome: "would be welcome at that moment",
};

export const criterionNames = Object.keys(criteria);

export const judgeSystem = `You score one sentence a quiet thinking companion said to someone thinking aloud. You read the last few lines the speaker said, the kind of sentence that was called for, and the sentence. The speaker was not talking to the companion; they were working something out and the companion handed them one line.

Score the sentence on five criteria, each an integer from 1 to 5.

- ownWords: it ${criteria.ownWords}. 5: every content word is one the speaker used. 3: mostly theirs, with a new word or two. 1: new vocabulary, a paraphrase in someone else's words.
- oneThing: it ${criteria.oneThing}. 5: the thing they kept coming back to. 3: a real thread, but a side one. 1: something they were not talking about, or several things at once.
- notAdvice: it ${criteria.notAdvice}. 5: a question, or their words handed back. 3: a question that carries a suggestion. 1: advice, praise, a verdict, or a new idea.
- fitsKind: it ${criteria.fitsKind}. 5: exactly that move. 3: a related move. 1: a different move.
- welcome: it ${criteria.welcome}. 5: it would help them keep going. 3: harmless, easy to skip. 1: it would interrupt or annoy.

Kinds:
${Object.entries(kindGuide)
  .map(([kind, guide]) => `- ${kind}: ${guide}`)
  .join("\n")}

Return JSON: the five scores under their names, and a note of one sentence on what the line got right or wrong.`;

export const judgeSchema = {
  type: "object",
  properties: Object.fromEntries([
    ...criterionNames.map((name) => [name, { type: "integer" }]),
    ["note", { type: "string" }],
  ]),
  required: [...criterionNames, "note"],
  additionalProperties: false,
};

/** The judge reads the window, the kind, and the line. The variant name never reaches it. */
export const judgeUserMessage = ({ kind, recent }, text) =>
  [
    `Kind: ${kind}`,
    `Recent words:\n${transcriptLines(recent)}`,
    `Sentence: ${text}`,
  ].join("\n\n");

export const judgeRequest = (record, text) => ({
  model: judgeModel,
  max_tokens: judgeMaxTokens,
  thinking: { type: "adaptive" },
  system: judgeSystem,
  output_config: {
    effort: "medium",
    format: { type: "json_schema", schema: judgeSchema },
  },
  messages: [{ role: "user", content: judgeUserMessage(record, text) }],
});

/** Reads the judge's JSON; anything but five integers in 1 to 5 and a note is an error. */
export const parseJudgement = (text) => {
  const parsed = JSON.parse(text);
  const scores = {};
  for (const name of criterionNames) {
    const value = parsed[name];
    if (!Number.isInteger(value) || value < 1 || value > 5) {
      throw new Error(
        `${name}: expected an integer from 1 to 5, got ${JSON.stringify(value)}`,
      );
    }
    scores[name] = value;
  }
  if (typeof parsed.note !== "string")
    throw new Error("note: expected a string");
  return { scores, note: parsed.note };
};
