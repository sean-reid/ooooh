import { env, SELF } from "cloudflare:test";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { charge, checkBudget, checkDeviceRate } from "../src/budget";
import { HttpError } from "../src/http";
import { decideBody, fakeUpstream, jevReply, type FakeUpstream } from "./upstream";

const today = new Date().toISOString().slice(0, 10);

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  SELF.fetch(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

beforeEach(async () => {
  const keys = await env.BUDGET.list();
  await Promise.all(keys.keys.map((k) => env.BUDGET.delete(k.name)));
});

describe("budget", () => {
  it("keeps the default cap when the var is not a positive number", async () => {
    await charge(env, "jev", 20_000_000);
    for (const bad of ["abc", "", "-5", "NaN"]) {
      const err = await checkBudget({ ...env, JEV_DAILY_TOKENS: bad }, "jev").catch((e) => e);
      expect(err, bad).toBeInstanceOf(HttpError);
      expect(err.status, bad).toBe(503);
    }
    await expect(
      checkBudget({ ...env, JEV_DAILY_TOKENS: "30000000" }, "jev"),
    ).resolves.toBeUndefined();
  });

  it("adds charges and refuses at the daily cap with a retry time", async () => {
    await charge(env, "jev", 1200);
    await charge(env, "jev", 800);
    expect(await env.BUDGET.get(`budget:jev:${today}`)).toBe("2000");
    await expect(checkBudget(env, "jev")).resolves.toBeUndefined();

    await charge(env, "jev", 20_000_000);
    const err = await checkBudget(env, "jev").catch((e) => e);
    expect(err).toBeInstanceOf(HttpError);
    expect(err.status).toBe(503);
    expect(err.body.provider).toBe("jev");
    expect(err.body.retryAfter).toBeGreaterThan(0);
    expect(err.body.retryAfter).toBeLessThanOrEqual(24 * 3600);
  });

  it("ignores non-positive charges", async () => {
    await charge(env, "anthropic", 0);
    await charge(env, "anthropic", -5);
    expect(await env.BUDGET.get(`budget:anthropic:${today}`)).toBeNull();
  });

  it("limits one device per minute and leaves others alone", async () => {
    const now = new Date("2026-10-25T10:00:30Z");
    const minute = Math.floor(now.getTime() / 60_000);
    await env.BUDGET.put(`rate:a:${minute}`, "59");
    await checkDeviceRate("a", env, now);
    const err = await checkDeviceRate("a", env, now).catch((e) => e);
    expect(err.status).toBe(429);
    expect(err.body.retryAfter).toBe(30);
    await expect(checkDeviceRate("b", env, now)).resolves.toBeUndefined();
  });
});

describe("guarded routes", () => {
  let upstream: FakeUpstream;
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("charges Jev input tokens from the response", async () => {
    upstream = fakeUpstream([{ body: { ...jevReply, usage: { input_tokens: 1211 } } }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const res = await post("/v1/decide", decideBody, { "x-device": "charge" });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { usage: { jevInputTokens: number } };
    expect(body.usage.jevInputTokens).toBe(1211);
    expect(await env.BUDGET.get(`budget:jev:${today}`)).toBe("1211");
    expect(upstream.pending()).toBe(0);
  });

  it("refuses before calling upstream once the cap is reached", async () => {
    await charge(env, "jev", 20_000_000);
    upstream = fakeUpstream([]);
    vi.stubGlobal("fetch", upstream.fetch);
    const res = await post("/v1/decide", decideBody, { "x-device": "capped" });
    expect(res.status).toBe(503);
    expect(res.headers.get("retry-after")).toMatch(/^\d+$/);
    expect(((await res.json()) as { error: string }).error).toBe("budget");
  });

  it("returns 429 once a device has used its minute", async () => {
    const minute = Math.floor(Date.now() / 60_000);
    await env.BUDGET.put(`rate:busy:${minute}`, "59");
    upstream = fakeUpstream([{ body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    expect((await post("/v1/decide", decideBody, { "x-device": "busy" })).status).toBe(200);
    const res = await post("/v1/decide", decideBody, { "x-device": "busy" });
    expect(res.status).toBe(429);
    expect(upstream.pending()).toBe(0);
  });
});
