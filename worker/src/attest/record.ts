import { HttpError } from "../http";

/** What `/v1/attest` stores per key id, with the last counter an assertion carried. */
export interface DeviceRecord {
  publicKey: JsonWebKey;
  counter: number;
  createdAt: string;
}

export const deviceKey = (keyId: string) => `device:${keyId}`;

export const unauthorized = (reason: string) =>
  new HttpError(401, { error: "unauthorized", reason });
