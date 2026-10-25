import type { Transaction } from "./storekit/verify";

export type Entitlement = "free" | "paid";

/** What `/v1/entitlement` stores per key id: the verified transaction and when. Dates are ms. */
export interface EntitlementRecord extends Transaction {
  verifiedAt: number;
}

export const entitlementKey = (keyId: string) => `entitlement:${keyId}`;

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
