import { entitlement } from "./entitlement";
import { HttpError } from "./http";
import { settings } from "./settings";

const month = (now: Date) => now.toISOString().slice(0, 7);

export const sessionsKey = (device: string, now: Date) => `sessions:${device}:${month(now)}`;
export const minutesKey = (device: string, now: Date) => `minutes:${device}:${month(now)}`;
export const sessionKey = (device: string) => `session:${device}`;

/** The session a device has open: when it started, in ms, and what the start answered. */
export type SessionRecord =
  | { startedAt: number; free: false }
  | { startedAt: number; free: true; remainingFree: number; promptMinutes: number };

/** A session nobody ends closes on its own after this long. */
export const sessionTtlSeconds = 4 * 3600;

export const openSession = (device: string, env: Env) =>
  env.BUDGET.get<SessionRecord>(sessionKey(device), "json");

export const readCount = async (kv: KVNamespace, key: string) => Number((await kv.get(key)) ?? 0);

/** What a free session's prompt minutes cover: prompts stop at the allowance, the rest runs while the session is open. */
export type Window = "prompt-minutes" | "whole-session";

export const noSession = (reason: string) => new HttpError(402, { error: "no-session", reason });

/** Refuses a device with no open session and no paid record, and a prompt once a free session's minutes are spent. */
export async function checkSession(
  device: string,
  env: Env,
  window: Window,
  now = new Date(),
): Promise<void> {
  const session = await openSession(device, env);
  if (!session) {
    if ((await entitlement(device, env, now)) === "paid") return;
    const used = await readCount(env.BUDGET, sessionsKey(device, now));
    throw noSession(used >= settings(env).freeSessionsPerMonth ? "free-used" : "not-started");
  }
  if (
    session.free &&
    window === "prompt-minutes" &&
    now.getTime() - session.startedAt >= session.promptMinutes * 60_000
  ) {
    throw noSession("minutes-used");
  }
}
