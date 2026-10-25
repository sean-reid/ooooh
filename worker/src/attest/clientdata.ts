import { sha256, toHex, type Bytes } from "../bytes";
import { AssertionError } from "./assertion";

export const assertionTimeHeader = "x-assertion-time";

/** How far, in seconds, the time an assertion carries may sit from the Worker's clock. */
export const maxAssertionSkewSeconds = 300;

/** The string an assertion covers: method, path, unix seconds, and the hex body hash, newline separated. */
export const canonicalClientData = (
  method: string,
  path: string,
  time: number,
  bodyHash: Bytes,
): string => [method, path, String(time), toHex(bodyHash)].join("\n");

export const clientDataHash = async (method: string, path: string, time: number, body: Bytes) =>
  sha256(new TextEncoder().encode(canonicalClientData(method, path, time, await sha256(body))));

/** The unix seconds from `x-assertion-time`, refused when malformed or outside the skew window. */
export const assertionTime = (header: string | null, nowMs = Date.now()): number => {
  if (!header || !/^\d{1,15}$/.test(header)) throw new AssertionError("bad-assertion");
  const time = Number(header);
  if (Math.abs(time - Math.floor(nowMs / 1000)) > maxAssertionSkewSeconds) {
    throw new AssertionError("stale");
  }
  return time;
};
