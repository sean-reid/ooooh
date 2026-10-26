import { counterFor } from "./attest/record";
import { deferred } from "./defer";
import { entitlement } from "./entitlement";
import { HttpError } from "./http";
import { settings } from "./settings";

export const month = (now: Date) => now.toISOString().slice(0, 7);

export const minutesKey = (device: string, now: Date) => `minutes:${device}:${month(now)}`;
export const sessionKey = (device: string) => `session:${device}`;

/** A free session as the start opened it; `pending` holds until the device shows it started. */
export interface FreeSession {
  id: string;
  startedAt: number;
  free: true;
  remainingFree: number;
  promptMinutes: number;
  pending?: boolean;
}

/** The session a device has open: when it started, in ms, and what the start answered. */
export type SessionRecord = { startedAt: number; free: false } | FreeSession;

/** A session nobody ends closes on its own after this long. */
export const sessionTtlSeconds = 4 * 3600;

export const openSession = (device: string, env: Env) =>
  env.BUDGET.get<SessionRecord>(sessionKey(device), "json");

/** Writes the record to run out `sessionTtlSeconds` after its start; KV takes nothing under a minute. */
export const writeSession = (env: Env, device: string, session: SessionRecord, now: Date) =>
  env.BUDGET.put(sessionKey(device), JSON.stringify(session), {
    expirationTtl: Math.max(
      60,
      sessionTtlSeconds - Math.floor((now.getTime() - session.startedAt) / 1000),
    ),
  });

/** Free sessions the device has had this month, counted in its DeviceCounter. */
export const sessionsUsed = (device: string, env: Env, now: Date) =>
  counterFor(env, device).sessions(month(now));

/** Lands the session's count against the month of its start; a repeat changes nothing. */
export const countSession = (device: string, session: FreeSession, env: Env) =>
  counterFor(env, device).countSession(month(new Date(session.startedAt)), session.id);

/** Counts the session and clears `pending`, so later calls skip the counter. */
async function confirmSession(device: string, session: FreeSession, env: Env, now: Date) {
  await countSession(device, session, env);
  await writeSession(env, device, { ...session, pending: false }, now);
}

/** What a free session's prompt minutes cover: prompts stop at the allowance, the rest runs while the session is open. */
export type Window = "prompt-minutes" | "whole-session";

export const noSession = (reason: string) => new HttpError(402, { error: "no-session", reason });

/**
 * Refuses a device with no open session and no paid record, and a prompt once a free session's
 * minutes are spent. The first call under a pending session is what counts it.
 */
export async function checkSession(
  device: string,
  env: Env,
  window: Window,
  now = new Date(),
): Promise<void> {
  const session = await openSession(device, env);
  if (!session) {
    if ((await entitlement(device, env, now)) === "paid") return;
    const used = await sessionsUsed(device, env, now);
    throw noSession(used >= settings(env).freeSessionsPerMonth ? "free-used" : "not-started");
  }
  if (session.free && session.pending) {
    await deferred(`confirm ${sessionKey(device)}`, () =>
      confirmSession(device, session, env, now),
    );
  }
  if (
    session.free &&
    window === "prompt-minutes" &&
    now.getTime() - session.startedAt >= session.promptMinutes * 60_000
  ) {
    throw noSession("minutes-used");
  }
}
