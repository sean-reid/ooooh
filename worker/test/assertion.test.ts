import { env, SELF } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { DeviceRecord } from "../src/attest/record";
import { sha256, toBase64 } from "../src/attest/verify";
import {
  assertionHeaders,
  buildAssertion,
  makeDevice,
  makeRoot,
  type Device,
  type TestRoot,
} from "./appattest";
import { bodyOf, decideBody, fakeUpstream, jevReply, type FakeUpstream } from "./upstream";

let authority: TestRoot;
let device: Device;
const attestEnv = (): Env => ({
  ...env,
  REQUIRE_ATTESTATION: "true",
  APP_ATTEST_ENVIRONMENT: "development",
  APP_ATTEST_ROOT_PEM: authority.rootPem,
});

const call = (path: string, init: RequestInit = {}, environment = attestEnv()) =>
  worker.fetch(new Request(`https://ooooh.test${path}`, init), environment);

const post = (path: string, body: string, headers: Record<string, string>) =>
  call(path, { method: "POST", headers: { "content-type": "application/json", ...headers }, body });

const stored = (keyId: string) => env.BUDGET.get<DeviceRecord>(`device:${keyId}`, "json");

const reason = async (res: Response) => {
  expect(res.status).toBe(401);
  return ((await res.json()) as { reason: string }).reason;
};

beforeAll(async () => {
  authority = await makeRoot();
});

beforeEach(async () => {
  const keys = await env.BUDGET.list();
  await Promise.all(keys.keys.map((k) => env.BUDGET.delete(k.name)));
  device = await makeDevice();
  const record: DeviceRecord = {
    publicKey: device.jwk,
    counter: 0,
    createdAt: new Date().toISOString(),
  };
  await env.BUDGET.put(`device:${device.keyId}`, JSON.stringify(record));
});

describe("assertion middleware", () => {
  let upstream: FakeUpstream;
  afterEach(() => vi.unstubAllGlobals());

  it("lets a signed request through, stores the counter, and rates by the verified key", async () => {
    upstream = fakeUpstream([{ body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(decideBody);
    const res = await post("/v1/decide", body, await assertionHeaders(device, body, 1));
    expect(res.status).toBe(200);
    expect((await stored(device.keyId))?.counter).toBe(1);
    expect(upstream.pending()).toBe(0);
    expect(bodyOf(upstream.requests[0])).toMatchObject({ model: "jev-latest" });
    const minute = Math.floor(Date.now() / 60_000);
    expect(await env.BUDGET.get(`rate:${device.keyId}:${minute}`)).toBe("1");
  });

  it("keys the rate limit on the verified device, not the address", async () => {
    upstream = fakeUpstream([{ body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(decideBody);
    const headers = {
      ...(await assertionHeaders(device, body, 1)),
      "cf-connecting-ip": "203.0.113.9",
    };
    expect((await post("/v1/decide", body, headers)).status).toBe(200);
    const minute = Math.floor(Date.now() / 60_000);
    expect(await env.BUDGET.get(`rate:203.0.113.9:${minute}`)).toBeNull();
  });

  it("refuses a request with no assertion headers", async () => {
    const body = JSON.stringify(decideBody);
    expect(await reason(await post("/v1/decide", body, {}))).toBe("bad-assertion");
    expect(await reason(await post("/v1/decide", body, { "x-device": device.keyId }))).toBe(
      "bad-assertion",
    );
    const { "x-assertion": assertion } = await assertionHeaders(device, body, 1);
    expect(await reason(await post("/v1/decide", body, { "x-assertion": assertion }))).toBe(
      "bad-assertion",
    );
    expect((await stored(device.keyId))?.counter).toBe(0);
  });

  it("refuses a device it has never seen", async () => {
    const stranger = await makeDevice();
    const body = JSON.stringify(decideBody);
    const res = await post("/v1/decide", body, await assertionHeaders(stranger, body, 1));
    expect(await reason(res)).toBe("unknown-device");
  });

  it("refuses an assertion signed by another key or over another body", async () => {
    const body = JSON.stringify(decideBody);
    const forger = await makeDevice();
    const forged = await buildAssertion({
      device,
      clientDataHash: await sha256(new TextEncoder().encode(body)),
      counter: 1,
      signer: forger.keys.privateKey,
    });
    const forgedHeaders = { "x-device": device.keyId, "x-assertion": toBase64(forged) };
    expect(await reason(await post("/v1/decide", body, forgedHeaders))).toBe("bad-assertion");

    const otherBody = await assertionHeaders(device, JSON.stringify({ ...decideBody, pad: 1 }), 1);
    expect(await reason(await post("/v1/decide", body, otherBody))).toBe("bad-assertion");

    const otherApp = await assertionHeaders(device, body, 1, "C6UWR42ZAP.com.seanreid.other");
    expect(await reason(await post("/v1/decide", body, otherApp))).toBe("bad-assertion");

    const garbage = {
      "x-device": device.keyId,
      "x-assertion": toBase64(new Uint8Array([1, 2, 3])),
    };
    expect(await reason(await post("/v1/decide", body, garbage))).toBe("bad-assertion");
    expect((await stored(device.keyId))?.counter).toBe(0);
  });

  it("refuses a counter that does not move forward", async () => {
    upstream = fakeUpstream([{ body: jevReply }, { body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(decideBody);
    const headers = await assertionHeaders(device, body, 5);
    expect((await post("/v1/decide", body, headers)).status).toBe(200);
    expect(await reason(await post("/v1/decide", body, headers))).toBe("replay");
    expect(
      await reason(await post("/v1/decide", body, await assertionHeaders(device, body, 4))),
    ).toBe("replay");
    expect((await post("/v1/decide", body, await assertionHeaders(device, body, 6))).status).toBe(
      200,
    );
    expect((await stored(device.keyId))?.counter).toBe(6);
    expect(upstream.pending()).toBe(0);
  });

  it("guards the session routes the same way", async () => {
    const body = "{}";
    expect(await reason(await post("/v1/session/start", body, {}))).toBe("bad-assertion");
    const res = await post("/v1/session/start", body, await assertionHeaders(device, body, 1));
    expect(res.status).toBe(200);
    expect(await res.json()).toMatchObject({ allowed: true, free: true, remainingFree: 2 });
    expect(
      await env.BUDGET.get(`sessions:${device.keyId}:${new Date().toISOString().slice(0, 7)}`),
    ).toBe("1");
  });

  it("leaves health and config open", async () => {
    expect((await call("/health")).status).toBe(200);
    expect((await call("/v1/config")).status).toBe(200);
  });

  it("skips verification when REQUIRE_ATTESTATION is false", async () => {
    upstream = fakeUpstream([{ body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const res = await SELF.fetch("https://ooooh.test/v1/decide", {
      method: "POST",
      headers: { "content-type": "application/json", "x-device": "simulator" },
      body: JSON.stringify(decideBody),
    });
    expect(res.status).toBe(200);
    const minute = Math.floor(Date.now() / 60_000);
    expect(await env.BUDGET.get(`rate:simulator:${minute}`)).toBe("1");
  });
});
