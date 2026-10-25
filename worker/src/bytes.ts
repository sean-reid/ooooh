export type Bytes = Uint8Array<ArrayBuffer>;

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

/** JWS parts are base64url without padding. */
export const fromBase64Url = (text: string) =>
  fromBase64(
    text
      .replace(/-/g, "+")
      .replace(/_/g, "/")
      .padEnd(Math.ceil(text.length / 4) * 4, "="),
  );
