import type { DeviceHandler } from "./attest/device";
import { envNumber, HttpError } from "./http";
import { checkSession, readCount, type Window } from "./session";

export type Provider = "jev" | "anthropic" | "elevenlabs";

const dailyLimit: Record<Provider, (env: Env) => number> = {
  jev: (env) => envNumber(env.JEV_DAILY_TOKENS, 20_000_000),
  anthropic: (env) => envNumber(env.ANTHROPIC_DAILY_TOKENS, 2_000_000),
  elevenlabs: (env) => envNumber(env.ELEVENLABS_DAILY_CHARACTERS, 20_000),
};

const day = (now: Date) => now.toISOString().slice(0, 10);

const secondsToMidnight = (now: Date) => {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
};

/** Refuses when today's spend for the provider has reached its cap. */
export async function checkBudget(env: Env, provider: Provider, now = new Date()): Promise<void> {
  const limit = dailyLimit[provider](env);
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

/** Adds what a response cost. KV is eventually consistent, so the cap is approximate by design. */
export async function charge(
  env: Env,
  provider: Provider,
  amount: number,
  now = new Date(),
): Promise<void> {
  if (!(amount > 0)) return;
  const key = `budget:${provider}:${day(now)}`;
  const used = await readCount(env.BUDGET, key);
  await env.BUDGET.put(key, String(used + amount), { expirationTtl: 3 * 24 * 3600 });
}

/** One device may make this many provider-backed requests a minute. */
export async function checkDeviceRate(device: string, env: Env, now = new Date()): Promise<void> {
  const limit = envNumber(env.DEVICE_MINUTE_REQUESTS, 60);
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
  await env.BUDGET.put(key, String(used + 1), { expirationTtl: 120 });
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
    await checkDeviceRate(device, env);
    await checkBudget(env, provider);
    return handler(request, env);
  };
