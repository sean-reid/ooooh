import { SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("worker", () => {
  it("reports health", async () => {
    const res = await SELF.fetch("https://ooooh.test/health");
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ ok: true });
  });

  it("serves the governor config with a version", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/config");
    expect(res.status).toBe(200);
    const body = (await res.json()) as { version: number; floor: { min: number; max: number } };
    expect(body.version).toBe(2);
    expect(body.floor).toEqual({ min: 30, max: 120 });
  });

  it("rejects writes and unknown paths", async () => {
    expect((await SELF.fetch("https://ooooh.test/v1/config", { method: "POST" })).status).toBe(405);
    expect((await SELF.fetch("https://ooooh.test/nope")).status).toBe(404);
  });
});

describe("request guards", () => {
  it("rejects a body over 256 KiB", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/decide", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ state: {}, pad: "x".repeat(256 * 1024) }),
    });
    expect(res.status).toBe(413);
  });

  it("rejects a body that is not json", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/decide", { method: "POST", body: "{" });
    expect(res.status).toBe(422);
  });
});
