import Anthropic from "@anthropic-ai/sdk";
import { HttpError } from "./http";

export const models = { compact: "claude-haiku-5-5", phrase: "claude-sonnet-5-5" } as const;

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

export const anthropicClient = (cred: Credential) =>
  new Anthropic({
    ...(cred.kind === "token" ? { authToken: cred.authToken } : { apiKey: cred.apiKey }),
    defaultHeaders: cred.betas.length ? { "anthropic-beta": cred.betas.join(",") } : {},
    maxRetries: 2,
    timeout: 30_000,
  });

export const upstreamError = (e: unknown): never => {
  if (e instanceof Anthropic.RateLimitError) {
    const retryAfter = Number(e.headers?.get("retry-after") ?? 5);
    throw new HttpError(503, { error: "anthropic unavailable", retryAfter });
  }
  if (e instanceof Anthropic.APIError) {
    throw new HttpError(502, { error: "anthropic", status: e.status, detail: e.message });
  }
  throw e;
};

export const textOf = (content: Array<{ type: string; text?: string }>) =>
  content
    .filter((b) => b.type === "text")
    .map((b) => b.text ?? "")
    .join("");
