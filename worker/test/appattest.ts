// Synthetic App Attest material in Apple's exact layout, signed by keys made here: a P-384 root
// and intermediate, a P-256 device key, the attestation object, and assertions over a body hash.
import { sha256, toBase64, type Bytes } from "../src/bytes";
import {
  certificate,
  concat,
  explicit,
  generate,
  octets,
  oid,
  pem,
  rawToDer,
  seq,
  type Authority,
} from "./x509";

const encoder = new TextEncoder();

export const cbor = (value: unknown): Bytes => {
  const head = (major: number, n: number) =>
    n < 24
      ? [(major << 5) | n]
      : n < 256
        ? [(major << 5) | 24, n]
        : [(major << 5) | 25, n >> 8, n & 0xff];
  if (typeof value === "number") return concat(value >= 0 ? head(0, value) : head(1, -1 - value));
  if (value instanceof Uint8Array) return concat(head(2, value.length), value as Bytes);
  if (typeof value === "string") {
    const bytes = encoder.encode(value);
    return concat(head(3, bytes.length), bytes);
  }
  if (Array.isArray(value)) return concat(head(4, value.length), ...value.map(cbor));
  const entries = value instanceof Map ? [...value.entries()] : Object.entries(value as object);
  return concat(head(5, entries.length), ...entries.flatMap(([k, v]) => [cbor(k), cbor(v)]));
};

export interface TestRoot {
  root: Authority;
  intermediate: Authority;
  rootPem: string;
  intermediateDer: Bytes;
}

/** A root like Apple's (P-384, self-signed) with one intermediate under it. */
export async function makeRoot(): Promise<TestRoot> {
  const root: Authority = {
    name: "Test App Attest Root",
    curve: "P-384",
    keys: await generate("P-384"),
  };
  const intermediate: Authority = {
    name: "Test App Attest CA 1",
    curve: "P-384",
    keys: await generate("P-384"),
  };
  const rootDer = await certificate({
    subject: root.name,
    publicKey: root.keys.publicKey,
    issuer: root,
  });
  const intermediateDer = await certificate({
    subject: intermediate.name,
    publicKey: intermediate.keys.publicKey,
    issuer: root,
  });
  return { root, intermediate, rootPem: pem(rootDer), intermediateDer };
}

export interface Device {
  keys: CryptoKeyPair;
  /** Uncompressed point, 65 bytes. */
  publicKey: Bytes;
  keyId: string;
  jwk: JsonWebKey;
}

/** What `DCAppAttestService.generateKey` yields: a P-256 key whose id is the hash of its point. */
export async function makeDevice(): Promise<Device> {
  const keys = await generate("P-256");
  const publicKey = new Uint8Array(await crypto.subtle.exportKey("raw", keys.publicKey));
  const jwk = await crypto.subtle.exportKey("jwk", keys.publicKey);
  return { keys, publicKey, keyId: toBase64(await sha256(publicKey)), jwk };
}

export const appId = "C6UWR42ZAP.com.seanreid.ooooh";

const aaguid = (environment: "development" | "production") =>
  concat(
    encoder.encode(environment === "development" ? "appattestdevelop" : "appattest"),
    new Uint8Array(16),
  ).subarray(0, 16);

const uint32 = (n: number) => [n >>> 24, (n >>> 16) & 0xff, (n >>> 8) & 0xff, n & 0xff];

interface AttestationOptions {
  device: Device;
  authority: TestRoot;
  challenge: Bytes;
  appId?: string;
  environment?: "development" | "production";
  counter?: number;
  /** Replaces the hash the certificate carries, for a wrong-nonce case. */
  nonce?: Bytes;
  /** The key id written into credentialId, for a mismatch case. */
  credentialId?: Bytes;
}

export async function buildAttestation(options: AttestationOptions): Promise<Bytes> {
  const { device, authority } = options;
  const rpIdHash = await sha256(encoder.encode(options.appId ?? appId));
  const credentialId = options.credentialId ?? (await sha256(device.publicKey));
  const coseKey = cbor(
    new Map<number, unknown>([
      [1, 2],
      [3, -7],
      [-1, 1],
      [-2, device.publicKey.subarray(1, 33)],
      [-3, device.publicKey.subarray(33)],
    ]),
  );
  const authData = concat(
    rpIdHash,
    [0x40],
    uint32(options.counter ?? 0),
    aaguid(options.environment ?? "development"),
    [credentialId.length >> 8, credentialId.length & 0xff],
    credentialId,
    coseKey,
  );
  const nonce = options.nonce ?? (await sha256(authData, await sha256(options.challenge)));
  const credCert = await certificate({
    subject: device.keyId,
    publicKey: device.keys.publicKey,
    issuer: authority.intermediate,
    extensions: [seq(oid("1.2.840.113635.100.8.2"), octets(seq(explicit(1, octets(nonce)))))],
  });
  return cbor({
    fmt: "apple-appattest",
    attStmt: { x5c: [credCert, authority.intermediateDer], receipt: new Uint8Array(4) },
    authData,
  });
}

interface AssertionOptions {
  device: Device;
  clientDataHash: Bytes;
  counter: number;
  appId?: string;
  /** Signs with another key, for a forged case. */
  signer?: CryptoKey;
}

export async function buildAssertion(options: AssertionOptions): Promise<Bytes> {
  const rpIdHash = await sha256(encoder.encode(options.appId ?? appId));
  const authenticatorData = concat(rpIdHash, [0x40], uint32(options.counter));
  const nonce = await sha256(authenticatorData, options.clientDataHash);
  const signature = rawToDer(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: "SHA-256" },
        options.signer ?? options.device.keys.privateKey,
        nonce,
      ),
    ),
  );
  return cbor({ signature, authenticatorData });
}

/** Headers for one request body, the way `ProxyClient` sends them. */
export async function assertionHeaders(
  device: Device,
  body: string,
  counter: number,
  appIdOverride?: string,
) {
  const assertion = await buildAssertion({
    device,
    clientDataHash: await sha256(encoder.encode(body)),
    counter,
    appId: appIdOverride,
  });
  return { "x-device": device.keyId, "x-assertion": toBase64(assertion) };
}
