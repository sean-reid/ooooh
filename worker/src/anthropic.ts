import Anthropic from "@anthropic-ai/sdk";
import { chargeModel } from "./budget";
import { HttpError, missingSecret, unavailable, upstreamFailure } from "./http";
import { ValidationError } from "./validate";

export { models } from "./models";

const oauthBeta = "oauth-2025-04-20";

export type Credential =
  | { kind: "token"; authToken: string; betas: [typeof oauthBeta] }
  | { kind: "key"; apiKey: string; betas: [] };

// A short-lived OAuth token wins over a stored key. Tokens need the oauth beta on every request.
export const credential = (env: Env): Credential => {
  if (env.ANTHROPIC_AUTH_TOKEN) {
    return { kind: "token", authToken: env.ANTHROPIC_AUTH_TOKEN, betas: [oauthBeta] };
  }
  if (env.ANTHROPIC_API_KEY) return { kind: "key", apiKey: env.ANTHROPIC_API_KEY, betas: [] };
  throw missingSecret("ANTHROPIC_API_KEY");
};

export const anthropicClient = (cred: Credential, options: { timeout?: number } = {}) =>
  new Anthropic({
    ...(cred.kind === "token" ? { authToken: cred.authToken } : { apiKey: cred.apiKey }),
    defaultHeaders: cred.betas.length ? { "anthropic-beta": cred.betas.join(",") } : {},
    maxRetries: 2,
    timeout: options.timeout ?? 30_000,
  });

const isAbort = (e: unknown) =>
  e instanceof Anthropic.APIUserAbortError ||
  (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError"));

export const upstreamError = (e: unknown): never => {
  if (isAbort(e)) throw unavailable("anthropic", 1);
  if (e instanceof Anthropic.APIError) {
    throw upstreamFailure("anthropic", e.status, e.headers?.get("retry-after") ?? null, e.message);
  }
  throw e;
};

/** The refusal's category and explanation go to the log; the phone only learns that no line came. */
export const refused = (message: { stop_details: unknown }) => {
  console.error("anthropic refused", JSON.stringify(message.stop_details));
  return new HttpError(502, { error: "anthropic refused" });
};

/** Runs one call under `ms`, body read included; the SDK's own timeout stops at the headers. */
export const within = <T>(ms: number, call: (signal: AbortSignal) => Promise<T>): Promise<T> => {
  const signal = AbortSignal.timeout(ms);
  const expired = new Promise<never>((_, reject) =>
    signal.addEventListener("abort", () => reject(signal.reason)),
  );
  return Promise.race([call(signal), expired]);
};

/** Yields upstream events and aborts the stream when the gap between two of them passes `stallMs`. */
export async function* paced<T>(events: AsyncIterable<T>, stallMs: number): AsyncGenerator<T> {
  const iterator = events[Symbol.asyncIterator]();
  let finished = false;
  try {
    for (;;) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const stalled = new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new DOMException("anthropic stalled", "TimeoutError")),
          stallMs,
        );
      });
      let next: IteratorResult<T>;
      try {
        next = await Promise.race([iterator.next(), stalled]);
      } finally {
        clearTimeout(timer);
      }
      if (next.done) {
        finished = true;
        return;
      }
      yield next.value;
    }
  } finally {
    if (!finished) await iterator.return?.().catch(() => undefined);
  }
}

export const textOf = (content: Array<{ type: string; text?: string }>) =>
  content
    .filter((b) => b.type === "text")
    .map((b) => b.text ?? "")
    .join("");

type StructuredReply = {
  model: string;
  stop_reason: string | null;
  stop_details: unknown;
  content: Array<{ type: string; text?: string }>;
  usage: { input_tokens: number; output_tokens: number };
};

/**
 * Charges a structured-output reply and reads its JSON through `read`. A reply cut off at
 * `maxTokens`, refused, not JSON, or outside the shape is a 502 under `error` that still counts
 * against the day.
 */
export async function structured<T>(
  env: Env,
  response: StructuredReply,
  maxTokens: number,
  error: string,
  read: (parsed: unknown) => T,
) {
  await chargeModel(env, response.model, response.usage);
  const text = textOf(response.content);
  // The answer itself stays out of the log; its shape and size are enough to see what went wrong.
  const rejected = (reason: string) =>
    console.error(
      "anthropic rejected",
      response.model,
      error,
      reason,
      `stop=${response.stop_reason} chars=${text.length} out=${response.usage.output_tokens}`,
    );
  if (response.stop_reason === "max_tokens") {
    rejected("truncated");
    throw new HttpError(502, { error: "anthropic truncated", maxTokens });
  }
  if (response.stop_reason === "refusal") throw refused(response);
  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch {
    rejected("not json");
    throw new HttpError(502, { error, field: "", expected: "json" });
  }
  try {
    const usage = {
      inputTokens: response.usage.input_tokens,
      outputTokens: response.usage.output_tokens,
    };
    return { value: read(parsed), usage };
  } catch (e) {
    if (e instanceof ValidationError) {
      rejected(`${e.field} expected ${e.expected}`);
      throw new HttpError(502, { error, field: e.field, expected: e.expected });
    }
    throw e;
  }
}
