import { sha256 } from "./bytes";
import type { Transaction } from "./storekit/verify";

export type Entitlement = "free" | "paid";

/** What `/v1/entitlement` stores per key id: the verified transaction and when. Dates are ms. */
export interface EntitlementRecord extends Transaction {
  verifiedAt: number;
}

/** Which key id first posted an `originalTransactionId`. Stored under `transaction:<id>`. */
export interface TransactionClaim {
  keyId: string;
  claimedAt: number;
}

export const entitlementKey = (keyId: string) => `entitlement:${keyId}`;
export const transactionKey = (originalTransactionId: string) =>
  `transaction:${originalTransactionId}`;

const tokenPrefix = "ooooh.appAccountToken:";

/**
 * The `appAccountToken` an install sets at purchase: the first 16 bytes of
 * SHA-256("ooooh.appAccountToken:" + keyId) as a version 8 UUID, lowercase. The app derives the
 * same value in `AppAccountToken.derive(keyId:)`.
 */
export async function appAccountTokenFor(keyId: string): Promise<string> {
  const digest = await sha256(new TextEncoder().encode(tokenPrefix + keyId));
  const bytes = digest.slice(0, 16);
  bytes[6] = (bytes[6] & 0x0f) | 0x80;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return [
    hex.slice(0, 8),
    hex.slice(8, 12),
    hex.slice(12, 16),
    hex.slice(16, 20),
    hex.slice(20),
  ].join("-");
}

/** Paid while the subscription or its grace period runs and nothing was revoked. */
export const entitlementFrom = (record: Transaction | null, now: Date): Entitlement => {
  if (!record || record.revocationDate !== undefined) return "free";
  const until = Math.max(record.expiresDate ?? 0, record.gracePeriodExpiresDate ?? 0);
  return until > now.getTime() ? "paid" : "free";
};

export async function entitlement(keyId: string, env: Env, now = new Date()): Promise<Entitlement> {
  const record = await env.BUDGET.get<EntitlementRecord>(entitlementKey(keyId), "json");
  return entitlementFrom(record, now);
}
