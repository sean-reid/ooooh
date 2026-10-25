import { env, SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";
import { entitlement } from "../src/entitlement";
import { HttpError } from "../src/http";
import { endSession, startSession } from "../src/routes/session";

const start = (device: string, now: Date, overrides: Partial<Env> = {}) =>
  startSession(
    new Request("https://ooooh.test/v1/session/start", { method: "POST" }),
    { ...env, ...overrides },
    device,
    now,
  ).then((res) => res.json() as Promise<Record<string, unknown>>);

const end = (device: string, minutes: number, now: Date) =>
  endSession(
    new Request("https://ooooh.test/v1/session/end", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ minutes }),
    }),
    env,
    device,
    now,
  );

beforeEach(async () => {
  const keys = await env.BUDGET.list();
  await Promise.all(keys.keys.map((k) => env.BUDGET.delete(k.name)));
});

describe("free sessions", () => {
  const october = new Date("2026-10-25T10:00:00Z");

  it("grants three a month with 20 prompt minutes each, then refuses", async () => {
    expect(await start("a", october)).toEqual({
      allowed: true,
      free: true,
      remainingFree: 2,
      promptMinutes: 20,
    });
    expect(await start("a", october)).toMatchObject({ remainingFree: 1 });
    expect(await start("a", october)).toMatchObject({ remainingFree: 0 });
    expect(await start("a", october)).toEqual({ allowed: false, reason: "free-exhausted" });
    expect(await env.BUDGET.get("sessions:a:2026-10")).toBe("3");
    expect(await start("b", october)).toMatchObject({ allowed: true, remainingFree: 2 });
  });

  it("starts over at the UTC month boundary", async () => {
    const lastMinute = new Date("2026-10-31T23:59:59Z");
    for (let i = 0; i < 3; i++) await start("a", lastMinute);
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
    expect(await start("a", october, overrides)).toMatchObject({ allowed: false });
  });

  it("adds up the minutes a session reports at its end", async () => {
    expect((await end("a", 12, october)).status).toBe(204);
    expect((await end("a", 7.5, october)).status).toBe(204);
    expect((await end("a", -3, october)).status).toBe(204);
    expect(await env.BUDGET.get("minutes:a:2026-10")).toBe("19.5");
  });

  it("rejects an end without minutes", async () => {
    const err = await endSession(
      new Request("https://ooooh.test/v1/session/end", { method: "POST", body: "{}" }),
      env,
      "a",
      october,
    ).catch((e) => e);
    expect(err).toBeInstanceOf(HttpError);
    expect(err.status).toBe(422);
  });

  it("answers over the route with the caller's label when attestation is off", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/session/start", {
      method: "POST",
      headers: { "x-device": "sim" },
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ allowed: true, remainingFree: 2 });
    expect(await env.BUDGET.get(`sessions:sim:${new Date().toISOString().slice(0, 7)}`)).toBe("1");
  });
});

describe("entitlement", () => {
  it("is free for every device until StoreKit lands", async () => {
    expect(await entitlement("any", env)).toBe("free");
  });
});
