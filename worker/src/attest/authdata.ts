import { equalBytes, sha256, type Bytes } from "../bytes";

// Apple's authenticator data, shared by an attestation and an assertion: the RP ID hash in the
// first 32 bytes, one flags byte, then the big-endian counter at byte 33.

export const rpIdMatches = async (authData: Bytes, appId: string) =>
  equalBytes(authData.subarray(0, 32), await sha256(new TextEncoder().encode(appId)));

export const counterIn = (authData: Bytes) =>
  new DataView(authData.buffer, authData.byteOffset + 33, 4).getUint32(0);
