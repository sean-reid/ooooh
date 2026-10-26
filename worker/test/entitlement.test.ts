import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { DeviceRecord } from "../src/attest/record";
import {
  appAccountTokenFor,
  entitlement,
  entitlementFrom,
  type EntitlementRecord,
  type TransactionClaim,
} from "../src/entitlement";
import { endSession } from "../src/routes/session";
import { assertionHeaders, makeDevice, makeRoot, type Device, type TestRoot } from "./appattest";
import { jsonRequest, openSession } from "./request";
import { wipeKV } from "./workers";
import {
  day,
  makeStoreChain,
  signTransaction,
  transactionPayload,
  type StoreChain,
} from "./storekit";

const hour = 3_600_000;
let authority: TestRoot;
let chain: StoreChain;
let device: Device;
let counter = 0;

const attestEnv = (overrides: Partial<Env> = {}): Env => ({
  ...env,
  REQUIRE_ATTESTATION: "true",
  APP_ATTEST_ENVIRONMENT: "development",
  APP_ATTEST_ROOT_PEM: authority.rootPem,
  APPLE_ROOT_PEM: chain.rootPem,
  ...overrides,
});

const submit = async (body: string, overrides: Partial<Env> = {}, from = device) =>
  worker.fetch(
    jsonRequest(
      "/v1/entitlement",
      body,
      await assertionHeaders(from, { path: "/v1/entitlement", body, counter: ++counter }),
    ),
    attestEnv(overrides),
  );

/** Signs a transaction carrying the posting device's token unless the overrides say otherwise. */
const submitTransaction = async (
  overrides: Record<string, unknown> = {},
  options: { chain?: StoreChain; signer?: CryptoKey; env?: Partial<Env>; from?: Device } = {},
) => {
  const from = options.from ?? device;
  const jws = await signTransaction(
    options.chain ?? chain,
    transactionPayload(Date.now(), {
      appAccountToken: await appAccountTokenFor(from.keyId),
      ...overrides,
    }),
    { signer: options.signer },
  );
  return submit(JSON.stringify({ transaction: jws }), options.env, from);
};

const stored = (keyId = device.keyId) =>
  env.BUDGET.get<EntitlementRecord>(`entitlement:${keyId}`, "json");
const claim = (originalTransactionId = "2000000123456000") =>
  env.BUDGET.get<TransactionClaim>(`transaction:${originalTransactionId}`, "json");

const enrol = async () => {
  const fresh = await makeDevice();
  const record: DeviceRecord = { publicKey: fresh.jwk, createdAt: new Date().toISOString() };
  await env.BUDGET.put(`device:${fresh.keyId}`, JSON.stringify(record));
  return fresh;
};

const start = (now: Date) =>
  openSession(env, device.keyId, now).then((res) => res.json() as Promise<Record<string, unknown>>);

beforeAll(async () => {
  authority = await makeRoot();
  chain = await makeStoreChain();
});

beforeEach(async () => {
  await wipeKV();
  counter = 0;
  device = await enrol();
});

const unauthorized = async (res: Response, reason = "bad-transaction") => {
  expect(res.status).toBe(401);
  expect(await res.json()).toEqual({ error: "unauthorized", reason });
  expect(await stored()).toBeNull();
};

