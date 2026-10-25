import "./env";
import { guarded } from "./budget";
import { governorConfig } from "./config";
import { HttpError, json, methodNotAllowed, notFound } from "./http";
import { compact } from "./routes/compact";
import { decide } from "./routes/decide";
import { phrase } from "./routes/phrase";

type Handler = (request: Request, env: Env) => Promise<Response> | Response;

const routes: Record<string, Partial<Record<string, Handler>>> = {
  "/health": { GET: () => json({ ok: true }) },
  "/v1/config": { GET: () => json(governorConfig) },
  "/v1/decide": { POST: guarded("jev", decide) },
  "/v1/compact": { POST: guarded("anthropic", compact) },
  "/v1/phrase": { POST: guarded("anthropic", phrase) },
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
