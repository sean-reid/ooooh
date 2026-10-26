import { createExecutionContext, env, SELF, waitOnExecutionContext } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { charge, chargeModel, checkBudget, checkDeviceRate, modelWeight } from "../src/budget";
import { HttpError } from "../src/http";
import worker from "../src/index";
import { startSession } from "../src/routes/session";
import { checkSession } from "../src/session";
import { MemoryKV } from "./kv";
import { buyMonth, makeStoreChain, type StoreChain } from "./storekit";
import {
  audioBytes,
  compactBody,
  decideBody,
  fakeUpstream,
  haikuReply,
  jevReply,
  notesBody,
  opusReply,
  phraseBody,
  sonnetReply,
  speakBody,
  type FakeUpstream,
  type Reply,
} from "./upstream";

const today = new Date().toISOString().slice(0, 10);

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  SELF.fetch(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

const request = (path: string, body: unknown) =>
  new Request(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-device": "direct" },
    body: JSON.stringify(body),
  });

const start = (device: string) => post("/v1/session/start", {}, { "x-device": device });
const end = (device: string, minutes: number) =>
  post("/v1/session/end", { minutes }, { "x-device": device });

const refused = async (res: Response, reason: string) => {
  expect(res.status).toBe(402);
  expect(await res.json()).toEqual({ error: "no-session", reason });
};

