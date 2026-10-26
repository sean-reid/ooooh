import { requiresAttestation } from "../attest/device";
import { unauthorized } from "../attest/record";
import {
  appAccountTokenFor,
  entitlementFrom,
  entitlementKey,
  transactionKey,
  type EntitlementRecord,
  type TransactionClaim,
} from "../entitlement";
import { json, readBody } from "../http";
import {
  storeKitSettingsFrom,
  TransactionError,
  verifyTransaction,
  type Transaction,
} from "../storekit/verify";
import { obj, str } from "../validate";

const body = obj({ transaction: str });
const keepAfterExpiryMs = 30 * 24 * 3600 * 1000;

/**
 * Verifies the app's latest signed transaction and keeps what it proves under the device. The
 * transaction has to carry the posting device's `appAccountToken`, be unclaimed or claimed by
 * this device, and be signed no earlier than what the device already holds.
 */
export async function submitEntitlement(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { transaction } = await readBody(request, body);
  let verified: Transaction;
  try {
    verified = await verifyTransaction(transaction, storeKitSettingsFrom(env));
  } catch (e) {
    if (e instanceof TransactionError) throw unauthorized("bad-transaction");
    throw e;
  }

  if (verified.appAccountToken === undefined) throw unauthorized("no-account-token");
  // Without attestation the device is a label, so there is no key id to derive the token from.
  if (
    requiresAttestation(env) &&
    verified.appAccountToken.toLowerCase() !== (await appAccountTokenFor(device))
  ) {
    throw unauthorized("wrong-device");
  }

  const claimKey = transactionKey(verified.originalTransactionId);
  const [claim, stored] = await Promise.all([
    env.BUDGET.get<TransactionClaim>(claimKey, "json"),
    env.BUDGET.get<EntitlementRecord>(entitlementKey(device), "json"),
  ]);
  if (claim && claim.keyId !== device) throw unauthorized("wrong-device");
  if (stored && verified.signedDate < stored.signedDate) throw unauthorized("stale-transaction");

  const record: EntitlementRecord = { ...verified, verifiedAt: now.getTime() };
  const until = Math.max(
    verified.expiresDate ?? 0,
    verified.gracePeriodExpiresDate ?? 0,
    now.getTime(),
  );
  const expirationTtl = Math.max(60, Math.ceil((until + keepAfterExpiryMs - now.getTime()) / 1000));
  const newClaim: TransactionClaim = claim ?? { keyId: device, claimedAt: now.getTime() };
  await Promise.all([
    env.BUDGET.put(entitlementKey(device), JSON.stringify(record), { expirationTtl }),
    env.BUDGET.put(claimKey, JSON.stringify(newClaim), { expirationTtl }),
  ]);
  return json({
    entitlement: entitlementFrom(record, now),
    expiresDate: verified.expiresDate ?? null,
  });
}
