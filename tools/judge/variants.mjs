import { models } from "../../worker/src/models.ts";
import {
  phraseEffort,
  phraseSystem,
  phraseUserMessage,
} from "../../worker/src/phrasing.ts";

export const exemplars = {
  clarify: "When you say it is slow, which step is the slow one?",
  deepen: "What makes Friday the deadline that counts?",
  reflect: "Three times now, slow was fine.",
  decide: "So is it the small team, or is that still open?",
  summarize: "Estimation, cost, and who sits in the room, three threads open.",
  challenge: "What would it take for the cheaper path to be wrong?",
};

const exemplarBlock = `Examples, one per kind, from other sessions:
${Object.entries(exemplars)
  .map(([kind, line]) => `- ${kind}: ${line}`)
  .join("\n")}`;

export const variants = {
  shipping: {
    model: models.phrase,
    system: phraseSystem,
    effort: phraseEffort,
  },
  exemplars: {
    model: models.phrase,
    system: `${phraseSystem}\n\n${exemplarBlock}`,
    effort: phraseEffort,
  },
  opus: {
    model: "claude-opus-5-5",
    system: phraseSystem,
    effort: "medium",
    thinking: { type: "adaptive" },
  },
};

export const variantNames = Object.keys(variants);

/** The request the Worker's phrase route sends, with the variant's model, prompt, and effort in place. */
export const phraseRequest = (name, record) => {
  const variant = variants[name];
  if (!variant)
    throw new Error(
      `unknown variant ${name}; one of ${variantNames.join(", ")}`,
    );
  return {
    model: variant.model,
    max_tokens: 1024,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: variant.system,
    output_config: { effort: variant.effort },
    ...(variant.thinking ? { thinking: variant.thinking } : {}),
    messages: [{ role: "user", content: phraseUserMessage(record) }],
  };
};