describe("POST /v1/entitlement", () => {
  it("stores a monthly subscription that runs into the future as paid", async () => {
    const before = Date.now();
    const res = await submitTransaction();
    expect(res.status).toBe(200);
    const body = (await res.json()) as { entitlement: string; expiresDate: number };
    expect(body.entitlement).toBe("paid");
    expect(body.expiresDate).toBeGreaterThan(before + 29 * day);

    const record = await stored();
    expect(record).toMatchObject({
      productId: "com.seanreid.ooooh.monthly",
      originalTransactionId: "2000000123456000",
      appAccountToken: await appAccountTokenFor(device.keyId),
      expiresDate: body.expiresDate,
    });
    expect(record).not.toHaveProperty("revocationDate");
    expect(record!.verifiedAt).toBeGreaterThanOrEqual(before);
    expect(record!.signedDate).toBeGreaterThanOrEqual(before);
    expect(await entitlement(device.keyId, env)).toBe("paid");
    expect(await claim()).toMatchObject({ keyId: device.keyId });

    for (const prefix of ["entitlement:", "transaction:"]) {
      const { keys } = await env.BUDGET.list({ prefix });
      expect(keys).toHaveLength(1);
      expect(keys[0].expiration).toBeGreaterThan((body.expiresDate + 29 * day) / 1000);
      expect(keys[0].expiration).toBeLessThan((body.expiresDate + 31 * day) / 1000);
    }
  });

  it("stores an expired subscription and answers free", async () => {
    const now = Date.now();
    const res = await submitTransaction({
      purchaseDate: now - 40 * day,
      expiresDate: now - 10 * day,
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ entitlement: "free", expiresDate: now - 10 * day });
    expect(await entitlement(device.keyId, env)).toBe("free");
  });

  it("answers free for a revoked subscription", async () => {
    const res = await submitTransaction({ revocationDate: Date.now() - 1000, revocationReason: 1 });
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ entitlement: "free" });
    expect((await stored())?.revocationDate).toBeDefined();
  });

  it("answers paid through a grace period after the expiry", async () => {
    const now = Date.now();
    const res = await submitTransaction({
      expiresDate: now - day,
      gracePeriodExpiresDate: now + 15 * day,
    });
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ entitlement: "paid", expiresDate: now - day });
    expect(await entitlement(device.keyId, env)).toBe("paid");
  });

  it("refuses another bundle id, product, or environment", async () => {
    await unauthorized(await submitTransaction({ bundleId: "com.seanreid.other" }));
    await unauthorized(await submitTransaction({ productId: "com.seanreid.ooooh.weekly" }));
    await unauthorized(await submitTransaction({ environment: "Sandbox" }));
    const sandbox = await submitTransaction(
      { environment: "Sandbox" },
      { env: { APP_STORE_ENVIRONMENT: "Sandbox" } },
    );
    expect(sandbox.status).toBe(200);
  });

  it("refuses a bad signature and a chain to a different root", async () => {
    const other = await makeStoreChain();
    await unauthorized(await submitTransaction({}, { signer: other.leaf.privateKey }));
    await unauthorized(await submitTransaction({}, { chain: other }));
  });

  it("answers 422 naming the field when the body has no transaction", async () => {
    const res = await submit(JSON.stringify({ receipt: "abc" }));
    expect(res.status).toBe(422);
    expect(await res.json()).toMatchObject({ field: "transaction" });
  });
});

describe("binding a transaction to the device", () => {
  it("refuses a transaction with no appAccountToken", async () => {
    await unauthorized(await submitTransaction({ appAccountToken: undefined }), "no-account-token");
    expect(await claim()).toBeNull();
  });

  it("refuses a token derived from another device's key id", async () => {
    const other = await enrol();
    await unauthorized(
      await submitTransaction({ appAccountToken: await appAccountTokenFor(other.keyId) }),
      "wrong-device",
    );
    await unauthorized(
      await submitTransaction({ appAccountToken: "1f0c3b2a-9d8e-8f70-a1b2-c3d4e5f60718" }),
      "wrong-device",
    );
    expect(await claim()).toBeNull();
  });

  it("accepts the token in either case", async () => {
    const token = await appAccountTokenFor(device.keyId);
    expect((await submitTransaction({ appAccountToken: token.toUpperCase() })).status).toBe(200);
  });

  it("refuses a second device for a transaction another device claimed", async () => {
    expect((await submitTransaction()).status).toBe(200);
    const second = await enrol();
    const res = await submitTransaction({}, { from: second });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: "unauthorized", reason: "wrong-device" });
    expect(await stored(second.keyId)).toBeNull();
    expect(await stored()).not.toBeNull();
    expect(await claim()).toMatchObject({ keyId: device.keyId });
  });

  it("lets the claiming device post renewals and a second subscription", async () => {
    const now = Date.now();
    expect((await submitTransaction()).status).toBe(200);
    const renewal = await submitTransaction({
      transactionId: "2000000123456790",
      signedDate: now + hour,
      expiresDate: now + 60 * day,
    });
    expect(renewal.status).toBe(200);
    expect((await stored())?.expiresDate).toBe(now + 60 * day);
    const another = await submitTransaction({
      originalTransactionId: "2000000999999000",
      signedDate: now + 2 * hour,
    });
    expect(another.status).toBe(200);
    expect(await claim("2000000999999000")).toMatchObject({ keyId: device.keyId });
  });

  it("refuses a transaction signed before the one it holds", async () => {
    const now = Date.now();
    expect((await submitTransaction({ revocationDate: now - 1000 })).status).toBe(200);
    const older = await submitTransaction({
      signedDate: now - day,
      purchaseDate: now - day,
      expiresDate: now + 29 * day,
    });
    expect(older.status).toBe(401);
    expect(await older.json()).toEqual({ error: "unauthorized", reason: "stale-transaction" });
    expect((await stored())?.revocationDate).toBe(now - 1000);
    expect(await entitlement(device.keyId, env)).toBe("free");
  });

  it("takes a transaction signed at or after the one it holds", async () => {
    const now = Date.now();
    expect((await submitTransaction({ signedDate: now })).status).toBe(200);
    const same = await submitTransaction({ signedDate: now, expiresDate: now + 31 * day });
    expect(same.status).toBe(200);
    expect((await stored())?.expiresDate).toBe(now + 31 * day);
    const newer = await submitTransaction({
      signedDate: now + 1000,
      revocationDate: now + 500,
      revocationReason: 0,
    });
    expect(newer.status).toBe(200);
    expect((await stored())?.revocationDate).toBe(now + 500);
  });

  it("requires the token but cannot match it when attestation is off", async () => {
    const off = { REQUIRE_ATTESTATION: "false" };
    const token = "1f0c3b2a-9d8e-8f70-a1b2-c3d4e5f60718";
    const res = await submitTransaction({ appAccountToken: token }, { env: off });
    expect(res.status).toBe(200);
    expect((await stored())?.appAccountToken).toBe(token);
    const missing = await submitTransaction(
      { appAccountToken: undefined, originalTransactionId: "2000000999999000" },
      { env: off },
    );
    expect(missing.status).toBe(401);
    expect(await missing.json()).toEqual({ error: "unauthorized", reason: "no-account-token" });
  });
});

