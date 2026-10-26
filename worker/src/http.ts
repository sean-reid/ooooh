import { ValidationError, type Validator } from "./validate";

export const MAX_BODY_BYTES = 256 * 1024;

export const json = (body: unknown, status = 200, headers: HeadersInit = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", ...headers },
  });

export class HttpError extends Error {
  constructor(
    public status: number,
    public body: Record<string, unknown>,
    public headers: HeadersInit = {},
  ) {
    super(String(body.error ?? status));
  }

  response() {
    return json(this.body, this.status, this.headers);
  }
}

export const notFound = () => new HttpError(404, { error: "not found" });
export const methodNotAllowed = (allow: string) =>
  new HttpError(405, { error: "method not allowed" }, { allow });

/** The body as bytes, refused past `MAX_BODY_BYTES` before and after reading. */
export async function readBytes(request: Request): Promise<ArrayBuffer> {
  const declared = Number(request.headers.get("content-length") ?? 0);
  if (declared > MAX_BODY_BYTES) {
    throw new HttpError(413, { error: "body too large", limit: MAX_BODY_BYTES });
  }
  const bytes = await request.arrayBuffer();
  if (bytes.byteLength > MAX_BODY_BYTES) {
    throw new HttpError(413, { error: "body too large", limit: MAX_BODY_BYTES });
  }
  return bytes;
}

export async function readBody<T>(request: Request, validator: Validator<T>): Promise<T> {
  const bytes = await readBytes(request);
  let parsed: unknown;
  try {
    parsed = JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    throw new HttpError(422, { error: "invalid json", field: "" });
  }
  try {
    return validator(parsed, "");
  } catch (e) {
    if (e instanceof ValidationError) {
      throw new HttpError(422, { error: "invalid", field: e.field, expected: e.expected });
    }
    throw e;
  }
}

/** The var's name goes to the log; the client learns only that the Worker is misconfigured. */
export const missingSecret = (name: string) => {
  console.error("missing secret", name);
  return new HttpError(500, { error: "misconfigured" });
};

export const requireSecret = (value: string | undefined, name: string) => {
  if (!value) throw missingSecret(name);
  return value;
};

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/** Seconds from a Retry-After header, a count or an HTTP date, clamped to 1..60. */
export const retryAfterFrom = (
  header: string | null | undefined,
  fallback = 5,
  now = Date.now(),
): number => {
  if (!header) return fallback;
  const seconds = Number(header);
  if (Number.isFinite(seconds)) return seconds > 0 ? Math.min(Math.ceil(seconds), 60) : fallback;
  const at = Date.parse(header);
  if (Number.isNaN(at)) return fallback;
  return Math.min(Math.max(1, Math.ceil((at - now) / 1000)), 60);
};

/** Retries wait at most this long; a provider asking for more gets the 503 straight away. */
export const maxRetryWaitMs = 2000;
