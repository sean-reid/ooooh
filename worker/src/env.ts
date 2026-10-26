import type { DeviceCounter } from "./attest/counter";

declare global {
  interface Env {
    BUDGET: KVNamespace;
    DEVICE_COUNTER: DurableObjectNamespace<DeviceCounter>;
    CF_VERSION_METADATA?: WorkerVersionMetadata;
    TYPESAFE_API_KEY?: string;
    ANTHROPIC_API_KEY?: string;
    ANTHROPIC_AUTH_TOKEN?: string;
    ELEVENLABS_API_KEY?: string;
    JEV_DAILY_TOKENS?: string;
    ANTHROPIC_DAILY_TOKENS?: string;
    ELEVENLABS_DAILY_CHARACTERS?: string;
    DEVICE_MINUTE_REQUESTS?: string;
    APP_ATTEST_APP_ID?: string;
    APP_ATTEST_ENVIRONMENT?: string;
    APP_ATTEST_ROOT_PEM?: string;
    REQUIRE_ATTESTATION?: string;
    APP_BUNDLE_ID?: string;
    APP_STORE_ENVIRONMENT?: string;
    APPLE_ROOT_PEM?: string;
    FREE_SESSIONS_PER_MONTH?: string;
    FREE_PROMPT_MINUTES?: string;
  }
}

export {};
