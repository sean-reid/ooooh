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

export const requireSecret = (value: string | undefined, name: string) => {
  if (!value) throw new HttpError(500, { error: "missing secret", name });
  return value;
};

export const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
