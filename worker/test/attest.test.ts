import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { DeviceRecord } from "../src/attest/record";
import { parseCertificate, pemToDer } from "../src/attest/der";
import { appleAppAttestRootPem } from "../src/attest/root";
import { fromBase64, signedBy, toBase64 } from "../src/attest/verify";
import { buildAttestation, makeDevice, makeRoot, type Device, type TestRoot } from "./appattest";

let authority: TestRoot;
const attestEnv = (overrides: Partial<Env> = {}): Env => ({
  ...env,
  APP_ATTEST_ENVIRONMENT: "development",
  APP_ATTEST_ROOT_PEM: authority.rootPem,
  ...overrides,
});

const fetchWorker = (path: string, init: RequestInit = {}, overrides: Partial<Env> = {}) =>
  worker.fetch(new Request(`https://ooooh.test${path}`, init), attestEnv(overrides));

export const getChallenge = async (overrides: Partial<Env> = {}) => {
  const res = await fetchWorker("/v1/challenge", {}, overrides);
  expect(res.status).toBe(200);
  const { challenge } = (await res.json()) as { challenge: string };
  return challenge;
};

export const postAttestation = (
  device: Device,
  challenge: string,
  attestation: Uint8Array<ArrayBuffer>,
  overrides: Partial<Env> = {},
) =>
  fetchWorker(
    "/v1/attest",
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ keyId: device.keyId, attestation: toBase64(attestation), challenge }),
    },
    overrides,
  );

/** Runs the whole enrolment for a fresh device against the test root. */
export async function enrol(overrides: Partial<Env> = {}) {
  const device = await makeDevice();
  const challenge = await getChallenge(overrides);
  const attestation = await buildAttestation({
    device,
    authority,
    challenge: fromBase64(challenge)!,
  });
  const res = await postAttestation(device, challenge, attestation, overrides);
  expect(res.status).toBe(204);
  return device;
}

export const setAuthority = (root: TestRoot) => {
  authority = root;
};

beforeAll(async () => {
  authority = await makeRoot();
});

beforeEach(async () => {
  const keys = await env.BUDGET.list();
  await Promise.all(keys.keys.map((k) => env.BUDGET.delete(k.name)));
});

const reason = async (res: Response) => {
  expect(res.status).toBe(401);
  return ((await res.json()) as { reason: string }).reason;
};

describe("Apple's root", () => {
  it("parses as a self-signed P-384 certificate valid to 2045", async () => {
    const root = parseCertificate(pemToDer(appleAppAttestRootPem));
    expect(root.curve).toBe("P-384");
    expect(root.signatureHash).toBe("SHA-384");
    expect(root.notBefore.toISOString()).toBe("2020-03-18T18:32:53.000Z");
    expect(root.notAfter.toISOString()).toBe("2045-03-15T00:00:00.000Z");
    expect(root.publicKey.length).toBe(97);
    expect(await signedBy(root, root)).toBe(true);
  });
});

describe("GET /v1/challenge", () => {
  it("issues 32 random bytes and remembers them for one use", async () => {
    const challenge = await getChallenge();
    expect(fromBase64(challenge)?.length).toBe(32);
    expect(await env.BUDGET.get(`challenge:${challenge}`)).toBe("1");
    expect(await getChallenge()).not.toBe(challenge);
  });
});

describe("POST /v1/attest", () => {
  it("stores the public key of a good attestation under the key id", async () => {
    const device = await enrol();
    const stored = await env.BUDGET.get<DeviceRecord>(`device:${device.keyId}`, "json");
    expect(stored?.counter).toBe(0);
    expect(stored?.publicKey).toMatchObject({
      kty: "EC",
      crv: "P-256",
      x: device.jwk.x,
      y: device.jwk.y,
    });
    expect(Date.parse(stored!.createdAt)).toBeGreaterThan(Date.now() - 10_000);
  });

  it("burns the challenge even when the attestation is good", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
    });
    expect((await postAttestation(device, challenge, attestation)).status).toBe(204);
    expect(await env.BUDGET.get(`challenge:${challenge}`)).toBeNull();
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe(
      "bad-challenge",
    );
  });

  it("refuses a challenge it never issued", async () => {
    const device = await makeDevice();
    const challenge = toBase64(crypto.getRandomValues(new Uint8Array(32)));
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
    });
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe(
      "bad-challenge",
    );
    expect(await env.BUDGET.get(`device:${device.keyId}`)).toBeNull();
  });

  it("refuses a nonce computed over another challenge", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: crypto.getRandomValues(new Uint8Array(32)),
    });
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe("bad-nonce");
  });

  it("refuses an RP ID hash for another app", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
      appId: "C6UWR42ZAP.com.seanreid.other",
    });
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe("bad-rp-id");
  });

  it("refuses a chain that does not reach the configured root", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const other = await makeRoot();
    const attestation = await buildAttestation({
      device,
      authority: other,
      challenge: fromBase64(challenge)!,
    });
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe("bad-chain");
  });

  it("refuses a key id that is not the hash of the certified key", async () => {
    const device = await makeDevice();
    const impostor = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
    });
    expect(await reason(await postAttestation(impostor, challenge, attestation))).toBe(
      "bad-key-id",
    );
  });

  it("refuses a credential id that differs from the key id", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
      credentialId: crypto.getRandomValues(new Uint8Array(32)),
    });
    expect(await reason(await postAttestation(device, challenge, attestation))).toBe("bad-key-id");
  });

  it("refuses a counter above zero and a production aaguid on a development worker", async () => {
    const device = await makeDevice();
    const first = await getChallenge();
    const counted = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(first)!,
      counter: 3,
    });
    expect(await reason(await postAttestation(device, first, counted))).toBe("bad-counter");

    const second = await getChallenge();
    const production = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(second)!,
      environment: "production",
    });
    expect(await reason(await postAttestation(device, second, production))).toBe("bad-aaguid");
  });

  it("accepts a production aaguid when the worker is configured for production", async () => {
    const device = await makeDevice();
    const challenge = await getChallenge();
    const attestation = await buildAttestation({
      device,
      authority,
      challenge: fromBase64(challenge)!,
      environment: "production",
    });
    const res = await postAttestation(device, challenge, attestation, {
      APP_ATTEST_ENVIRONMENT: "production",
    });
    expect(res.status).toBe(204);
  });

  it("answers 422 for a body that is not an attestation", async () => {
    const res = await fetchWorker("/v1/attest", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ keyId: "k", attestation: "***", challenge: "c" }),
    });
    expect(res.status).toBe(422);
    const device = await makeDevice();
    const challenge = await getChallenge();
    const garbage = await postAttestation(
      device,
      challenge,
      crypto.getRandomValues(new Uint8Array(40)),
    );
    expect(await reason(garbage)).toBe("bad-format");
  });
});
