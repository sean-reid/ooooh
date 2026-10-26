import { entitlement } from "../entitlement";
import { json, readBody } from "../http";
import {
  countSession,
  minutesKey,
  openSession,
  sessionKey,
  sessionsUsed,
  writeSession,
  type SessionRecord,
} from "../session";
import { settings } from "../settings";
import { num, obj } from "../validate";

const keepSeconds = 62 * 24 * 3600;

const readCount = async (kv: KVNamespace, key: string) => Number((await kv.get(key)) ?? 0);

const allowance = (session: SessionRecord) =>
  session.free
    ? {
        allowed: true,
        free: true,
        remainingFree: session.remainingFree,
        promptMinutes: session.promptMinutes,
      }
    : { allowed: true, free: false };

/** Opens the device's session, or answers the open one; a free session counts at its first call or its end. */
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
    await writeSession(env, device, session, now);
    return json(allowance(session));
  }
  const used = await sessionsUsed(device, env, now);
  const { freeSessionsPerMonth: limit, freePromptMinutes: promptMinutes } = settings(env);
  if (used >= limit) return json({ allowed: false, reason: "free-exhausted" });
  const session: SessionRecord = {
    id: crypto.randomUUID(),
    startedAt,
    free: true,
    remainingFree: limit - used - 1,
    promptMinutes,
    pending: true,
  };
  await writeSession(env, device, session, now);
  return json(allowance(session));
}

const endBody = obj({ minutes: num });

/** Closes the open session, counts it if no call did, and adds its minutes, clamped to its length plus one. */
export async function endSession(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { minutes } = await readBody(request, endBody);
  const session = await openSession(device, env);
  if (!session) return new Response(null, { status: 204 });
  if (session.free && session.pending) await countSession(device, session, env);
  const wallClock = Math.max(0, now.getTime() - session.startedAt) / 60_000;
  const counted = Math.min(Math.max(0, minutes), wallClock + 1);
  const key = minutesKey(device, now);
  const used = await readCount(env.BUDGET, key);
  await env.BUDGET.put(key, String(used + counted), { expirationTtl: keepSeconds });
  await env.BUDGET.delete(sessionKey(device));
  return new Response(null, { status: 204 });
}
