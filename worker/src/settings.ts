import type { AttestationSettings } from "./attest/verify";
import type { Provider } from "./budget";
import type { StoreKitSettings } from "./storekit/verify";

/** Every var in wrangler.jsonc and what a missing or malformed value falls back to. */
export const defaults = {
  JEV_DAILY_TOKENS: 20_000_000,
  ANTHROPIC_DAILY_TOKENS: 700_000,
  ELEVENLABS_DAILY_CHARACTERS: 20_000,
  DEVICE_MINUTE_REQUESTS: 60,
  DEVICE_DAILY_JEV_TOKENS: 1_500_000,
  DEVICE_DAILY_ANTHROPIC_TOKENS: 100_000,
  DEVICE_DAILY_ELEVENLABS_CHARACTERS: 6_000,
  ELEVENLABS_VOICE_ID: "SAz9YHcvj6GT2YYXdXww",
  REQUIRE_ATTESTATION: "true",
  APP_ATTEST_APP_ID: "C6UWR42ZAP.com.seanreid.ooooh",
  APP_ATTEST_ENVIRONMENT: "production",
  APP_BUNDLE_ID: "com.seanreid.ooooh",
  APP_STORE_ENVIRONMENTS: "Production,Sandbox",
  FREE_SESSIONS_PER_MONTH: 3,
  FREE_PROMPT_MINUTES: 20,
} as const;

export type VarName = keyof typeof defaults;

export interface Settings {
  dailyLimit: Record<Provider, number>;
  deviceDailyLimit: Record<Provider, number>;
  deviceMinuteRequests: number;
  freeSessionsPerMonth: number;
  freePromptMinutes: number;
  voiceId: string;
  requireAttestation: boolean;
  attestation: AttestationSettings;
  storeKit: StoreKitSettings;
}

type NumberVar = { [K in VarName]: (typeof defaults)[K] extends number ? K : never }[VarName];
type StringVar = Exclude<VarName, NumberVar>;

/** A positive, finite number from a var, else the default; a typo must not disable a cap. */
const number = (env: Env, name: NumberVar) => {
  const value = env[name];
  if (value === undefined || value === "") return defaults[name];
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : defaults[name];
};

const text = (env: Env, name: StringVar) => env[name] || defaults[name];

/** One of `options`, else the default; the default is the safe side for every enum here. */
const oneOf = <const T extends readonly string[]>(env: Env, name: StringVar, options: T) => {
  const value = env[name];
  return (
    (options as readonly string[]).includes(value ?? "") ? value : defaults[name]
  ) as T[number];
};

/** A comma-separated subset of `options`, else the default; one unknown name voids the whole var. */
const listOf = <const T extends readonly string[]>(env: Env, name: StringVar, options: T) => {
  const names = (env[name] || defaults[name]).split(",").map((n) => n.trim());
  const known = names.every((n) => (options as readonly string[]).includes(n));
  return (known ? names : defaults[name].split(",")) as T[number][];
};

const read = (env: Env): Settings => ({
  dailyLimit: {
    jev: number(env, "JEV_DAILY_TOKENS"),
    anthropic: number(env, "ANTHROPIC_DAILY_TOKENS"),
    elevenlabs: number(env, "ELEVENLABS_DAILY_CHARACTERS"),
  },
  deviceDailyLimit: {
    jev: number(env, "DEVICE_DAILY_JEV_TOKENS"),
    anthropic: number(env, "DEVICE_DAILY_ANTHROPIC_TOKENS"),
    elevenlabs: number(env, "DEVICE_DAILY_ELEVENLABS_CHARACTERS"),
  },
  deviceMinuteRequests: number(env, "DEVICE_MINUTE_REQUESTS"),
  freeSessionsPerMonth: number(env, "FREE_SESSIONS_PER_MONTH"),
  freePromptMinutes: number(env, "FREE_PROMPT_MINUTES"),
  voiceId: text(env, "ELEVENLABS_VOICE_ID"),
  requireAttestation: oneOf(env, "REQUIRE_ATTESTATION", ["true", "false"]) === "true",
  attestation: {
    appId: text(env, "APP_ATTEST_APP_ID"),
    environment: oneOf(env, "APP_ATTEST_ENVIRONMENT", ["development", "production"]),
    rootPem: env.APP_ATTEST_ROOT_PEM,
  },
  storeKit: {
    bundleId: text(env, "APP_BUNDLE_ID"),
    environments: listOf(env, "APP_STORE_ENVIRONMENTS", ["Sandbox", "Production"]),
    rootPem: env.APPLE_ROOT_PEM,
  },
});

const parsed = new WeakMap<Env, Settings>();

/** The vars read and checked once per Env object, which the runtime keeps for the isolate's life. */
export const settings = (env: Env): Settings => {
  let value = parsed.get(env);
  if (!value) {
    value = read(env);
    parsed.set(env, value);
  }
  return value;
};
