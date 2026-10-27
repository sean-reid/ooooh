import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { MODEL, outputSchema, system, userMessage } from "./proposal.mjs";

// Thinking counts against this too; a long session needs the room before the JSON closes.
export const MAX_TOKENS = 16_000;
export const DEADLINE_MS = 180_000;

// The SDK is installed for the Worker; the tool loads it from there.
export async function loadSDK() {
  const require = createRequire(
    new URL("../../worker/package.json", import.meta.url),
  );
  const dir = dirname(require.resolve("@anthropic-ai/sdk"));
  const { default: Anthropic } = await import(
    pathToFileURL(join(dir, "index.mjs")).href
  );
  return Anthropic;
}

export const requestParams = (finals) => ({
  model: MODEL,
  max_tokens: MAX_TOKENS,
  betas: ["server-side-fallback-2026-07-01"],
  fallbacks: "default",
  thinking: { type: "adaptive" },
  system,
  messages: [{ role: "user", content: userMessage(finals) }],
  output_config: {
    effort: "high",
    format: { type: "json_schema", schema: outputSchema },
  },
});

// The model's JSON for one fixture, parsed but not yet checked, with the usage it cost.
export async function askModel(finals, apiKey, Anthropic) {
  Anthropic ??= await loadSDK();
  const client = new Anthropic({ apiKey, maxRetries: 2, timeout: DEADLINE_MS });
  const response = await client.beta.messages.create(requestParams(finals));
  if (response.stop_reason === "max_tokens")
    throw new Error(`the answer was cut off at ${MAX_TOKENS} tokens`);
  if (response.stop_reason === "refusal")
    throw new Error(
      `the model refused: ${JSON.stringify(response.stop_details)}`,
    );
  const text = response.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("");
  return {
    parsed: JSON.parse(text),
    usage: response.usage,
    model: response.model,
  };
}
