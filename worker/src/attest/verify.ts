import { decodeCbor, field, isBytes, isList, isText, type Bytes } from "./cbor";
import {
  children,
  ecdsaDerToRaw,
  parseCertificate,
  pemToDer,
  readDer,
  type Certificate,
} from "./der";
import { appleAppAttestRootPem } from "./root";

export type AttestationFailure =
  | "bad-format"
  | "bad-chain"
  | "bad-nonce"
  | "bad-key-id"
  | "bad-rp-id"
  | "bad-counter"
  | "bad-aaguid";

export class AttestationError extends Error {
  constructor(public reason: AttestationFailure) {
    super(reason);
  }
}

export interface AttestationSettings {
  /** `TEAMID.bundleid`, hashed into the RP ID. */
  appId: string;
  environment: "development" | "production";
  rootPem?: string;
  now?: Date;
}

export const settingsFrom = (env: Env): AttestationSettings => ({
  appId: env.APP_ATTEST_APP_ID ?? "C6UWR42ZAP.com.seanreid.ooooh",
  environment: env.APP_ATTEST_ENVIRONMENT === "development" ? "development" : "production",
  rootPem: env.APP_ATTEST_ROOT_PEM,
});

const nonceExtension = "1.2.840.113635.100.8.2";

export const sha256 = async (...parts: Bytes[]) => {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    joined.set(part, offset);
    offset += part.length;
  }
  return new Uint8Array(await crypto.subtle.digest("SHA-256", joined));
};

export const equalBytes = (a: Bytes, b: Bytes) =>
  a.length === b.length && a.every((byte, i) => byte === b[i]);

export const toBase64 = (bytes: Bytes) => btoa(String.fromCharCode(...bytes));
export const fromBase64 = (text: string) => {
  try {
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
};

const aaguid = (environment: AttestationSettings["environment"]) => {
  const out = new Uint8Array(16);
  out.set(
    new TextEncoder().encode(environment === "development" ? "appattestdevelop" : "appattest"),
  );
  return out;
};

const importSpki = (cert: Certificate) =>
  crypto.subtle.importKey("spki", cert.spki, { name: "ECDSA", namedCurve: cert.curve }, true, [
    "verify",
  ]);

export const signedBy = async (cert: Certificate, issuer: Certificate) => {
  const key = await importSpki(issuer);
  const size = issuer.curve === "P-256" ? 32 : 48;
  return crypto.subtle.verify(
    { name: "ECDSA", hash: cert.signatureHash },
    key,
    ecdsaDerToRaw(cert.signature, size),
    cert.tbs,
  );
};

async function verifyChain(chain: Certificate[], root: Certificate, now: Date) {
  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i];
    if (now < cert.notBefore || now > cert.notAfter) throw new AttestationError("bad-chain");
    const issuer = chain[i + 1] ?? root;
    if (!(await signedBy(cert, issuer))) throw new AttestationError("bad-chain");
  }
}

/** The extension holds `SEQUENCE { [1] OCTET STRING nonce }`. */
const nonceFrom = (cert: Certificate) => {
  const value = cert.extensions.get(nonceExtension);
  if (!value) throw new AttestationError("bad-nonce");
  try {
    const [tagged] = children(readDer(value).node);
    const [octets] = children(tagged);
    if (octets.tag !== 0x04) throw new AttestationError("bad-nonce");
    return octets.content;
  } catch {
    throw new AttestationError("bad-nonce");
  }
};

export interface VerifiedAttestation {
  publicKey: JsonWebKey;
}

/**
 * The server steps from Apple's "Validating apps that connect to your server", in order.
 * `challenge` is the raw bytes the Worker issued; the app hashed them for `clientDataHash`.
 */
export async function verifyAttestation(
  keyId: string,
  attestation: Bytes,
  challenge: Bytes,
  settings: AttestationSettings,
): Promise<VerifiedAttestation> {
  const now = settings.now ?? new Date();
  let chain: Certificate[];
  let authData: Bytes;
  try {
    const object = decodeCbor(attestation);
    if (field(object, "fmt", isText, "text") !== "apple-appattest") throw new Error();
    const statement = field(
      object,
      "attStmt",
      (v): v is Map<never, never> => v instanceof Map,
      "map",
    );
    const x5c = field(statement, "x5c", isList, "list");
    if (x5c.length < 2 || !x5c.every(isBytes)) throw new Error();
    chain = x5c.map(parseCertificate);
    authData = field(object, "authData", isBytes, "bytes");
    if (authData.length < 55) throw new Error();
  } catch {
    throw new AttestationError("bad-format");
  }

  const root = parseCertificate(pemToDer(settings.rootPem ?? appleAppAttestRootPem));
  await verifyChain(chain, root, now);

  const credCert = chain[0];
  const nonce = await sha256(authData, await sha256(challenge));
  if (!equalBytes(nonceFrom(credCert), nonce)) throw new AttestationError("bad-nonce");

  const keyHash = await sha256(credCert.publicKey);
  if (toBase64(keyHash) !== keyId) throw new AttestationError("bad-key-id");

  const rpIdHash = await sha256(new TextEncoder().encode(settings.appId));
  if (!equalBytes(authData.subarray(0, 32), rpIdHash)) throw new AttestationError("bad-rp-id");

  const counter = new DataView(authData.buffer, authData.byteOffset + 33, 4).getUint32(0);
  if (counter !== 0) throw new AttestationError("bad-counter");

  if (!equalBytes(authData.subarray(37, 53), aaguid(settings.environment))) {
    throw new AttestationError("bad-aaguid");
  }

  const idLength = (authData[53] << 8) | authData[54];
  if (!equalBytes(authData.subarray(55, 55 + idLength), keyHash)) {
    throw new AttestationError("bad-key-id");
  }

  const publicKey = await crypto.subtle.exportKey("jwk", await importSpki(credCert));
  return { publicKey };
}
