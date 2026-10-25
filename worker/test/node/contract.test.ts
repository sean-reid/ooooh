import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import worker from "../../src/index";
import { compactBody, decideBody, phraseBody } from "../upstream";

// Real provider calls. Each runs only when its key is set, in the environment or in .dev.vars.
const devVars = resolve(dirname(fileURLToPath(import.meta.url)), "../../.dev.vars");

const secret = (name: string): string | undefined => {
  if (process.env[name]) return process.env[name];
  if (!existsSync(devVars)) return undefined;
  const line = readFileSync(devVars, "utf8")
    .split("\n")
    .find((l) => l.startsWith(`${name}=`));
  return (
    line
      ?.slice(name.length + 1)
      .trim()
      .replace(/^"|"$/g, "") || undefined
  );
};

const env: Env = {
  CONFIG_VERSION: "1",
  TYPESAFE_API_KEY: secret("TYPESAFE_API_KEY"),
  ANTHROPIC_API_KEY: secret("ANTHROPIC_API_KEY"),
};

const post = (path: string, body: unknown) =>
  worker.fetch(
    new Request(`https://ooooh.test${path}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(body),
    }),
    env,
  );

describe("provider contracts", () => {
  it.skipIf(!env.TYPESAFE_API_KEY)("Jev answers the six questions", async () => {
    const res = await post("/v1/decide", decideBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const body = (await res.json()) as {
      answers: Record<string, Record<string, number | string>>;
      usage: { jevInputTokens: number };
    };
    for (const name of ["goodMoment", "seemsFinished"]) {
      expect(body.answers[name].probability).toBeGreaterThanOrEqual(0);
      expect(body.answers[name].probability).toBeLessThanOrEqual(1);
    }
    for (const name of ["articulationDifficulty", "momentum"]) {
      expect(body.answers[name].score).toBeGreaterThanOrEqual(1);
      expect(body.answers[name].score).toBeLessThanOrEqual(5);
    }
    expect(typeof body.answers.intervention.choice).toBe("string");
    expect(["none", "recall", "wrapUp"]).toContain(body.answers.addressesApp.choice);
    expect(body.usage.jevInputTokens).toBeGreaterThan(0);
  });

  it.skipIf(!env.ANTHROPIC_API_KEY)("Haiku returns a patch that validates", async () => {
    const res = await post("/v1/compact", compactBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const body = (await res.json()) as {
      patch: { add: unknown[]; resolve: string[]; remove: string[] };
      usage: { inputTokens: number; outputTokens: number };
    };
    expect(Array.isArray(body.patch.add)).toBe(true);
    expect(body.usage.inputTokens).toBeGreaterThan(0);
    expect(body.usage.outputTokens).toBeGreaterThan(0);
  });

  it.skipIf(!env.ANTHROPIC_API_KEY)("Sonnet phrases one short sentence", async () => {
    const res = await post("/v1/phrase", phraseBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const { text } = (await res.json()) as { text: string };
    expect(text.trim().split(/\s+/).length).toBeLessThanOrEqual(15);
    expect(text).not.toMatch(/\bI\b/);
  });
});
