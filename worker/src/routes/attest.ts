import {
  AttestationError,
  fromBase64,
  settingsFrom,
  toBase64,
  verifyAttestation,
} from "../attest/verify";
import { callerFrom } from "../attest/device";
import { deviceKey, unauthorized, type DeviceRecord } from "../attest/record";
import { checkDeviceRate } from "../budget";
import { HttpError, json, readBody } from "../http";
import { obj, str } from "../validate";

const challengeTtlSeconds = 300;
const challengeKey = (challenge: string) => `challenge:${challenge}`;

/** 32 random bytes the app hashes into `clientDataHash` for `attestKey`. One use, five minutes. */
export async function challenge(request: Request, env: Env): Promise<Response> {
  await checkDeviceRate(callerFrom(request), env);
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const issued = toBase64(bytes);
  await env.BUDGET.put(challengeKey(issued), "1", { expirationTtl: challengeTtlSeconds });
  return json({ challenge: issued });
}

const body = obj({ keyId: str, attestation: str, challenge: str });

export async function attest(request: Request, env: Env): Promise<Response> {
  await checkDeviceRate(callerFrom(request), env);
  const { keyId, attestation, challenge } = await readBody(request, body);
  const attestationBytes = fromBase64(attestation);
  const challengeBytes = fromBase64(challenge);
  if (!attestationBytes || !challengeBytes) {
    throw new HttpError(422, { error: "invalid", field: "attestation", expected: "base64" });
  }

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
    const record: DeviceRecord = { publicKey, counter: 0, createdAt: new Date().toISOString() };
    await env.BUDGET.put(deviceKey(keyId), JSON.stringify(record));
  } catch (e) {
    if (e instanceof AttestationError) throw unauthorized(e.reason);
    throw e;
  }
  return new Response(null, { status: 204 });
}