describe("entitlement and the session count", () => {
  it("lets a paid device start sessions without counting them", async () => {
    expect((await submitTransaction()).status).toBe(200);
    const now = new Date();
    for (let i = 0; i < 5; i++) expect(await start(now)).toEqual({ allowed: true, free: false });
    expect(
      await env.BUDGET.get(`sessions:${device.keyId}:${now.toISOString().slice(0, 7)}`),
    ).toBeNull();
  });

  it("counts a device whose record says free", async () => {
    const now = Date.now();
    await submitTransaction({ expiresDate: now - day });
    expect(await start(new Date(now))).toMatchObject({
      allowed: true,
      free: true,
      remainingFree: 2,
    });
  });

  it("flips back to free once the stored expiry passes, with no new submission", async () => {
    expect((await submitTransaction()).status).toBe(200);
    const record = (await stored())!;
    const beforeExpiry = new Date(record.expiresDate! - 1000);
    const afterExpiry = new Date(record.expiresDate! + 1000);
    expect(await entitlement(device.keyId, env, beforeExpiry)).toBe("paid");
    expect(await entitlement(device.keyId, env, afterExpiry)).toBe("free");
    expect(await start(beforeExpiry)).toEqual({ allowed: true, free: false });
    await endSession(
      jsonRequest("/v1/session/end", { minutes: 1 }),
      env,
      device.keyId,
      beforeExpiry,
    );
    expect(await start(afterExpiry)).toMatchObject({ allowed: true, free: true, remainingFree: 2 });
  });

  it("is free with no record and reads the dates as paid, grace, revoked", () => {
    const now = new Date("2026-10-25T10:00:00Z");
    const t = now.getTime();
    const base = {
      productId: "com.seanreid.ooooh.yearly" as const,
      originalTransactionId: "1",
      signedDate: t,
    };
    expect(entitlementFrom(null, now)).toBe("free");
    expect(entitlementFrom({ ...base, expiresDate: t + 1 }, now)).toBe("paid");
    expect(entitlementFrom({ ...base, expiresDate: t }, now)).toBe("free");
    expect(
      entitlementFrom({ ...base, expiresDate: t - 1, gracePeriodExpiresDate: t + 1 }, now),
    ).toBe("paid");
    expect(entitlementFrom({ ...base, expiresDate: t + 1, revocationDate: t - 1 }, now)).toBe(
      "free",
    );
    expect(entitlementFrom({ ...base }, now)).toBe("free");
  });
});
