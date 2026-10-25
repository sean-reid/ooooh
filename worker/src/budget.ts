import { HttpError } from "./http";

export type Provider = "jev" | "anthropic" | "elevenlabs";

const dailyLimit: Record<Provider, (env: Env) => number> = {
  jev: (env) => Number(env.JEV_DAILY_TOKENS ?? 20_000_000),
  anthropic: (env) => Number(env.ANTHROPIC_DAILY_TOKENS ?? 2_000_000),
  elevenlabs: (env) => Number(env.ELEVENLABS_DAILY_CHARACTERS ?? 20_000),
};

const day = (now: Date) => now.toISOString().slice(0, 10);

const secondsToMidnight = (now: Date) => {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
};

const read = async (kv: KVNamespace, key: string) => Number((await kv.get(key)) ?? 0);

/** Refuses when today's spend for the provider has reached its cap. */
export async function checkBudget(env: Env, provider: Provider, now = new Date()): Promise<void> {
  const limit = dailyLimit[provider](env);
  const used = await read(env.BUDGET, `budget:${provider}:${day(now)}`);
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
  const used = await read(env.BUDGET, key);
  await env.BUDGET.put(key, String(used + amount), { expirationTtl: 3 * 24 * 3600 });
}

/** One device may make this many provider-backed requests a minute. */
export async function checkDeviceRate(request: Request, env: Env, now = new Date()): Promise<void> {
  const limit = Number(env.DEVICE_MINUTE_REQUESTS ?? 60);
  const device =
    request.headers.get("x-device") ?? request.headers.get("cf-connecting-ip") ?? "unknown";
  const minute = Math.floor(now.getTime() / 60_000);
  const key = `rate:${device}:${minute}`;
  const used = await read(env.BUDGET, key);
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

/** Wraps a route so the device and budget checks run before any upstream call. */
export const guarded =
  (provider: Provider, handler: (request: Request, env: Env) => Promise<Response> | Response) =>
  async (request: Request, env: Env) => {
    await checkDeviceRate(request, env);
    await checkBudget(env, provider);
    return handler(request, env);
  };
