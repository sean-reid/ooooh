import { decodeCbor, field, isBytes, type Bytes } from "./cbor";
import { ecdsaDerToRaw } from "./der";
import type { DeviceRecord } from "./record";
import { equalBytes, sha256, type AttestationSettings } from "./verify";

export type AssertionFailure = "bad-assertion" | "replay";

export class AssertionError extends Error {
  constructor(public reason: AssertionFailure) {
    super(reason);
  }
}

/**
 * Checks one assertion over `clientDataHash` and returns the counter to store.
 * The signature covers `SHA256(authenticatorData || clientDataHash)`.
 */
export async function verifyAssertion(
  assertion: Bytes,
  clientDataHash: Bytes,
  device: DeviceRecord,
  settings: Pick<AttestationSettings, "appId">,
): Promise<number> {
  let signature: Bytes;
  let authenticatorData: Bytes;
  try {
    const object = decodeCbor(assertion);
    signature = ecdsaDerToRaw(field(object, "signature", isBytes, "bytes"), 32);
    authenticatorData = field(object, "authenticatorData", isBytes, "bytes");
    if (authenticatorData.length < 37) throw new Error();
  } catch {
    throw new AssertionError("bad-assertion");
  }

  const key = await crypto.subtle.importKey(
    "jwk",
    device.publicKey,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["verify"],
  );
  const nonce = await sha256(authenticatorData, clientDataHash);
  const valid = await crypto.subtle.verify(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    signature,
    nonce,
  );
  if (!valid) throw new AssertionError("bad-assertion");

  const rpIdHash = await sha256(new TextEncoder().encode(settings.appId));
  if (!equalBytes(authenticatorData.subarray(0, 32), rpIdHash)) {
    throw new AssertionError("bad-assertion");
  }

  const counter = new DataView(
    authenticatorData.buffer,
    authenticatorData.byteOffset + 33,
    4,
  ).getUint32(0);
  if (counter <= device.counter) throw new AssertionError("replay");
  return counter;
}
