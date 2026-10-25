import { env, SELF } from "cloudflare:test";
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import worker from "../src/index";
import type { DeviceRecord } from "../src/attest/record";
import { sha256, toBase64 } from "../src/bytes";
import {
  assertionHeaders,
  buildAssertion,
  makeDevice,
  makeRoot,
  type Device,
  type SignedRequest,
  type TestRoot,
} from "./appattest";
import {
  bodyOf,
  compactBody,
  decideBody,
  fakeUpstream,
  haikuReply,
  jevReply,
  type FakeUpstream,
} from "./upstream";

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

const sign = (path: string, body: string, counter: number, rest: Partial<SignedRequest> = {}) =>
  assertionHeaders(device, { path, body, counter, ...rest });

const stored = (keyId: string) => env.BUDGET.get<DeviceRecord>(`device:${keyId}`, "json");

const now = () => Math.floor(Date.now() / 1000);

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
    const res = await post("/v1/decide", body, await sign("/v1/decide", body, 1));
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
      ...(await sign("/v1/decide", body, 1)),
      "cf-connecting-ip": "203.0.113.9",
    };
    expect((await post("/v1/decide", body, headers)).status).toBe(200);
    const minute = Math.floor(Date.now() / 60_000);
    expect(await env.BUDGET.get(`rate:203.0.113.9:${minute}`)).toBeNull();
  });

  it("refuses a request missing any of the three headers", async () => {
    const body = JSON.stringify(decideBody);
    expect(await reason(await post("/v1/decide", body, {}))).toBe("bad-assertion");
    expect(await reason(await post("/v1/decide", body, { "x-device": device.keyId }))).toBe(
      "bad-assertion",
    );
    const { "x-assertion": assertion, "x-assertion-time": time } = await sign(
      "/v1/decide",
      body,
      1,
    );
    expect(await reason(await post("/v1/decide", body, { "x-assertion": assertion }))).toBe(
      "bad-assertion",
    );
    const noTime = { "x-device": device.keyId, "x-assertion": assertion };
    expect(await reason(await post("/v1/decide", body, noTime))).toBe("bad-assertion");
    const wordy = { ...noTime, "x-assertion-time": `${time}s` };
    expect(await reason(await post("/v1/decide", body, wordy))).toBe("bad-assertion");
    expect((await stored(device.keyId))?.counter).toBe(0);
  });

  it("refuses a device it has never seen", async () => {
    const stranger = await makeDevice();
    const body = JSON.stringify(decideBody);
    const headers = await assertionHeaders(stranger, { path: "/v1/decide", body, counter: 1 });
    expect(await reason(await post("/v1/decide", body, headers))).toBe("unknown-device");
  });

  it("refuses an assertion signed by another key or over another body", async () => {
    const body = JSON.stringify(decideBody);
    const forger = await makeDevice();
    const good = await sign("/v1/decide", body, 1);
    const forged = await buildAssertion({
      device,
      clientDataHash: await sha256(new TextEncoder().encode(body)),
      counter: 1,
      signer: forger.keys.privateKey,
    });
    const forgedHeaders = { ...good, "x-assertion": toBase64(forged) };
    expect(await reason(await post("/v1/decide", body, forgedHeaders))).toBe("bad-assertion");

    const otherBody = await sign("/v1/decide", JSON.stringify({ ...decideBody, pad: 1 }), 1);
    expect(await reason(await post("/v1/decide", body, otherBody))).toBe("bad-assertion");

    const otherApp = await sign("/v1/decide", body, 1, { appId: "C6UWR42ZAP.com.seanreid.other" });
    expect(await reason(await post("/v1/decide", body, otherApp))).toBe("bad-assertion");

    const garbage = { ...good, "x-assertion": toBase64(new Uint8Array([1, 2, 3])) };
    expect(await reason(await post("/v1/decide", body, garbage))).toBe("bad-assertion");
    expect((await stored(device.keyId))?.counter).toBe(0);
  });

  it("binds an assertion to the route it was signed for", async () => {
    upstream = fakeUpstream([{ body: haikuReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(compactBody);
    const headers = await sign("/v1/compact", body, 1);
    expect(await reason(await post("/v1/notes", body, headers))).toBe("bad-assertion");
    expect((await stored(device.keyId))?.counter).toBe(0);
    expect((await post("/v1/compact", body, headers)).status).toBe(200);
    expect((await stored(device.keyId))?.counter).toBe(1);
    expect(upstream.pending()).toBe(0);
  });

  it("binds an assertion to the time it carries, within 300 seconds of its own clock", async () => {
    upstream = fakeUpstream([{ body: jevReply }, { body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(decideBody);
    const old = await sign("/v1/decide", body, 1, { time: now() - 301 });
    expect(await reason(await post("/v1/decide", body, old))).toBe("stale");
    const far = await sign("/v1/decide", body, 1, { time: now() + 301 });
    expect(await reason(await post("/v1/decide", body, far))).toBe("stale");

    const signedAt = now() - 299;
    const shifted = { ...(await sign("/v1/decide", body, 1, { time: signedAt })) };
    shifted["x-assertion-time"] = String(signedAt + 1);
    expect(await reason(await post("/v1/decide", body, shifted))).toBe("bad-assertion");
    expect((await stored(device.keyId))?.counter).toBe(0);

    const ahead = await sign("/v1/decide", body, 1, { time: now() + 299 });
    expect((await post("/v1/decide", body, ahead)).status).toBe(200);
    const behind = await sign("/v1/decide", body, 2, { time: now() - 299 });
    expect((await post("/v1/decide", body, behind)).status).toBe(200);
    expect((await stored(device.keyId))?.counter).toBe(2);
    expect(upstream.pending()).toBe(0);
  });

  it("refuses a counter that does not move forward", async () => {
    upstream = fakeUpstream([{ body: jevReply }, { body: jevReply }]);
    vi.stubGlobal("fetch", upstream.fetch);
    const body = JSON.stringify(decideBody);
    const headers = await sign("/v1/decide", body, 5);
    expect((await post("/v1/decide", body, headers)).status).toBe(200);
    expect(await reason(await post("/v1/decide", body, headers))).toBe("replay");
    expect(await reason(await post("/v1/decide", body, await sign("/v1/decide", body, 4)))).toBe(
      "replay",
    );
    expect((await post("/v1/decide", body, await sign("/v1/decide", body, 6))).status).toBe(200);
    expect((await stored(device.keyId))?.counter).toBe(6);
    expect(upstream.pending()).toBe(0);
  });

  it("guards the session routes the same way", async () => {
    const body = "{}";
    expect(await reason(await post("/v1/session/start", body, {}))).toBe("bad-assertion");
    const res = await post("/v1/session/start", body, await sign("/v1/session/start", body, 1));
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