let chain: StoreChain;
beforeAll(async () => {
  chain = await makeStoreChain();
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

  it("weighs tokens by model so the cap is Opus-equivalent, and 700,000 is the default", async () => {
    expect(modelWeight("claude-opus-5-5")).toBe(1);
    expect(modelWeight("claude-sonnet-5-5")).toBe(0.5);
    expect(modelWeight("claude-haiku-5-5")).toBe(0.025);
    expect(modelWeight("claude-opus-5-5-20260601")).toBe(1);
    expect(modelWeight("something-new")).toBe(1);

    const usage = { input_tokens: 3000, output_tokens: 1000 };
    await chargeModel(env, "claude-haiku-5-5", usage);
    expect(await env.BUDGET.get(`budget:anthropic:${today}`)).toBe("100");
    await chargeModel(env, "claude-sonnet-5-5", usage);
    expect(await env.BUDGET.get(`budget:anthropic:${today}`)).toBe("2100");
    await chargeModel(env, "claude-opus-5-5", usage);
    expect(await env.BUDGET.get(`budget:anthropic:${today}`)).toBe("6100");

    await charge(env, "anthropic", 700_000 - 6100 - 1);
    await expect(
      checkBudget({ ...env, ANTHROPIC_DAILY_TOKENS: "" }, "anthropic"),
    ).resolves.toBeUndefined();
    await chargeModel(env, "claude-haiku-5-5", { input_tokens: 40, output_tokens: 0 });
    const err = await checkBudget({ ...env, ANTHROPIC_DAILY_TOKENS: "" }, "anthropic").catch(
      (e) => e,
    );
    expect(err.status).toBe(503);
    expect(err.body).toMatchObject({ error: "budget", provider: "anthropic", limit: 700_000 });
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
    await start("charge");
    const res = await post("/v1/decide", decideBody, { "x-device": "charge" });
    expect(res.status).toBe(200);
    const body = (await res.json()) as { usage: { jevInputTokens: number } };
    expect(body.usage.jevInputTokens).toBe(1211);
    await expect.poll(() => env.BUDGET.get(`budget:jev:${today}`)).toBe("1211");
    expect(upstream.pending()).toBe(0);
  });

  it("answers before the charge lands and settles it in waitUntil", async () => {
    upstream = fakeUpstream([{ body: { ...jevReply, usage: { input_tokens: 1211 } } }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const kv = new MemoryKV();
    let pending = 0;
    kv.put = async (key, value) => {
      if (key.startsWith("budget:")) pending += 1;
      kv.store.set(key, value);
    };
    const testEnv = { ...env, BUDGET: kv as unknown as KVNamespace };
    const ctx = createExecutionContext();
    await worker.fetch(request("/v1/session/start", {}), testEnv, ctx);
    const res = await worker.fetch(request("/v1/decide", decideBody), testEnv, ctx);
    expect(res.status).toBe(200);
    await waitOnExecutionContext(ctx);
    expect(pending).toBe(1);
    expect(await kv.get(`budget:jev:${today}`)).toBe("1211");
  });

  it("logs a charge the store refuses and keeps the 200", async () => {
    upstream = fakeUpstream([{ body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const kv = new MemoryKV();
    kv.put = async (key, value) => {
      if (key.startsWith("budget:")) throw new Error("KV PUT failed: 429 Too Many Requests");
      kv.store.set(key, value);
    };
    const logged = vi.spyOn(console, "error").mockImplementation(() => undefined);
    const testEnv = { ...env, BUDGET: kv as unknown as KVNamespace };
    const ctx = createExecutionContext();
    await worker.fetch(request("/v1/session/start", {}), testEnv, ctx);
    const res = await worker.fetch(request("/v1/decide", decideBody), testEnv, ctx);
    expect(res.status).toBe(200);
    await waitOnExecutionContext(ctx);
    expect(logged).toHaveBeenCalledWith(`charge budget:jev:${today}`, expect.any(Error));
    logged.mockRestore();
  });

  it("refuses before calling upstream once the cap is reached", async () => {
    await charge(env, "jev", 20_000_000);
    upstream = fakeUpstream([]);
    vi.stubGlobal("fetch", upstream.fetch);
    await start("capped");
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
    await start("busy");
    expect((await post("/v1/decide", decideBody, { "x-device": "busy" })).status).toBe(200);
    const res = await post("/v1/decide", decideBody, { "x-device": "busy" });
    expect(res.status).toBe(429);
    expect(upstream.pending()).toBe(0);
  });
});

describe("session gate", () => {
  let upstream: FakeUpstream;
  const expectUpstream = (...replies: Reply[]) => {
    upstream = fakeUpstream(replies);
    vi.stubGlobal("fetch", upstream.fetch);
  };
  const device = { "x-device": "gated" };
  const audioReply = (): Reply => ({ body: audioBytes, headers: { "content-type": "audio/mpeg" } });
  afterEach(() => {
    expect(upstream.pending()).toBe(0);
    vi.unstubAllGlobals();
  });

  it("lets a provider call through once the device has started a session", async () => {
    expectUpstream({ body: jevReply });
    expect(await (await start("gated")).json()).toMatchObject({ allowed: true, free: true });
    expect((await post("/v1/decide", decideBody, device)).status).toBe(200);
  });

  it("answers 402 not-started with no session, before the rate counter moves", async () => {
    expectUpstream();
    await refused(await post("/v1/decide", decideBody, device), "not-started");
    await refused(await post("/v1/notes", notesBody, device), "not-started");
    const minute = Math.floor(Date.now() / 60_000);
    expect(await env.BUDGET.get(`rate:gated:${minute}`)).toBeNull();
  });

  it("refuses the fourth free start of the month, and the calls after it, with free-used", async () => {
    expectUpstream({ body: jevReply });
    for (let i = 0; i < 3; i++) {
      expect(await (await start("gated")).json()).toMatchObject({ allowed: true });
      expect((await end("gated", 1)).status).toBe(204);
    }
    expect(await (await start("gated")).json()).toEqual({
      allowed: false,
      reason: "free-exhausted",
    });
    await refused(await post("/v1/decide", decideBody, device), "free-used");
    await refused(await post("/v1/compact", compactBody, device), "free-used");
    expect((await post("/v1/decide", decideBody, { "x-device": "other" })).status).toBe(402);
    await start("other");
    expect((await post("/v1/decide", decideBody, { "x-device": "other" })).status).toBe(200);
  });

  it("never refuses a paid device, whose starts count nothing", async () => {
    expectUpstream({ body: jevReply }, { body: jevReply });
    expect((await buyMonth("gated", chain, env)).status).toBe(200);
    expect((await post("/v1/decide", decideBody, device)).status).toBe(200);
    for (let i = 0; i < 4; i++) {
      expect(await (await start("gated")).json()).toEqual({ allowed: true, free: false });
    }
    expect(
      await env.BUDGET.get(`sessions:gated:${new Date().toISOString().slice(0, 7)}`),
    ).toBeNull();
    expect((await post("/v1/decide", decideBody, device)).status).toBe(200);
  });

  it("stops prompts at the allowance and keeps the whole-session routes running", async () => {
    expectUpstream();
    const opened = new Date("2026-10-25T10:00:00Z");
    const request = new Request("https://ooooh.test/v1/session/start", { method: "POST" });
    await startSession(request, env, "gated", opened);
    const at = (minutes: number) => new Date(opened.getTime() + minutes * 60_000);
    await expect(checkSession("gated", env, "prompt-minutes", at(19.99))).resolves.toBeUndefined();
    const err = await checkSession("gated", env, "prompt-minutes", at(20)).catch((e) => e);
    expect(err).toBeInstanceOf(HttpError);
    expect(err.status).toBe(402);
    expect(err.body).toEqual({ error: "no-session", reason: "minutes-used" });
    await expect(checkSession("gated", env, "whole-session", at(180))).resolves.toBeUndefined();

    await buyMonth("paid", chain, env, opened.getTime());
    await startSession(request, env, "paid", opened);
    await expect(checkSession("paid", env, "prompt-minutes", at(180))).resolves.toBeUndefined();
  });

  it("answers minutes-used on decide, phrase, and speak, and still serves compact and notes", async () => {
    expectUpstream({ body: haikuReply }, { body: opusReply() });
    const longAgo = new Date("2026-01-01T00:00:00Z");
    await startSession(
      new Request("https://ooooh.test/v1/session/start", { method: "POST" }),
      env,
      "gated",
      longAgo,
    );
    await refused(await post("/v1/decide", decideBody, device), "minutes-used");
    await refused(await post("/v1/phrase", phraseBody, device), "minutes-used");
    await refused(await post("/v1/speak", speakBody, device), "minutes-used");
    expect((await post("/v1/compact", compactBody, device)).status).toBe(200);
    expect((await post("/v1/notes", notesBody, device)).status).toBe(200);
    expect((await end("gated", 20)).status).toBe(204);
    expectUpstream({ body: sonnetReply("Which part is unclear?") }, audioReply());
    await start("gated");
    expect((await post("/v1/phrase", phraseBody, device)).status).toBe(200);
    expect((await post("/v1/speak", speakBody, device)).status).toBe(200);
  });
});
