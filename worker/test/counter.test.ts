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
});
