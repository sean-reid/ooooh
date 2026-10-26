import Anthropic from "@anthropic-ai/sdk";
import { HttpError, retryAfterFrom } from "./http";

export const models = {
  compact: "claude-haiku-5-5",
  phrase: "claude-sonnet-5-5",
  notes: "claude-opus-5-5",
} as const;

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
  throw new HttpError(500, { error: "missing secret", name: "ANTHROPIC_API_KEY" });
};

export const anthropicClient = (cred: Credential, options: { timeout?: number } = {}) =>
  new Anthropic({
    ...(cred.kind === "token" ? { authToken: cred.authToken } : { apiKey: cred.apiKey }),
    defaultHeaders: cred.betas.length ? { "anthropic-beta": cred.betas.join(",") } : {},
    maxRetries: 2,
    timeout: options.timeout ?? 30_000,
  });

const unavailable = (retryAfter: number) =>
  new HttpError(503, { error: "anthropic unavailable", retryAfter });

const isAbort = (e: unknown) =>
  e instanceof Anthropic.APIUserAbortError ||
  (e instanceof DOMException && (e.name === "TimeoutError" || e.name === "AbortError"));

export const upstreamError = (e: unknown): never => {
  if (isAbort(e)) throw unavailable(1);
  if (e instanceof Anthropic.RateLimitError) {
    throw unavailable(retryAfterFrom(e.headers?.get("retry-after")));
  }
  if (e instanceof Anthropic.APIError) {
    throw new HttpError(502, { error: "anthropic", status: e.status, detail: e.message });
  }
  throw e;
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
