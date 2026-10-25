// Synthetic App Attest material in Apple's exact layout, signed by keys made here: a P-384 root
// and intermediate, a P-256 device key, the attestation object, and assertions over a body hash.
import { sha256, toBase64 } from "../src/attest/verify";

type Bytes = Uint8Array<ArrayBuffer>;
type Curve = "P-256" | "P-384";

const encoder = new TextEncoder();

export const concat = (...parts: (Bytes | number[])[]): Bytes => {
  const arrays = parts.map((p) => (Array.isArray(p) ? Uint8Array.from(p) : p));
  const out = new Uint8Array(arrays.reduce((n, a) => n + a.length, 0));
  let offset = 0;
  for (const a of arrays) {
    out.set(a, offset);
    offset += a.length;
  }
  return out;
};

const length = (n: number) => (n < 128 ? [n] : n < 256 ? [0x81, n] : [0x82, n >> 8, n & 0xff]);
const tlv = (tag: number, content: Bytes | number[]) => {
  const body = concat(content);
  return concat([tag, ...length(body.length)], body);
};
const seq = (...items: Bytes[]) => tlv(0x30, concat(...items));
const set = (...items: Bytes[]) => tlv(0x31, concat(...items));
const integer = (bytes: Bytes) => tlv(0x02, bytes[0] & 0x80 ? concat([0], bytes) : bytes);
const octets = (bytes: Bytes) => tlv(0x04, bytes);
const bitString = (bytes: Bytes) => tlv(0x03, concat([0], bytes));
const utf8 = (text: string) => tlv(0x0c, encoder.encode(text));
const explicit = (n: number, content: Bytes) => tlv(0xa0 | n, content);
const utcTime = (date: Date) =>
  tlv(
    0x17,
    encoder.encode(
      date
        .toISOString()
        .replace(/[-:T]|\.\d+/g, "")
        .slice(2, 14) + "Z",
    ),
  );

const oid = (text: string) => {
  const arcs = text.split(".").map(Number);
  const out = [arcs[0] * 40 + arcs[1]];
  for (const arc of arcs.slice(2)) {
    const bytes = [arc & 0x7f];
    for (let v = arc >> 7; v > 0; v >>= 7) bytes.unshift((v & 0x7f) | 0x80);
    out.push(...bytes);
  }
  return tlv(0x06, out);
};

const name = (cn: string) => seq(set(seq(oid("2.5.4.3"), utf8(cn))));

const trim = (bytes: Bytes) => {
  let start = 0;
  while (start < bytes.length - 1 && bytes[start] === 0) start++;
  return bytes.subarray(start);
};

/** WebCrypto signs as r||s; certificates and assertions carry DER `SEQUENCE { r, s }`. */
export const rawToDer = (raw: Bytes) => {
  const half = raw.length / 2;
  return seq(integer(trim(raw.subarray(0, half))), integer(trim(raw.subarray(half))));
};

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

export interface Authority {
  name: string;
  curve: Curve;
  keys: CryptoKeyPair;
}

const generate = (curve: Curve) =>
  crypto.subtle.generateKey({ name: "ECDSA", namedCurve: curve }, true, ["sign", "verify"]);

const hashFor = (curve: Curve) => (curve === "P-256" ? "SHA-256" : "SHA-384");
const signatureOid = (curve: Curve) =>
  oid(curve === "P-256" ? "1.2.840.10045.4.3.2" : "1.2.840.10045.4.3.3");

const sign = async (issuer: Authority, data: Bytes) =>
  rawToDer(
    new Uint8Array(
      await crypto.subtle.sign(
        { name: "ECDSA", hash: hashFor(issuer.curve) },
        issuer.keys.privateKey,
        data,
      ),
    ),
  );

interface CertificateOptions {
  subject: string;
  publicKey: CryptoKey;
  issuer: Authority;
  extensions?: Bytes[];
  notBefore?: Date;
  notAfter?: Date;
}

export async function certificate(options: CertificateOptions): Promise<Bytes> {
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", options.publicKey));
  const algorithm = seq(signatureOid(options.issuer.curve));
  const notBefore = options.notBefore ?? new Date(Date.now() - 86_400_000);
  const notAfter = options.notAfter ?? new Date(Date.now() + 86_400_000);
  const tbs = seq(
    explicit(0, integer(Uint8Array.of(2))),
    integer(crypto.getRandomValues(new Uint8Array(8))),
    algorithm,
    name(options.issuer.name),
    seq(utcTime(notBefore), utcTime(notAfter)),
    name(options.subject),
    spki,
    ...(options.extensions?.length ? [explicit(3, seq(...options.extensions))] : []),
  );
  return seq(tbs, algorithm, bitString(await sign(options.issuer, tbs)));
}

const pem = (der: Bytes) =>
  `-----BEGIN CERTIFICATE-----\n${toBase64(der).replace(/(.{64})/g, "$1\n")}\n-----END CERTIFICATE-----`;

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
