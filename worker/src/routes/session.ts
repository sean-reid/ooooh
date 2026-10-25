import { entitlement } from "../entitlement";
import { envNumber, json, readBody } from "../http";
import { num, obj } from "../validate";

export const freeSessionsPerMonth = (env: Env) => envNumber(env.FREE_SESSIONS_PER_MONTH, 3);
export const freePromptMinutes = (env: Env) => envNumber(env.FREE_PROMPT_MINUTES, 20);

const month = (now: Date) => now.toISOString().slice(0, 7);
const keepSeconds = 62 * 24 * 3600;

export const sessionsKey = (device: string, now: Date) => `sessions:${device}:${month(now)}`;
export const minutesKey = (device: string, now: Date) => `minutes:${device}:${month(now)}`;

const read = async (kv: KVNamespace, key: string) => Number((await kv.get(key)) ?? 0);

/** Decides at the start whether this session is free, and counts it then. */
export async function startSession(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  if ((await entitlement(device, env, now)) === "paid") return json({ allowed: true, free: false });
  const key = sessionsKey(device, now);
  const used = await read(env.BUDGET, key);
  const limit = freeSessionsPerMonth(env);
  if (used >= limit) return json({ allowed: false, reason: "free-exhausted" });
  await env.BUDGET.put(key, String(used + 1), { expirationTtl: keepSeconds });
  return json({
    allowed: true,
    free: true,
    remainingFree: limit - used - 1,
    promptMinutes: freePromptMinutes(env),
  });
}

const endBody = obj({ minutes: num });

export async function endSession(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { minutes } = await readBody(request, endBody);
  const key = minutesKey(device, now);
  const used = await read(env.BUDGET, key);
  await env.BUDGET.put(key, String(used + Math.max(0, minutes)), { expirationTtl: keepSeconds });
  return new Response(null, { status: 204 });
}
