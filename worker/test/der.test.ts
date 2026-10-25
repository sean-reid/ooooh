import { describe, expect, it } from "vitest";
import { DerError, readDer } from "../src/x509";

describe("readDer", () => {
  it("refuses a long-form length whose size bytes run past the buffer", () => {
    expect(() => readDer(new Uint8Array([0x30, 0x82, 0x01]))).toThrow(DerError);
  });

  it("reads a long-form length that fits", () => {
    const bytes = new Uint8Array([0x04, 0x81, 0x02, 0xaa, 0xbb]);
    const { node, next } = readDer(bytes);
    expect(Array.from(node.content)).toEqual([0xaa, 0xbb]);
    expect(next).toBe(5);
  });
});
