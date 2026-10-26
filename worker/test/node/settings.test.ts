import { describe, expect, it } from "vitest";
import { defaults, settings } from "../../src/settings";
import { memoryKV, noCounter } from "../kv";
import { wrangler } from "./env";

const env = (vars: Record<string, string> = {}) =>
  ({ BUDGET: memoryKV(), DEVICE_COUNTER: noCounter, ...vars }) as Env;

describe("settings", () => {
  it("reads every var wrangler.jsonc names, with the same default in both places", () => {
    const names = Object.keys(defaults).sort();
    expect(Object.keys(wrangler.vars).sort()).toEqual(names);
    for (const name of names) {
      expect(wrangler.vars[name], name).toBe(String(defaults[name as keyof typeof defaults]));
    }
  });

  it("gives production every var the top level has", () => {
    expect(Object.keys(wrangler.env.production.vars).sort()).toEqual(
      Object.keys(wrangler.vars).sort(),
    );
  });

  it("falls back to the defaults when a var is missing, empty, or malformed", () => {
    const bare = settings(env());
    expect(bare.dailyLimit).toEqual({ jev: 20_000_000, anthropic: 700_000, elevenlabs: 20_000 });
    expect(bare.deviceMinuteRequests).toBe(60);
    expect(bare.freeSessionsPerMonth).toBe(3);
    expect(bare.freePromptMinutes).toBe(20);
    expect(bare.voiceId).toBe("SAz9YHcvj6GT2YYXdXww");
    expect(bare.requireAttestation).toBe(true);
    expect(bare.attestation).toEqual({
      appId: "C6UWR42ZAP.com.seanreid.ooooh",
      environment: "production",
      rootPem: undefined,
    });
    expect(bare.storeKit).toEqual({
      bundleId: "com.seanreid.ooooh",
      environment: "Production",
      rootPem: undefined,
    });

    const bad = settings(
      env({
        JEV_DAILY_TOKENS: "abc",
        DEVICE_MINUTE_REQUESTS: "-5",
        FREE_PROMPT_MINUTES: "",
        REQUIRE_ATTESTATION: "no",
        APP_ATTEST_ENVIRONMENT: "staging",
        APP_STORE_ENVIRONMENT: "sandbox",
      }),
    );
    expect(bad.dailyLimit.jev).toBe(20_000_000);
    expect(bad.deviceMinuteRequests).toBe(60);
    expect(bad.freePromptMinutes).toBe(20);
    expect(bad.requireAttestation).toBe(true);
    expect(bad.attestation.environment).toBe("production");
    expect(bad.storeKit.environment).toBe("Production");
  });

  it("takes a well-formed var over its default", () => {
    const set = settings(
      env({
        ANTHROPIC_DAILY_TOKENS: "1000",
        FREE_SESSIONS_PER_MONTH: "1",
        REQUIRE_ATTESTATION: "false",
        APP_ATTEST_ENVIRONMENT: "development",
        APP_STORE_ENVIRONMENT: "Sandbox",
        APP_ATTEST_ROOT_PEM: "attest-root",
        APPLE_ROOT_PEM: "apple-root",
      }),
    );
    expect(set.dailyLimit.anthropic).toBe(1000);
    expect(set.freeSessionsPerMonth).toBe(1);
    expect(set.requireAttestation).toBe(false);
    expect(set.attestation).toMatchObject({ environment: "development", rootPem: "attest-root" });
    expect(set.storeKit).toMatchObject({ environment: "Sandbox", rootPem: "apple-root" });
  });

  it("reads one Env object once", () => {
    const shared = env();
    expect(settings(shared)).toBe(settings(shared));
    expect(settings(env())).not.toBe(settings(shared));
  });
});
