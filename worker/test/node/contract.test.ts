import { describe, expect, it } from "vitest";
import worker from "../../src/index";
import { memoryKV } from "../kv";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { compactBody, decideBody, phraseBody, speakBody, state } from "../upstream";
import { secret, vars } from "./env";

// Real provider calls. Each runs only when its key is set, in the environment or in .dev.vars.
const decisionFixture = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../fixtures/synthetic/estimate/decision.fixture.json",
);

const env: Env = {
  ...vars,
  BUDGET: memoryKV(),
  TYPESAFE_API_KEY: secret("TYPESAFE_API_KEY"),
  ANTHROPIC_API_KEY: secret("ANTHROPIC_API_KEY"),
  ANTHROPIC_AUTH_TOKEN: secret("ANTHROPIC_AUTH_TOKEN"),
  ELEVENLABS_API_KEY: secret("ELEVENLABS_API_KEY"),
};
const anthropic = env.ANTHROPIC_AUTH_TOKEN ?? env.ANTHROPIC_API_KEY;

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

  it.skipIf(!anthropic)("Haiku returns a patch that validates", async () => {
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

  it.skipIf(!anthropic)("Sonnet phrases one short sentence", async () => {
    const res = await post("/v1/phrase", phraseBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const { text } = (await res.json()) as { text: string };
    expect(text.trim().split(/\s+/).length).toBeLessThanOrEqual(15);
    expect(text).not.toMatch(/\bI\b/);
  });

  // Opus on 20 lines of the decision fixture: about 3,000 tokens in and 800 out.
  it.skipIf(!anthropic)(
    "Opus writes notes whose spans lie in the transcript",
    async () => {
      type Segment = { text: string; start: number; end: number };
      const fixture = JSON.parse(readFileSync(decisionFixture, "utf8")) as { segments: Segment[] };
      const transcript = fixture.segments
        .slice(0, 20)
        .map(({ text, start, end }) => ({ text, start, end }));
      const notesState = {
        ...state,
        currentThread: "Carver Street or the apartment by the park, money against time.",
        mainIdeas: [
          {
            id: "money-versus-time",
            text: "The trade is a thousand a month against seven and a half hours a week.",
            resolved: false,
          },
        ],
        openQuestions: [],
        recentTopics: ["apartments", "commute"],
        mode: "converging",
      };
      const res = await post("/v1/notes", { state: notesState, transcript });
      expect(res.status, await res.clone().text()).toBe(200);
      type Item = { id: string; text: string; span?: { start: number; end: number } };
      const body = (await res.json()) as {
        notes: { title: string; summary?: string } & Record<string, Item[] | string | undefined>;
        usage: { inputTokens: number; outputTokens: number };
      };
      const sections = [
        "ideas",
        "decisions",
        "questions",
        "insights",
        "actions",
        "openThreads",
        "quotes",
      ];
      const counts = Object.fromEntries(
        sections.map((name) => [name, (body.notes[name] as Item[]).length]),
      );
      console.log(`notes title: ${body.notes.title}`, counts, body.usage);
      expect(body.notes.title.trim().length).toBeGreaterThan(0);
      const items = sections.flatMap((name) => body.notes[name] as Item[]);
      expect(items.length).toBeGreaterThan(0);
      const last = transcript.at(-1)!.end;
      for (const item of items) {
        if (!item.span) continue;
        expect(item.span.start).toBeGreaterThanOrEqual(0);
        expect(item.span.end).toBeLessThanOrEqual(last);
        expect(item.span.start).toBeLessThanOrEqual(item.span.end);
      }
      expect(new Set(items.map((i) => i.id)).size).toBe(items.length);
      expect(body.usage.inputTokens).toBeGreaterThan(0);
    },
    180_000,
  );

  it.skipIf(!env.ELEVENLABS_API_KEY)("ElevenLabs speaks one short line", async () => {
    const res = await post("/v1/speak", speakBody);
    expect(res.status, await res.clone().text()).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/mpeg");
    expect(Number(res.headers.get("x-character-count"))).toBeGreaterThan(0);
    expect((await res.arrayBuffer()).byteLength).toBeGreaterThan(1000);
  });
});
