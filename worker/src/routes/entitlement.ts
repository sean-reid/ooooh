import { counterFor, unauthorized } from "../attest/record";
import {
  appAccountTokenFor,
  entitlementFrom,
  entitlementKey,
  transactionKey,
  type EntitlementRecord,
  type TransactionClaim,
} from "../entitlement";
import { json, readBody } from "../http";
import { settings } from "../settings";
import { TransactionError, verifyTransaction, type Transaction } from "../storekit/verify";
import { obj, str } from "../validate";

const body = obj({ transaction: str });
const day = 24 * 3600 * 1000;
const keepAfterExpiryMs = 30 * day;
/** How long the key holding a claim has to stay silent before another key may take it. */
export const claimTransferQuietMs = 7 * day;

/** True when `keyId` has passed no assertion within the window; a key never stamped is quiet. */
const quiet = async (env: Env, keyId: string, now: Date) => {
  const seen = await counterFor(env, keyId).lastSeen();
  return seen === undefined || now.getTime() - seen >= claimTransferQuietMs;
};

/**
 * Verifies the app's latest signed transaction and keeps what it proves under the device. A
 * transaction nobody has claimed has to carry the posting device's `appAccountToken`. One
 * another key claimed moves to this device only once that key has been quiet for 7 days, since
 * the token is fixed at purchase and a phone whose App Attest key changed posts the same
 * transaction under its new key. Either way it has to be signed no earlier than what the device
 * already holds.
 */
export async function submitEntitlement(
  request: Request,
  env: Env,
  device: string,
  now = new Date(),
): Promise<Response> {
  const { transaction } = await readBody(request, body);
  const { requireAttestation, storeKit } = settings(env);
  let verified: Transaction;
  try {
    verified = await verifyTransaction(transaction, storeKit);
  } catch (e) {
    if (e instanceof TransactionError) throw unauthorized("bad-transaction");
    throw e;
  }
  if (verified.appAccountToken === undefined) throw unauthorized("no-account-token");

  const claimKey = transactionKey(verified.originalTransactionId);
  const [claim, stored] = await Promise.all([
    env.BUDGET.get<TransactionClaim>(claimKey, "json"),
    env.BUDGET.get<EntitlementRecord>(entitlementKey(device), "json"),
  ]);
  const previous = claim && claim.keyId !== device ? claim.keyId : undefined;
  if (!claim) {
    // Without attestation the device is a label, so there is no key id to derive the token from.
    if (
      requireAttestation &&
      verified.appAccountToken.toLowerCase() !== (await appAccountTokenFor(device))
    ) {
      throw unauthorized("wrong-device");
    }
  } else if (previous !== undefined && !(await quiet(env, previous, now))) {
    throw unauthorized("wrong-device");
  }
  if (stored && verified.signedDate < stored.signedDate) throw unauthorized("stale-transaction");

  const record: EntitlementRecord = { ...verified, verifiedAt: now.getTime() };
  const until = Math.max(
    verified.expiresDate ?? 0,
    verified.gracePeriodExpiresDate ?? 0,
    now.getTime(),
  );
  const expirationTtl = Math.max(60, Math.ceil((until + keepAfterExpiryMs - now.getTime()) / 1000));
  const newClaim: TransactionClaim =
    claim && previous === undefined ? claim : { keyId: device, claimedAt: now.getTime() };
  await Promise.all([
    env.BUDGET.put(entitlementKey(device), JSON.stringify(record), { expirationTtl }),
    env.BUDGET.put(claimKey, JSON.stringify(newClaim), { expirationTtl }),
    previous === undefined ? undefined : env.BUDGET.delete(entitlementKey(previous)),
  ]);
  return json({
    entitlement: entitlementFrom(record, now),
    expiresDate: verified.expiresDate ?? null,
  });
}
