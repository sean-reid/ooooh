import { SELF } from "cloudflare:test";
import { beforeEach, describe, expect, it } from "vitest";

describe("worker", () => {
  it("reports health", async () => {
    const res = await SELF.fetch("https://ooooh.test/health");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { ok: boolean; version: string | null };
    expect(body.ok).toBe(true);
    expect(typeof body.version).toBe("string");
  });

  it("serves the governor config with a version", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/config");
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      version: number;
      floor: { min: number; max: number };
      warmUp: number;
      armingDelay: number;
      silenceChecks: number[];
    };
    expect(body.version).toBe(5);
    expect(body.floor).toEqual({ min: 30, max: 120 });
    expect(body.warmUp).toBe(45);
    expect(body.armingDelay).toBe(1.5);
    expect(body.silenceChecks).toEqual([5, 11, 20]);
    expect(body).not.toHaveProperty("minCheckInterval");
  });

  it("rejects writes and unknown paths", async () => {
    expect((await SELF.fetch("https://ooooh.test/v1/config", { method: "POST" })).status).toBe(405);
    expect((await SELF.fetch("https://ooooh.test/nope")).status).toBe(404);
  });
});

describe("request guards", () => {
  beforeEach(async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/session/start", {
      method: "POST",
      headers: { "x-device": "guards" },
    });
    expect(res.status).toBe(200);
  });

  it("rejects a body over 256 KiB", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/decide", {
      method: "POST",
      headers: { "content-type": "application/json", "x-device": "guards" },
      body: JSON.stringify({ state: {}, pad: "x".repeat(256 * 1024) }),
    });
    expect(res.status).toBe(413);
  });

  it("rejects a body that is not json", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/decide", {
      method: "POST",
      headers: { "x-device": "guards" },
      body: "{",
    });
    expect(res.status).toBe(422);
  });
});
