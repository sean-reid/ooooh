import Anthropic from "@anthropic-ai/sdk";
import { HttpError } from "./http";

export const models = { compact: "claude-haiku-5-5", phrase: "claude-sonnet-5-5" } as const;

export const anthropicClient = (apiKey: string) =>
  new Anthropic({ apiKey, maxRetries: 2, timeout: 30_000 });

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
