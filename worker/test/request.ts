// Requests the way the phone sends them, for both the Workers and the node project.
import { startSession } from "../src/routes/session";

export const origin = "https://ooooh.test";

/** A JSON POST; a string body goes through as is, so an assertion signed over it still matches. */
export const jsonRequest = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  new Request(`${origin}${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });

export const startRequest = () => new Request(`${origin}/v1/session/start`, { method: "POST" });

/** Opens a session past the attestation and budget wrappers, the way the direct tests do. */
export const openSession = (env: Env, device: string, now?: Date) =>
  startSession(startRequest(), env, device, now);
