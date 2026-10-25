import { envNumber } from "./http";

export const freeSessionsPerMonth = (env: Env) => envNumber(env.FREE_SESSIONS_PER_MONTH, 3);
export const freePromptMinutes = (env: Env) => envNumber(env.FREE_PROMPT_MINUTES, 20);

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
