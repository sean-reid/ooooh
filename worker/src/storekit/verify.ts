import { fromBase64, fromBase64Url, type Bytes } from "../bytes";
import { chainsTo, importSpki, parseCertificate, pemToDer, type Certificate } from "../x509";
import { appleRootPem } from "./root";

export type TransactionFailure =
  | "bad-format"
  | "bad-chain"
  | "bad-signature"
  | "bad-bundle-id"
  | "bad-product"
  | "bad-type"
  | "bad-environment";

export class TransactionError extends Error {
  constructor(public reason: TransactionFailure) {
    super(reason);
  }
}

export const productIds = ["com.seanreid.ooooh.monthly", "com.seanreid.ooooh.yearly"] as const;

export interface StoreKitSettings {
  bundleId: string;
  environment: "Sandbox" | "Production";
  rootPem?: string;
}

/** The fields of `JWSTransactionDecodedPayload` the Worker keeps. Dates are ms since the epoch. */
export interface Transaction {
  productId: (typeof productIds)[number];
  originalTransactionId: string;
  signedDate: number;
  /** The UUID the purchase carried, which binds the transaction to one install. */
  appAccountToken?: string;
  expiresDate?: number;
  gracePeriodExpiresDate?: number;
  revocationDate?: number;
}

// The marker extensions Apple's own app-store-server-library requires on the receipt signing chain.
const leafMarker = "1.2.840.113635.100.6.11.1";
const intermediateMarker = "1.2.840.113635.100.6.2.1";

const decodeJson = (part: string): Record<string, unknown> => {
  const bytes = fromBase64Url(part);
  if (!bytes) throw new TransactionError("bad-format");
  const value: unknown = JSON.parse(new TextDecoder().decode(bytes));
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new TransactionError("bad-format");
  }
  return value as Record<string, unknown>;
};

const date = (value: unknown) =>
  typeof value === "number" && Number.isFinite(value) ? value : undefined;

/**
 * Apple's "Verifying a signed transaction" offline: the x5c chain to the Apple Root CA G3, checked
 * at the payload's `signedDate`, then the ES256 signature with the leaf key, then the payload.
 */
export async function verifyTransaction(
  jws: string,
  settings: StoreKitSettings,
): Promise<Transaction> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new TransactionError("bad-format");
  let payload: Record<string, unknown>;
  let chain: Certificate[];
  let signature: Bytes;
  try {
    const header = decodeJson(parts[0]);
    payload = decodeJson(parts[1]);
    const x5c = header.x5c;
    if (header.alg !== "ES256" || !Array.isArray(x5c) || x5c.length < 2) throw new Error();
    chain = x5c.slice(0, 2).map((cert: unknown) => {
      const der = typeof cert === "string" ? fromBase64(cert) : null;
      if (!der) throw new Error();
      return parseCertificate(der);
    });
    const raw = fromBase64Url(parts[2]);
    if (raw?.length !== 64) throw new Error();
    signature = raw;
  } catch {
    throw new TransactionError("bad-format");
  }

  const [leaf, intermediate] = chain;
  const root = parseCertificate(pemToDer(settings.rootPem ?? appleRootPem));
  const signedDate = date(payload.signedDate);
  if (signedDate === undefined) throw new TransactionError("bad-format");
  const at = new Date(signedDate);
  if (
    leaf.curve !== "P-256" ||
    !leaf.extensions.has(leafMarker) ||
    !intermediate.extensions.has(intermediateMarker) ||
    !(await chainsTo(chain, root, at))
  ) {
    throw new TransactionError("bad-chain");
  }

  const signed = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
  const key = await importSpki(leaf);
  if (!(await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, signed))) {
    throw new TransactionError("bad-signature");
  }

  if (payload.bundleId !== settings.bundleId) throw new TransactionError("bad-bundle-id");
  const productId = productIds.find((id) => id === payload.productId);
  if (!productId) throw new TransactionError("bad-product");
  if (payload.type !== "Auto-Renewable Subscription") throw new TransactionError("bad-type");
  if (payload.environment !== settings.environment) throw new TransactionError("bad-environment");
  if (typeof payload.originalTransactionId !== "string") throw new TransactionError("bad-format");
  const appAccountToken = payload.appAccountToken;
  if (appAccountToken !== undefined && typeof appAccountToken !== "string") {
    throw new TransactionError("bad-format");
  }

  return {
    productId,
    originalTransactionId: payload.originalTransactionId,
    signedDate,
    appAccountToken,
    expiresDate: date(payload.expiresDate),
    gracePeriodExpiresDate: date(payload.gracePeriodExpiresDate),
    revocationDate: date(payload.revocationDate),
  };
}
