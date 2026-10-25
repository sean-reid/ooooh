import { fromBase64, sha256 } from "../bytes";
import { readBytes } from "../http";
import { AssertionError, verifyAssertion } from "./assertion";
import { deviceKey, unauthorized, type DeviceRecord } from "./record";
import { settingsFrom } from "./verify";

export type DeviceHandler = (
  request: Request,
  env: Env,
  device: string,
) => Promise<Response> | Response;

export const requiresAttestation = (env: Env) => (env.REQUIRE_ATTESTATION ?? "true") !== "false";

/** Who is calling when nothing is verified: the client's own label, else its address. */
export const callerFrom = (request: Request) =>
  request.headers.get("x-device") ?? request.headers.get("cf-connecting-ip") ?? "unknown";

/**
 * Requires `x-device` and `x-assertion` over the body, and hands the verified key id on.
 * With `REQUIRE_ATTESTATION=false` the route runs as is, keyed on whatever the client says.
 */
export const attested =
  (handler: DeviceHandler) =>
  async (request: Request, env: Env): Promise<Response> => {
    if (!requiresAttestation(env)) return handler(request, env, callerFrom(request));

    const keyId = request.headers.get("x-device");
    const assertion = fromBase64(request.headers.get("x-assertion") ?? "");
    if (!keyId || !assertion?.length) throw unauthorized("bad-assertion");

    const stored = await env.BUDGET.get<DeviceRecord>(deviceKey(keyId), "json");
    if (!stored) throw unauthorized("unknown-device");

    const body = new Uint8Array(await readBytes(request));
    let counter: number;
    try {
      counter = await verifyAssertion(assertion, await sha256(body), stored, settingsFrom(env));
    } catch (e) {
      if (e instanceof AssertionError) throw unauthorized(e.reason);
      throw e;
    }
    await env.BUDGET.put(deviceKey(keyId), JSON.stringify({ ...stored, counter }));
    return handler(new Request(request, { body }), env, keyId);
  };
