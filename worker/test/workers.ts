// Helpers that need the Workers runtime: the test Worker itself, its KV namespace, and its objects.
import { createExecutionContext, env, reset, waitOnExecutionContext } from "cloudflare:test";
import { expect } from "vitest";
import { deviceKey, type DeviceRecord } from "../src/attest/record";
import type { Provider } from "../src/budget";
import worker from "../src/index";
import { makeDevice, type TestRoot } from "./appattest";
import { jsonRequest } from "./request";

const contexts: ExecutionContext[] = [];

/** A JSON POST through the Worker, with the work it leaves in waitUntil kept for `settled`. */
export const post = (path: string, body: unknown, headers: Record<string, string> = {}) => {
  const ctx = createExecutionContext();
  contexts.push(ctx);
  return worker.fetch(jsonRequest(path, body, headers), env, ctx);
};

/** Waits for the background work of every `post` so far. */
export const settled = async () => {
  for (const ctx of contexts.splice(0)) await waitOnExecutionContext(ctx);
};

/** Every key in the namespace and every object's storage, once the work before it has landed, so one test's counts never reach the next. */
export const wipeStorage = async () => {
  await settled();
  await reset();
};

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
export const thisMonth = () => new Date().toISOString().slice(0, 7);

/** Free sessions the device's object has counted for the month. */
export const sessionsOf = (device: string, month = thisMonth()) =>
  env.DEVICE_COUNTER.getByName(device).sessions(month);

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
