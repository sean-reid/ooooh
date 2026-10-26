// Helpers that need the Workers runtime: the test Worker itself, its KV namespace, and its objects.
import { env, reset, SELF } from "cloudflare:test";
import { expect } from "vitest";
import { deviceKey, type DeviceRecord } from "../src/attest/record";
import type { Provider } from "../src/budget";
import { makeDevice, type TestRoot } from "./appattest";
import { jsonRequest } from "./request";

export const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  SELF.fetch(jsonRequest(path, body, headers));

/** Every key in the namespace and every object's storage, so one test's counts never reach the next. */
export const wipeStorage = () => reset();

/** The test Env with attestation on against `authority` instead of Apple's root. */
export const attestEnv = (authority: TestRoot, overrides: Partial<Env> = {}): Env => ({
  ...env,
  REQUIRE_ATTESTATION: "true",
  APP_ATTEST_ENVIRONMENT: "development",
  APP_ATTEST_ROOT_PEM: authority.rootPem,
  ...overrides,
});

export const counterOf = (keyId: string) => env.DEVICE_COUNTER.getByName(keyId).current();

export const today = () => new Date().toISOString().slice(0, 10);

/** What the provider's object holds for the day. */
export const spent = (provider: Provider, day = today()) =>
  env.PROVIDER_BUDGET.getByName(provider).spent(day);

export const reason = async (res: Response) => {
  expect(res.status).toBe(401);
  return ((await res.json()) as { reason: string }).reason;
};

/** A fresh device written straight to KV as if it had attested. */
export const seedDevice = async () => {
  const device = await makeDevice();
  const record: DeviceRecord = { publicKey: device.jwk, createdAt: new Date().toISOString() };
  await env.BUDGET.put(deviceKey(device.keyId), JSON.stringify(record));
  return device;
};
