import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";

describe("DeviceCounter", () => {
  it("accepts exactly one of many concurrent copies of a counter", async () => {
    const stub = env.DEVICE_COUNTER.getByName("race");
    const results = await Promise.all(Array.from({ length: 20 }, () => stub.advance(7)));
    expect(results.filter(Boolean)).toHaveLength(1);
    expect(await stub.current()).toBe(7);
    expect(await stub.advance(7)).toBe(false);
    expect(await stub.advance(8)).toBe(true);
  });

  it("treats the floor as already seen and lifts the stored value to it", async () => {
    const stub = env.DEVICE_COUNTER.getByName("floor");
    expect(await stub.advance(3, 3)).toBe(false);
    expect(await stub.advance(4, 3)).toBe(true);
    await stub.raise(2);
    expect(await stub.current()).toBe(4);
    await stub.raise(9);
    expect(await stub.current()).toBe(9);
  });

  it("keeps a spend per provider and day, counts every add, and drops the days before", async () => {
    const stub = env.DEVICE_COUNTER.getByName("spend");
    await Promise.all(Array.from({ length: 20 }, () => stub.spend("jev", "2026-10-24", 3)));
    expect(await stub.spent("jev", "2026-10-24")).toBe(60);
    expect(await stub.spent("elevenlabs", "2026-10-24")).toBe(0);
    await stub.spend("elevenlabs", "2026-10-24", 41);
    expect(await stub.spend("jev", "2026-10-25", 7)).toBe(7);
    expect(await stub.spent("jev", "2026-10-24")).toBe(0);
    expect(await stub.spent("elevenlabs", "2026-10-24")).toBe(41);
  });

  it("stamps the time of each accepted assertion and none for a key that passed none", async () => {
    const stub = env.DEVICE_COUNTER.getByName("seen");
    expect(await stub.lastSeen()).toBeUndefined();
    expect(await stub.advance(1, 0, 1_000)).toBe(true);
    expect(await stub.lastSeen()).toBe(1_000);
    expect(await stub.advance(1, 0, 2_000)).toBe(false);
    expect(await stub.lastSeen()).toBe(1_000);
    const before = Date.now();
    expect(await stub.advance(2)).toBe(true);
    const stamped = await stub.lastSeen();
    expect(stamped).toBeGreaterThanOrEqual(before);
    await stub.raise(5);
    expect(await stub.lastSeen()).toBe(stamped);
  });
});
