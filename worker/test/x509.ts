// DER builders and a certificate signer for the test chains: enough X.509 to stand in for Apple.
import { toBase64, type Bytes } from "../src/bytes";

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
export const tlv = (tag: number, content: Bytes | number[]) => {
  const body = concat(content);
  return concat([tag, ...length(body.length)], body);
};
export const seq = (...items: Bytes[]) => tlv(0x30, concat(...items));
const set = (...items: Bytes[]) => tlv(0x31, concat(...items));
const integer = (bytes: Bytes) => tlv(0x02, bytes[0] & 0x80 ? concat([0], bytes) : bytes);
export const octets = (bytes: Bytes) => tlv(0x04, bytes);
const bitString = (bytes: Bytes) => tlv(0x03, concat([0], bytes));
const utf8 = (text: string) => tlv(0x0c, encoder.encode(text));
export const explicit = (n: number, content: Bytes) => tlv(0xa0 | n, content);
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

export const oid = (text: string) => {
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

export interface Authority {
  name: string;
  curve: Curve;
  keys: CryptoKeyPair;
}

export const generate = (curve: Curve) =>
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

/** Tests pin `now` to fixed dates, so a default certificate is valid at any of them, not around today. */
const alwaysValid = {
  notBefore: new Date("2020-01-01T00:00:00Z"),
  notAfter: new Date("2099-01-01T00:00:00Z"),
};

export async function certificate(options: CertificateOptions): Promise<Bytes> {
  const spki = new Uint8Array(await crypto.subtle.exportKey("spki", options.publicKey));
  const algorithm = seq(signatureOid(options.issuer.curve));
  const notBefore = options.notBefore ?? alwaysValid.notBefore;
  const notAfter = options.notAfter ?? alwaysValid.notAfter;
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

export const pem = (der: Bytes) =>
  `-----BEGIN CERTIFICATE-----\n${toBase64(der).replace(/(.{64})/g, "$1\n")}\n-----END CERTIFICATE-----`;
