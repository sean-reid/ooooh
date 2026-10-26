import type { DeviceHandler } from "./attest/device";
import { deferred } from "./defer";
import { HttpError } from "./http";
import { checkSession, readCount, type Window } from "./session";
import { settings } from "./settings";

export type Provider = "jev" | "anthropic" | "elevenlabs";

const day = (now: Date) => now.toISOString().slice(0, 10);

const secondsToMidnight = (now: Date) => {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
};

/** Refuses when today's spend for the provider has reached its cap. */
export async function checkBudget(env: Env, provider: Provider, now = new Date()): Promise<void> {
  const limit = settings(env).dailyLimit[provider];
  const used = await readCount(env.BUDGET, `budget:${provider}:${day(now)}`);
  if (used >= limit) {
    const retryAfter = secondsToMidnight(now);
    throw new HttpError(
      503,
      { error: "budget", provider, used, limit, retryAfter },
      { "retry-after": String(retryAfter) },
    );
  }
}

/**
 * Adds what a response cost without holding the response on the write. KV is eventually
 * consistent and takes one write a second per key, so the cap is approximate by design.
 */
export function charge(env: Env, provider: Provider, amount: number, now = new Date()) {
  if (!(amount > 0)) return Promise.resolve();
  const key = `budget:${provider}:${day(now)}`;
  const write = (pendingCharges.get(key) ?? Promise.resolve()).then(async () => {
    const used = await readCount(env.BUDGET, key);
    await env.BUDGET.put(key, String(used + amount), { expirationTtl: 3 * 24 * 3600 });
  });
  const tail: Promise<void> = write
    .catch(() => undefined)
    .then(() => {
      if (pendingCharges.get(key) === tail) pendingCharges.delete(key);
    });
  pendingCharges.set(key, tail);
  return deferred(`charge ${key}`, () => write);
}

/** Charges on one key run in order within the isolate, so two in one request keep both puts. */
const pendingCharges = new Map<string, Promise<void>>();

/** Each family's list price over Opus's, so the Anthropic cap counts Opus-equivalent tokens. */
const modelWeights: [family: string, weight: number][] = [
  ["haiku", 0.025],
  ["sonnet", 0.5],
  ["opus", 1],
];

/** A model outside the table is charged as Opus, so a fallback never undercounts. */
export const modelWeight = (model: string) =>
  modelWeights.find(([family]) => model.includes(family))?.[1] ?? 1;

export const chargeModel = (
  env: Env,
  model: string,
  usage: { input_tokens: number; output_tokens: number },
  now = new Date(),
) => charge(env, "anthropic", modelWeight(model) * (usage.input_tokens + usage.output_tokens), now);

/**
 * One device may make this many provider-backed requests a minute. The count is a KV read then
 * a put, so it is approximate under concurrency, and a put KV refuses is logged and the request
 * goes on.
 */
export async function checkDeviceRate(device: string, env: Env, now = new Date()): Promise<void> {
  const limit = settings(env).deviceMinuteRequests;
  const minute = Math.floor(now.getTime() / 60_000);
  const key = `rate:${device}:${minute}`;
  const used = await readCount(env.BUDGET, key);
  if (used >= limit) {
    const retryAfter = 60 - Math.floor((now.getTime() % 60_000) / 1000);
    throw new HttpError(
      429,
      { error: "rate", limit, retryAfter },
      { "retry-after": String(retryAfter) },
    );
  }
  await deferred(`rate ${key}`, () =>
    env.BUDGET.put(key, String(used + 1), { expirationTtl: 120 }),
  );
}

/** Wraps a route so the session, device, and budget checks run before any upstream call. */
export const guarded =
  (
    provider: Provider,
    handler: (request: Request, env: Env) => Promise<Response> | Response,
    window: Window = "prompt-minutes",
  ): DeviceHandler =>
  async (request, env, device) => {
    await checkSession(device, env, window);
    await Promise.all([checkDeviceRate(device, env), checkBudget(env, provider)]);
    return handler(request, env);
  };
