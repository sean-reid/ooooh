import { models } from "../../worker/src/models.ts";
import {
  exemplars,
  phraseEffort,
  phraseRules,
  phraseSystem,
  phraseUserMessage,
} from "../../worker/src/phrasing.ts";

export { exemplars };

export const variants = {
  shipping: {
    model: models.phrase,
    system: phraseSystem,
    effort: phraseEffort,
  },
  bare: {
    model: models.phrase,
    system: phraseRules,
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
