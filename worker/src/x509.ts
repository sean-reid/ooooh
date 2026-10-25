// Enough of DER to walk an X.509 certificate: tags, lengths, and the fields the chain check needs.
import type { Bytes } from "./bytes";

export class DerError extends Error {}

export interface DerNode {
  tag: number;
  /** The whole element, header included, for signature inputs. */
  raw: Bytes;
  content: Bytes;
}

export function readDer(bytes: Bytes, offset = 0): { node: DerNode; next: number } {
  if (offset + 2 > bytes.length) throw new DerError("truncated");
  const tag = bytes[offset];
  let length = bytes[offset + 1];
  let cursor = offset + 2;
  if (length & 0x80) {
    const size = length & 0x7f;
    if (size === 0 || size > 4) throw new DerError("bad length");
    length = 0;
    for (let i = 0; i < size; i++) length = length * 256 + bytes[cursor++];
  }
  const end = cursor + length;
  if (end > bytes.length) throw new DerError("truncated");
  return {
    node: { tag, raw: bytes.subarray(offset, end), content: bytes.subarray(cursor, end) },
    next: end,
  };
}

export function children(node: DerNode): DerNode[] {
  const out: DerNode[] = [];
  let offset = 0;
  while (offset < node.content.length) {
    const { node: child, next } = readDer(node.content, offset);
    out.push(child);
    offset = next;
  }
  return out;
}

export function oid(node: DerNode): string {
  if (node.tag !== 0x06) throw new DerError("expected oid");
  const parts: number[] = [];
  let value = 0;
  for (const byte of node.content) {
    value = value * 128 + (byte & 0x7f);
    if (byte & 0x80) continue;
    if (parts.length === 0) {
      const first = value < 40 ? 0 : value < 80 ? 1 : 2;
      parts.push(first, value - 40 * first);
    } else {
      parts.push(value);
    }
    value = 0;
  }
  return parts.join(".");
}

/** The bits of a BIT STRING, which carries ECDSA signatures and EC points with a zero pad byte. */
export const bits = (node: DerNode) => {
  if (node.tag !== 0x03 || node.content[0] !== 0) throw new DerError("expected bit string");
  return node.content.subarray(1);
};

const time = (node: DerNode) => {
  const text = new TextDecoder().decode(node.content);
  const full = node.tag === 0x17 ? `${Number(text.slice(0, 2)) < 50 ? "20" : "19"}${text}` : text;
  const m = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})Z$/.exec(full);
  if (!m) throw new DerError("bad time");
  return new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]));
};

export const curves: Record<string, "P-256" | "P-384"> = {
  "1.2.840.10045.3.1.7": "P-256",
  "1.3.132.0.34": "P-384",
};

export const hashes: Record<string, "SHA-256" | "SHA-384"> = {
  "1.2.840.10045.4.3.2": "SHA-256",
  "1.2.840.10045.4.3.3": "SHA-384",
};

export interface Certificate {
  tbs: Bytes;
  signatureHash: "SHA-256" | "SHA-384";
  signature: Bytes;
  spki: Bytes;
  curve: "P-256" | "P-384";
  /** Uncompressed point, 0x04 then x and y. */
  publicKey: Bytes;
  notBefore: Date;
  notAfter: Date;
  extensions: Map<string, Bytes>;
}

export function parseCertificate(der: Bytes): Certificate {
  const [tbs, algorithm, signature] = children(readDer(der).node);
  const fields = children(tbs);
  if (fields[0]?.tag !== 0xa0) throw new DerError("expected v3 certificate");
  const [, , , , validity, , spki] = fields;
  const [notBefore, notAfter] = children(validity).map(time);
  const [keyAlgorithm, point] = children(spki);
  const [keyType, curveOid] = children(keyAlgorithm);
  if (oid(keyType) !== "1.2.840.10045.2.1") throw new DerError("not an EC key");
  const curve = curves[oid(curveOid)];
  const signatureHash = hashes[oid(children(algorithm)[0])];
  if (!curve || !signatureHash) throw new DerError("unsupported algorithm");
  const extensions = new Map<string, Bytes>();
  const wrapper = fields.find((f) => f.tag === 0xa3);
  if (wrapper) {
    for (const extension of children(children(wrapper)[0])) {
      const parts = children(extension);
      extensions.set(oid(parts[0]), parts[parts.length - 1].content);
    }
  }
  return {
    tbs: tbs.raw,
    signatureHash,
    signature: bits(signature),
    spki: spki.raw,
    curve,
    publicKey: bits(point),
    notBefore,
    notAfter,
    extensions,
  };
}

export function pemToDer(pem: string): Bytes {
  const body = pem.replace(/-----(BEGIN|END)[^-]*-----/g, "").replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

/** WebCrypto wants r and s fixed width and concatenated; DER carries them as two INTEGERs. */
export function ecdsaDerToRaw(der: Bytes, size: number): Bytes {
  const [r, s] = children(readDer(der).node);
  if (!r || !s || r.tag !== 0x02 || s.tag !== 0x02) throw new DerError("bad signature");
  const out = new Uint8Array(size * 2);
  const place = (value: Bytes, at: number) => {
    const trimmed = value[0] === 0 && value.length > size ? value.subarray(1) : value;
    if (trimmed.length > size) throw new DerError("bad signature");
    out.set(trimmed, at + size - trimmed.length);
  };
  place(r.content, 0);
  place(s.content, size);
  return out;
}

export const importSpki = (cert: Certificate) =>
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

/** Every certificate valid at `at` and signed by the next one, the last by `root`. */
export async function chainsTo(chain: Certificate[], root: Certificate, at: Date) {
  for (let i = 0; i < chain.length; i++) {
    const cert = chain[i];
    if (at < cert.notBefore || at > cert.notAfter) return false;
    if (!(await signedBy(cert, chain[i + 1] ?? root))) return false;
  }
  return true;
}
