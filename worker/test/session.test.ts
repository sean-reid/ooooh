import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { HttpError } from "../src/http";
import { endSession } from "../src/routes/session";
import { sessionTtlSeconds, type SessionRecord } from "../src/session";
import { jsonRequest, openSession } from "./request";
import { buyMonth, makeStoreChain, type StoreChain } from "./storekit";
import { post, wipeKV } from "./workers";

let chain: StoreChain;

const start = (device: string, now: Date, overrides: Partial<Env> = {}) =>
  openSession({ ...env, ...overrides }, device, now).then(
    (res) => res.json() as Promise<Record<string, unknown>>,
  );

const end = (device: string, minutes: number, now: Date) =>
  endSession(jsonRequest("/v1/session/end", { minutes }), env, device, now);

const session = (device: string) => env.BUDGET.get<SessionRecord>(`session:${device}`, "json");

const minutesLater = (from: Date, minutes: number) => new Date(from.getTime() + minutes * 60_000);

beforeAll(async () => {
  chain = await makeStoreChain();
});

beforeEach(wipeKV);

describe("free sessions", () => {
  const october = new Date("2026-10-25T10:00:00Z");

  it("grants three a month with 20 prompt minutes each, then refuses", async () => {
    expect(await start("a", october)).toEqual({
      allowed: true,
      free: true,
      remainingFree: 2,
      promptMinutes: 20,
    });
    await end("a", 5, minutesLater(october, 5));
    expect(await start("a", october)).toMatchObject({ remainingFree: 1 });
    await end("a", 5, minutesLater(october, 5));
    expect(await start("a", october)).toMatchObject({ remainingFree: 0 });
    await end("a", 5, minutesLater(october, 5));
    expect(await start("a", october)).toEqual({ allowed: false, reason: "free-exhausted" });
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBe("3");
    expect(await session("a")).toBeNull();
    expect(await start("b", october)).toMatchObject({ allowed: true, remainingFree: 2 });
  });

  it("opens a record with the start time, the allowance, and a four hour expiry", async () => {
    await start("a", october);
    expect(await session("a")).toEqual({
      startedAt: october.getTime(),
      free: true,
      remainingFree: 2,
      promptMinutes: 20,
    });
    const listed = (await env.BUDGET.list({ prefix: "session:a" })).keys[0];
    const expiresIn = listed.expiration! - Date.now() / 1000;
    expect(expiresIn).toBeGreaterThan(sessionTtlSeconds - 60);
    expect(expiresIn).toBeLessThanOrEqual(sessionTtlSeconds);
  });

  it("answers a second start the same way without counting it again", async () => {
    const first = await start("a", october);
    expect(await start("a", minutesLater(october, 1))).toEqual(first);
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBe("1");
    expect((await session("a"))?.startedAt).toBe(october.getTime());
  });

  it("starts over at the UTC month boundary", async () => {
    const lastMinute = new Date("2026-10-31T23:59:59Z");
    for (let i = 0; i < 3; i++) {
      await start("a", lastMinute);
      await end("a", 0, lastMinute);
    }
    expect(await start("a", lastMinute)).toMatchObject({ allowed: false });
    expect(await start("a", new Date("2026-11-01T00:00:00Z"))).toMatchObject({
      allowed: true,
      remainingFree: 2,
    });
    expect(await env.BUDGET.get("sessions:a:2026-11")).toBe("1");
  });

  it("reads the limits from vars", async () => {
    const overrides = { FREE_SESSIONS_PER_MONTH: "1", FREE_PROMPT_MINUTES: "5" };
    expect(await start("a", october, overrides)).toMatchObject({
      remainingFree: 0,
      promptMinutes: 5,
    });
    await end("a", 1, october);
    expect(await start("a", october, overrides)).toMatchObject({ allowed: false });
  });

  it("opens a session for a paid device without counting it", async () => {
    expect((await buyMonth("a", chain, env, october.getTime())).status).toBe(200);
    expect(await start("a", october)).toEqual({ allowed: true, free: false });
    expect(await session("a")).toEqual({ startedAt: october.getTime(), free: false });
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBeNull();
    await end("a", 30, minutesLater(october, 30));
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBe("30");
    expect(await start("a", october)).toEqual({ allowed: true, free: false });
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBeNull();
  });

  it("records nothing for an end with no session open", async () => {
    expect((await end("a", 12, october)).status).toBe(204);
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBeNull();
  });

  it("adds the minutes an end reports and closes the session", async () => {
    await start("a", october);
    expect((await end("a", 12, minutesLater(october, 12))).status).toBe(204);
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBe("12");
    expect(await session("a")).toBeNull();
    await start("a", october);
    await end("a", 7.5, minutesLater(october, 8));
    await start("a", october);
    await end("a", -3, minutesLater(october, 1));
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBe("19.5");
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBe("3");
  });

  it("clamps a long figure to the wall clock, and a clock behind the start to one minute", async () => {
    await start("a", october);
    await end("a", 1e308, minutesLater(october, 5));
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBe("6");
    await start("b", october);
    await end("b", 10, minutesLater(october, -5));
    expect(await env.BUDGET.get("minutes:b:2026-10")).toBe("1");
  });

  it("rejects an end without minutes", async () => {
    const err = await endSession(jsonRequest("/v1/session/end", "{}"), env, "a", october).catch(
      (e) => e,
    );
    expect(err).toBeInstanceOf(HttpError);
    expect(err.status).toBe(422);
  });

  it("answers over the route with the caller's label when attestation is off", async () => {
    const res = await post("/v1/session/start", {}, { "x-device": "sim" });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ allowed: true, remainingFree: 2 });
    expect(await env.BUDGET.get(`sessions:sim:${new Date().toISOString().slice(0, 7)}`)).toBe("1");
    expect((await session("sim"))?.free).toBe(true);
    const ended = await post("/v1/session/end", { minutes: 0.5 }, { "x-device": "sim" });
    expect(ended.status).toBe(204);
    expect(await session("sim")).toBeNull();
  });
});
