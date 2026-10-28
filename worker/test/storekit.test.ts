import { beforeAll, describe, expect, it } from "vitest";
import { appleRootPem } from "../src/storekit/root";
import { TransactionError, verifyTransaction, type StoreKitSettings } from "../src/storekit/verify";
import { parseCertificate, pemToDer, signedBy } from "../src/x509";
import {
  day,
  makeStoreChain,
  signTransaction,
  transactionPayload,
  type StoreChain,
} from "./storekit";

let chain: StoreChain;
const now = Date.parse("2026-10-25T10:00:00Z");
const settings = (overrides: Partial<StoreKitSettings> = {}): StoreKitSettings => ({
  bundleId: "com.seanreid.ooooh",
  environments: ["Production"],
  rootPem: chain.rootPem,
  ...overrides,
});

const reason = async (jws: string, overrides: Partial<StoreKitSettings> = {}) => {
  const err = await verifyTransaction(jws, settings(overrides)).catch((e) => e);
  expect(err).toBeInstanceOf(TransactionError);
  return (err as TransactionError).reason;
};

beforeAll(async () => {
  chain = await makeStoreChain();
});

describe("Apple Root CA - G3", () => {
  it("parses as a self-signed P-384 certificate valid to 2039", async () => {
    const root = parseCertificate(pemToDer(appleRootPem));
    expect(root.curve).toBe("P-384");
    expect(root.signatureHash).toBe("SHA-384");
    expect(root.notBefore.toISOString()).toBe("2014-04-30T18:19:06.000Z");
    expect(root.notAfter.toISOString()).toBe("2039-04-30T18:19:06.000Z");
    expect(await signedBy(root, root)).toBe(true);
  });
});

describe("verifyTransaction", () => {
  it("returns the subscription fields of a transaction signed under the root", async () => {
    const jws = await signTransaction(chain, transactionPayload(now));
    expect(await verifyTransaction(jws, settings())).toEqual({
      productId: "com.seanreid.ooooh.monthly",
      originalTransactionId: "2000000123456000",
      signedDate: now,
      appAccountToken: undefined,
      expiresDate: now + 30 * day,
      gracePeriodExpiresDate: undefined,
      revocationDate: undefined,
    });
  });

  it("keeps the appAccountToken as signed and refuses one that is not a string", async () => {
    const token = "1f0c3b2a-9d8e-8f70-a1b2-c3d4e5f60718";
    const jws = await signTransaction(chain, transactionPayload(now, { appAccountToken: token }));
    expect(await verifyTransaction(jws, settings())).toMatchObject({ appAccountToken: token });
    const bad = await signTransaction(chain, transactionPayload(now, { appAccountToken: 7 }));
    expect(await reason(bad)).toBe("bad-format");
  });

  it("keeps the yearly product, a revocation, and a grace period when present", async () => {
    const payload = transactionPayload(now, {
      productId: "com.seanreid.ooooh.yearly",
      revocationDate: now + day,
      revocationReason: 0,
      gracePeriodExpiresDate: now + 16 * day,
    });
    expect(
      await verifyTransaction(await signTransaction(chain, payload), settings()),
    ).toMatchObject({
      productId: "com.seanreid.ooooh.yearly",
      revocationDate: now + day,
      gracePeriodExpiresDate: now + 16 * day,
    });
  });

  it("checks the chain at the signed date, so an older transaction still verifies", async () => {
    const short = await makeStoreChain({
      leafNotBefore: new Date(now - 40 * day),
      leafNotAfter: new Date(now - 10 * day),
    });
    const payload = transactionPayload(now - 20 * day);
    const jws = await signTransaction(short, payload);
    expect(await verifyTransaction(jws, settings({ rootPem: short.rootPem }))).toMatchObject({
      expiresDate: now + 10 * day,
    });
    expect(
      await reason(await signTransaction(short, transactionPayload(now)), {
        rootPem: short.rootPem,
      }),
    ).toBe("bad-chain");
  });

  it("refuses a signature from another key", async () => {
    const other = await makeStoreChain();
    const jws = await signTransaction(chain, transactionPayload(now), {
      signer: other.leaf.privateKey,
    });
    expect(await reason(jws)).toBe("bad-signature");
  });

  it("refuses a chain to a different root", async () => {
    const other = await makeStoreChain();
    expect(await reason(await signTransaction(other, transactionPayload(now)))).toBe("bad-chain");
  });

  it("refuses a chain without Apple's marker extensions", async () => {
    const noLeaf = await makeStoreChain({ leafMarker: "1.2.840.113635.100.6.11.2" });
    const noIntermediate = await makeStoreChain({ intermediateMarker: "1.2.840.113635.100.6.2.2" });
    for (const c of [noLeaf, noIntermediate]) {
      const jws = await signTransaction(c, transactionPayload(now));
      expect(await reason(jws, { rootPem: c.rootPem })).toBe("bad-chain");
    }
  });

  it("refuses another bundle id, product, type, or environment", async () => {
    const cases: [Record<string, unknown>, string][] = [
      [{ bundleId: "com.seanreid.other" }, "bad-bundle-id"],
      [{ productId: "com.seanreid.ooooh.lifetime" }, "bad-product"],
      [{ type: "Non-Consumable" }, "bad-type"],
      [{ environment: "Sandbox" }, "bad-environment"],
    ];
    for (const [overrides, expected] of cases) {
      const jws = await signTransaction(chain, transactionPayload(now, overrides));
      expect(await reason(jws)).toBe(expected);
    }
  });

  it("accepts a Sandbox transaction only when Sandbox is listed", async () => {
    const both = { environments: ["Production", "Sandbox"] as const };
    const sandbox = await signTransaction(
      chain,
      transactionPayload(now, { environment: "Sandbox" }),
    );
    expect(await reason(sandbox)).toBe("bad-environment");
    expect(await verifyTransaction(sandbox, settings(both))).toMatchObject({
      productId: "com.seanreid.ooooh.monthly",
    });
    const production = await signTransaction(chain, transactionPayload(now));
    expect(await verifyTransaction(production, settings(both))).toMatchObject({
      productId: "com.seanreid.ooooh.monthly",
    });
    const xcode = await signTransaction(chain, transactionPayload(now, { environment: "Xcode" }));
    expect(await reason(xcode, both)).toBe("bad-environment");
  });

  it("refuses anything that is not an ES256 JWS with a chain", async () => {
    const payload = transactionPayload(now);
    expect(await reason("not.a.jws")).toBe("bad-format");
    expect(await reason("a.b")).toBe("bad-format");
    expect(await reason(await signTransaction(chain, payload, { alg: "RS256" }))).toBe(
      "bad-format",
    );
    expect(await reason(await signTransaction(chain, payload, { x5c: [chain.leafDer] }))).toBe(
      "bad-format",
    );
    const good = await signTransaction(chain, payload);
    expect(await reason(good.slice(0, -4))).toBe("bad-format");
    const noId = await signTransaction(
      chain,
      transactionPayload(now, { originalTransactionId: 7 }),
    );
    expect(await reason(noId)).toBe("bad-format");
    const noDate = await signTransaction(chain, transactionPayload(now, { signedDate: undefined }));
    expect(await reason(noDate)).toBe("bad-format");
  });
});
