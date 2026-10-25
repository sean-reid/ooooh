import { env } from "cloudflare:test";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index";
import type { DeviceRecord } from "../src/attest/record";
import { entitlement, entitlementFrom, type EntitlementRecord } from "../src/entitlement";
import { startSession } from "../src/routes/session";
import { assertionHeaders, makeDevice, makeRoot, type Device, type TestRoot } from "./appattest";
import {
  day,
  makeStoreChain,
  signTransaction,
  transactionPayload,
  type StoreChain,
} from "./storekit";

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

const submit = async (body: string, overrides: Partial<Env> = {}) =>
  worker.fetch(
    new Request("https://ooooh.test/v1/entitlement", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(await assertionHeaders(device, { path: "/v1/entitlement", body, counter: ++counter })),
      },
      body,
    }),
    attestEnv(overrides),
  );

const submitTransaction = async (
  overrides: Record<string, unknown> = {},
  options: { chain?: StoreChain; signer?: CryptoKey; env?: Partial<Env> } = {},
) => {
  const jws = await signTransaction(
    options.chain ?? chain,
    transactionPayload(Date.now(), overrides),
    {
      signer: options.signer,
    },
  );
  return submit(JSON.stringify({ transaction: jws }), options.env);
};

const stored = () => env.BUDGET.get<EntitlementRecord>(`entitlement:${device.keyId}`, "json");

const start = (now: Date) =>
  startSession(
    new Request("https://ooooh.test/v1/session/start", { method: "POST" }),
    env,
    device.keyId,
    now,
  ).then((res) => res.json() as Promise<Record<string, unknown>>);

beforeAll(async () => {
  authority = await makeRoot();
  chain = await makeStoreChain();
});

beforeEach(async () => {
  const keys = await env.BUDGET.list();
  await Promise.all(keys.keys.map((k) => env.BUDGET.delete(k.name)));
  device = await makeDevice();
  counter = 0;
  const record: DeviceRecord = {
    publicKey: device.jwk,
    counter: 0,
    createdAt: new Date().toISOString(),
  };
  await env.BUDGET.put(`device:${device.keyId}`, JSON.stringify(record));
});

const unauthorized = async (res: Response) => {
  expect(res.status).toBe(401);
  expect(await res.json()).toEqual({ error: "unauthorized", reason: "bad-transaction" });
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
      expiresDate: body.expiresDate,
    });
    expect(record).not.toHaveProperty("revocationDate");
    expect(record!.verifiedAt).toBeGreaterThanOrEqual(before);
    expect(await entitlement(device.keyId, env)).toBe("paid");

    const { keys } = await env.BUDGET.list({ prefix: "entitlement:" });
    expect(keys[0].expiration).toBeGreaterThan((body.expiresDate + 29 * day) / 1000);
    expect(keys[0].expiration).toBeLessThan((body.expiresDate + 31 * day) / 1000);
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
    expect(await start(afterExpiry)).toMatchObject({ allowed: true, free: true, remainingFree: 2 });
  });

  it("is free with no record and reads the dates as paid, grace, revoked", () => {
    const now = new Date("2026-10-25T10:00:00Z");
    const t = now.getTime();
    const base = { productId: "com.seanreid.ooooh.yearly" as const, originalTransactionId: "1" };
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
