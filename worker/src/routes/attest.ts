import { addressFrom } from "../attest/device";
import { AttestationError, settingsFrom, verifyAttestation } from "../attest/verify";
import { fromBase64, toBase64 } from "../bytes";
import {
  counterFor,
  deviceKey,
  readDevice,
  unauthorized,
  type DeviceRecord,
} from "../attest/record";
import { HttpError, json, readBody } from "../http";
import { obj, str } from "../validate";

const challengeTtlSeconds = 300;
const challengeKey = (challenge: string) => `challenge:${challenge}`;
const challengeLength = 32;

/** Nothing here is verified, so one address gets this many challenges and attestations a minute. */
const addressMinuteRequests = 10;
const addressRateKey = (address: string, minute: number) => `attest-rate:${address}:${minute}`;

/** Shaped like `checkDeviceRate`, with its own prefix so enrolment never touches provider budget. */
async function checkAddressRate(request: Request, env: Env, now = new Date()): Promise<void> {
  const minute = Math.floor(now.getTime() / 60_000);
  const key = addressRateKey(addressFrom(request), minute);
  const used = Number((await env.BUDGET.get(key)) ?? 0);
  if (used >= addressMinuteRequests) {
    const retryAfter = 60 - Math.floor((now.getTime() % 60_000) / 1000);
    throw new HttpError(
      429,
      { error: "rate", limit: addressMinuteRequests, retryAfter },
      { "retry-after": String(retryAfter) },
    );
  }
  await env.BUDGET.put(key, String(used + 1), { expirationTtl: 120 });
}

/** 32 random bytes the app hashes into `clientDataHash` for `attestKey`. One use, five minutes. */
export async function challenge(request: Request, env: Env): Promise<Response> {
  await checkAddressRate(request, env);
  const bytes = crypto.getRandomValues(new Uint8Array(challengeLength));
  const issued = toBase64(bytes);
  await env.BUDGET.put(challengeKey(issued), "1", { expirationTtl: challengeTtlSeconds });
  return json({ challenge: issued });
}

const body = obj({ keyId: str, attestation: str, challenge: str });

export async function attest(request: Request, env: Env): Promise<Response> {
  await checkAddressRate(request, env);
  const { keyId, attestation, challenge } = await readBody(request, body);
  const attestationBytes = fromBase64(attestation);
  const challengeBytes = fromBase64(challenge);
  if (!attestationBytes || !challengeBytes) {
    throw new HttpError(422, { error: "invalid", field: "attestation", expected: "base64" });
  }

  if (challengeBytes.length !== challengeLength) throw unauthorized("bad-challenge");
  const key = challengeKey(challenge);
  if (!(await env.BUDGET.get(key))) throw unauthorized("bad-challenge");
  await env.BUDGET.delete(key);

  try {
    const { publicKey } = await verifyAttestation(
      keyId,
      attestationBytes,
      challengeBytes,
      settingsFrom(env),
    );
    const known = await readDevice(env, keyId);
    const record: DeviceRecord = { publicKey, createdAt: new Date().toISOString() };
    await Promise.all([
      env.BUDGET.put(deviceKey(keyId), JSON.stringify(record)),
      known?.counter === undefined ? undefined : counterFor(env, keyId).raise(known.counter),
    ]);
  } catch (e) {
    if (e instanceof AttestationError) throw unauthorized(e.reason);
    throw e;
  }
  return new Response(null, { status: 204 });
}
