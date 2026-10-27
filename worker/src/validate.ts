export class ValidationError extends Error {
  constructor(
    public field: string,
    public expected: string,
  ) {
    super(`${field || "body"}: expected ${expected}`);
  }
}

export type Validator<T> = (value: unknown, path: string) => T;

const join = (path: string, key: string | number) =>
  typeof key === "number" ? `${path}[${key}]` : path ? `${path}.${key}` : key;

export const str: Validator<string> = (v, p) => {
  if (typeof v !== "string") throw new ValidationError(p, "string");
  return v;
};

/** A string of at most `max` characters. */
export const text =
  (max: number): Validator<string> =>
  (v, p) => {
    const value = str(v, p);
    if (value.length > max) throw new ValidationError(p, `at most ${max} characters`);
    return value;
  };

export const num: Validator<number> = (v, p) => {
  if (typeof v !== "number" || !Number.isFinite(v)) throw new ValidationError(p, "number");
  return v;
};

export const bool: Validator<boolean> = (v, p) => {
  if (typeof v !== "boolean") throw new ValidationError(p, "boolean");
  return v;
};

export const oneOf =
  <const T extends readonly string[]>(options: T): Validator<T[number]> =>
  (v, p) => {
    if (typeof v !== "string" || !options.includes(v)) {
      throw new ValidationError(p, `one of ${options.join(", ")}`);
    }
    return v;
  };

export const optional =
  <T>(inner: Validator<T>): Validator<T | undefined> =>
  (v, p) =>
    v === undefined || v === null ? undefined : inner(v, p);

export const array =
  <T>(inner: Validator<T>, max = Infinity): Validator<T[]> =>
  (v, p) => {
    if (!Array.isArray(v)) throw new ValidationError(p, "array");
    if (v.length > max) throw new ValidationError(p, `at most ${max} items`);
    return v.map((item, i) => inner(item, join(p, i)));
  };

export const withDefault =
  <T>(inner: Validator<T>, fallback: T): Validator<T> =>
  (v, p) =>
    v === undefined ? fallback : inner(v, p);

type Shape = Record<string, Validator<unknown>>;
type Output<S extends Shape> = { [K in keyof S]: ReturnType<S[K]> };

export const obj =
  <S extends Shape>(shape: S): Validator<Output<S>> =>
  (v, p) => {
    if (typeof v !== "object" || v === null || Array.isArray(v)) {
      throw new ValidationError(p, "object");
    }
    const record = v as Record<string, unknown>;
    const out: Record<string, unknown> = {};
    for (const key of Object.keys(shape)) {
      out[key] = shape[key](record[key], join(p, key));
    }
    return out as Output<S>;
  };
