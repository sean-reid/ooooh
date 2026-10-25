import "./env";
import { attested } from "./attest/device";
import { guarded } from "./budget";
import { governorConfig } from "./config";
import { HttpError, json, methodNotAllowed, notFound } from "./http";
import { compact } from "./routes/compact";
import { decide } from "./routes/decide";
import { notesRoute } from "./routes/notes";
import { phrase } from "./routes/phrase";
import { attest, challenge } from "./routes/attest";
import { endSession, startSession } from "./routes/session";
import { speak } from "./routes/speak";

type Handler = (request: Request, env: Env) => Promise<Response> | Response;

const routes: Record<string, Partial<Record<string, Handler>>> = {
  "/health": { GET: (_, env) => json({ ok: true, version: env.CF_VERSION_METADATA?.id ?? null }) },
  "/v1/config": { GET: () => json(governorConfig) },
  "/v1/challenge": { GET: challenge },
  "/v1/attest": { POST: attest },
  "/v1/session/start": { POST: attested(startSession) },
  "/v1/session/end": { POST: attested(endSession) },
  "/v1/decide": { POST: attested(guarded("jev", decide)) },
  "/v1/compact": { POST: attested(guarded("anthropic", compact)) },
  "/v1/phrase": { POST: attested(guarded("anthropic", phrase)) },
  "/v1/notes": { POST: attested(guarded("anthropic", notesRoute)) },
  "/v1/speak": { POST: attested(guarded("elevenlabs", speak)) },
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    try {
      const route = routes[url.pathname];
      if (!route) throw notFound();
      const handler = route[request.method];
      if (!handler) throw methodNotAllowed(Object.keys(route).join(", "));
      return await handler(request, env);
    } catch (e) {
      if (e instanceof HttpError) return e.response();
      console.error(e);
      return json({ error: "internal" }, 500);
    }
  },
} satisfies ExportedHandler<Env>;
