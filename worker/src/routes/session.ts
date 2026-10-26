import { entitlement } from "../entitlement";
import { json, readBody } from "../http";
import {
  minutesKey,
  openSession,
  readCount,
  sessionKey,
  sessionsKey,
  sessionTtlSeconds,
  type SessionRecord,
} from "../session";
import { settings } from "../settings";
import { num, obj } from "../validate";

const keepSeconds = 62 * 24 * 3600;

const allowance = (session: SessionRecord) =>
  session.free
    ? {
        allowed: true,
        free: true,
        remainingFree: session.remainingFree,
        promptMinutes: session.promptMinutes,
      }
    : { allowed: true, free: false };

const open = (env: Env, device: string, session: SessionRecord) =>
  env.BUDGET.put(sessionKey(device), JSON.stringify(session), {
    expirationTtl: sessionTtlSeconds,
  });

/** Opens the device's session and counts a free one against the month; a start while one is open answers the same allowance. */
export async function startSession(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const current = await openSession(device, env);
  if (current) return json(allowance(current));
  const startedAt = now.getTime();
  if ((await entitlement(device, env, now)) === "paid") {
    const session: SessionRecord = { startedAt, free: false };
    await open(env, device, session);
    return json(allowance(session));
  }
  const key = sessionsKey(device, now);
  const used = await readCount(env.BUDGET, key);
  const { freeSessionsPerMonth: limit, freePromptMinutes: promptMinutes } = settings(env);
  if (used >= limit) return json({ allowed: false, reason: "free-exhausted" });
  const session: SessionRecord = {
    startedAt,
    free: true,
    remainingFree: limit - used - 1,
    promptMinutes,
  };
  await open(env, device, session);
  await env.BUDGET.put(key, String(used + 1), { expirationTtl: keepSeconds });
  return json(allowance(session));
}

const endBody = obj({ minutes: num });

/** Closes the open session and adds its minutes to the month, clamped to its own length plus one. */
export async function endSession(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { minutes } = await readBody(request, endBody);
  const session = await openSession(device, env);
  if (!session) return new Response(null, { status: 204 });
  const wallClock = Math.max(0, now.getTime() - session.startedAt) / 60_000;
  const counted = Math.min(Math.max(0, minutes), wallClock + 1);
  const key = minutesKey(device, now);
  const used = await readCount(env.BUDGET, key);
  await env.BUDGET.put(key, String(used + counted), { expirationTtl: keepSeconds });
  await env.BUDGET.delete(sessionKey(device));
  return new Response(null, { status: 204 });
}
