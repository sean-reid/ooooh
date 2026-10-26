import { HttpError } from "../http";

/**
 * What `/v1/attest` stores per key id. The counter lives in the device's `DeviceCounter`;
 * a record that still carries one is moved there on its next use.
 */
export interface DeviceRecord {
  publicKey: JsonWebKey;
  createdAt: string;
  counter?: number;
}

export const deviceKey = (keyId: string) => `device:${keyId}`;

/** The public key under a key id never changes, so a read may serve from the colo's cache. */
export const deviceCacheSeconds = 300;

export const readDevice = (env: Env, keyId: string) =>
  env.BUDGET.get<DeviceRecord>(deviceKey(keyId), { type: "json", cacheTtl: deviceCacheSeconds });

export const counterFor = (env: Env, keyId: string) => env.DEVICE_COUNTER.getByName(keyId);

export const unauthorized = (reason: string) =>
  new HttpError(401, { error: "unauthorized", reason });
