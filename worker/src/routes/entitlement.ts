import { unauthorized } from "../attest/record";
import { entitlementFrom, entitlementKey, type EntitlementRecord } from "../entitlement";
import { json, readBody } from "../http";
import { storeKitSettingsFrom, TransactionError, verifyTransaction } from "../storekit/verify";
import { obj, str } from "../validate";

const body = obj({ transaction: str });
const keepAfterExpiryMs = 30 * 24 * 3600 * 1000;

/** Verifies the app's latest signed transaction and keeps what it proves under the device. */
export async function submitEntitlement(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { transaction } = await readBody(request, body);
  let verified: Omit<EntitlementRecord, "verifiedAt">;
  try {
    verified = await verifyTransaction(transaction, { ...storeKitSettingsFrom(env), now });
  } catch (e) {
    if (e instanceof TransactionError) throw unauthorized("bad-transaction");
    throw e;
  }
  const record: EntitlementRecord = { ...verified, verifiedAt: now.getTime() };
  const until = Math.max(
    verified.expiresDate ?? 0,
    verified.gracePeriodExpiresDate ?? 0,
    now.getTime(),
  );
  const expirationTtl = Math.max(60, Math.ceil((until + keepAfterExpiryMs - now.getTime()) / 1000));
  await env.BUDGET.put(entitlementKey(device), JSON.stringify(record), { expirationTtl });
  return json({
    entitlement: entitlementFrom(record, now),
    expiresDate: verified.expiresDate ?? null,
  });
}
