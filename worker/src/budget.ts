import type { DeviceHandler } from "./attest/device";
import { counterFor } from "./attest/record";
import { deferred } from "./defer";
import { HttpError } from "./http";
import { checkSession, type Window } from "./session";
import { settings } from "./settings";

export type Provider = "jev" | "anthropic" | "elevenlabs";

const day = (now: Date) => now.toISOString().slice(0, 10);

const secondsToMidnight = (now: Date) => {
  const next = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + 1);
  return Math.max(1, Math.ceil((next - now.getTime()) / 1000));
};

export const budgetFor = (env: Env, provider: Provider) => env.PROVIDER_BUDGET.getByName(provider);

/** Refuses when today's spend for the provider has reached its cap. */
export async function checkBudget(env: Env, provider: Provider, now = new Date()): Promise<void> {
  const limit = settings(env).dailyLimit[provider];
  const used = await budgetFor(env, provider).spent(day(now));
  if (used >= limit) {
    const retryAfter = secondsToMidnight(now);
    throw new HttpError(
      503,
      { error: "budget", provider, used, limit, retryAfter },
      { "retry-after": String(retryAfter) },
    );
  }
}

/** Refuses when the device's spend on the provider today has reached its cap, until midnight UTC. */
export async function checkDeviceBudget(
  device: string,
  env: Env,
  provider: Provider,
  now = new Date(),
): Promise<void> {
  const limit = settings(env).deviceDailyLimit[provider];
  const used = await counterFor(env, device).spent(provider, day(now));
  if (used >= limit) {
    const retryAfter = secondsToMidnight(now);
    throw new HttpError(
      429,
      { error: "device-budget", provider, used, limit, retryAfter },
      { "retry-after": String(retryAfter) },
    );
  }
}

/** Adds what a response cost to the provider's day and the device's, without holding the response on the writes. */
export function charge(
  env: Env,
  device: string,
  provider: Provider,
  amount: number,
  now = new Date(),
) {
  if (!(amount > 0)) return Promise.resolve();
  const today = day(now);
  return deferred(`charge ${provider} ${today}`, () =>
    Promise.all([
      budgetFor(env, provider).add(today, amount),
      counterFor(env, device).spend(provider, today, amount),
    ]),
  );
}

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
  device: string,
  model: string,
  usage: { input_tokens: number; output_tokens: number },
  now = new Date(),
) =>
  charge(
    env,
    device,
    "anthropic",
    modelWeight(model) * (usage.input_tokens + usage.output_tokens),
    now,
  );

/** One device may make this many provider-backed requests a minute, counted in its DeviceCounter. */
export async function checkDeviceRate(device: string, env: Env, now = new Date()): Promise<void> {
  const limit = settings(env).deviceMinuteRequests;
  const minute = Math.floor(now.getTime() / 60_000);
  if (await counterFor(env, device).hit(minute, limit)) return;
  const retryAfter = 60 - Math.floor((now.getTime() % 60_000) / 1000);
  throw new HttpError(
    429,
    { error: "rate", limit, retryAfter },
    { "retry-after": String(retryAfter) },
  );
}

/** Wraps a route so the session, device rate, and both budget checks run before any upstream call. */
export const guarded =
  (provider: Provider, handler: DeviceHandler, window: Window = "prompt-minutes"): DeviceHandler =>
  async (request, env, device) => {
    await checkSession(device, env, window);
    await Promise.all([
      checkDeviceRate(device, env),
      checkDeviceBudget(device, env, provider),
      checkBudget(env, provider),
    ]);
    return handler(request, env, device);
  };
