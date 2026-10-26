import { equalBytes, sha256, type Bytes } from "../bytes";
import { ecdsaDerToRaw } from "../x509";
import { decodeCbor, field, isBytes } from "./cbor";
import type { AttestationSettings } from "./verify";

export type AssertionFailure = "bad-assertion" | "replay" | "stale";

export class AssertionError extends Error {
  constructor(public reason: AssertionFailure) {
    super(reason);
  }
}

/**
 * Checks one assertion over `clientDataHash` and returns the counter it carries; whether that
 * counter moves forward is the device's `DeviceCounter` to decide.
 * The signature covers `SHA256(authenticatorData || clientDataHash)`.
 */
export async function verifyAssertion(
  assertion: Bytes,
  clientDataHash: Bytes,
  publicKey: JsonWebKey,
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
    publicKey,
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

  return new DataView(authenticatorData.buffer, authenticatorData.byteOffset + 33, 4).getUint32(0);
}
