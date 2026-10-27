import Anthropic from "@anthropic-ai/sdk";

/** The SDK reads the key from the environment; nothing here prints or stores it. */
export const client = () => new Anthropic({ maxRetries: 2, timeout: 60_000 });

export const concurrency = 3;

export const textOf = (content) =>
  content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("");

export const usageOf = (message) => ({
  input: message.usage.input_tokens,
  output: message.usage.output_tokens,
  cacheRead: message.usage.cache_read_input_tokens ?? 0,
  cacheWrite: message.usage.cache_creation_input_tokens ?? 0,
});

/** One non-streaming call with its wall time, body read included. */
export async function timed(call) {
  const started = performance.now();
  const message = await call();
  if (message.stop_reason === "refusal") {
    throw new Error(`refused: ${JSON.stringify(message.stop_details)}`);
  }
  if (message.stop_reason === "max_tokens")
    throw new Error("cut off at max_tokens");
  return { message, latencyMs: Math.round(performance.now() - started) };
}
