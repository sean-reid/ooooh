import { beforeAll, describe, expect, it } from "vitest";
import worker from "../../src/index";
import { memoryKV } from "../kv";
import { memoryObjects } from "../objects";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { cueQuestions, questions, questionsVersion } from "../../src/jev/questions";
import type { StatePatch } from "../../src/routes/compact";
import { sectionNames } from "../../src/routes/notes";
import { compactState, existingIds, listNames } from "../../src/schema";
import { jsonRequest } from "../request";
import { compactBody, decideBody, opusNotes, phraseBody, speakBody, state } from "../upstream";
import { secret } from "./env";

// Real provider calls. Each runs only when its key is set, in the environment or in .dev.vars.
// The Worker does not enforce any assertion here, so a reply shaped like the fixtures in
// upstream.ts fails and a real answer about the transcript passes.
const decisionFixture = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../fixtures/synthetic/estimate/decision.fixture.json",
);

const env = {
  REQUIRE_ATTESTATION: "false",
  BUDGET: memoryKV(),
  ...memoryObjects(),
  TYPESAFE_API_KEY: secret("TYPESAFE_API_KEY"),
  ANTHROPIC_API_KEY: secret("ANTHROPIC_API_KEY"),
  ANTHROPIC_AUTH_TOKEN: secret("ANTHROPIC_AUTH_TOKEN"),
  ELEVENLABS_API_KEY: secret("ELEVENLABS_API_KEY"),
} as Env;
const anthropic = env.ANTHROPIC_AUTH_TOKEN ?? env.ANTHROPIC_API_KEY;

const post = (path: string, body: unknown) => worker.fetch(jsonRequest(path, body), env);

describe("provider contracts", () => {
  beforeAll(async () => {
    expect((await post("/v1/session/start", {})).status).toBe(200);
  });

  it.skipIf(!env.TYPESAFE_API_KEY)("Jev answers the question list, and nothing else", async () => {
    const res = await post("/v1/decide", decideBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const body = (await res.json()) as {
      answers: { cues: Record<string, number> } & Record<
        string,
        { probability?: number; score?: number; confidence?: number; choice?: string }
      >;
      questionsVersion: number;
      usage: { jevInputTokens: number };
    };
    const { cues, ...answers } = body.answers;
    expect([...Object.keys(answers), ...Object.keys(cues)].sort()).toEqual(
      Object.keys(questions).sort(),
    );
    expect(body.questionsVersion).toBe(questionsVersion);

    for (const name of ["goodMoment", "seemsFinished"]) {
      expect(answers[name].probability, name).toBeGreaterThanOrEqual(0);
      expect(answers[name].probability, name).toBeLessThanOrEqual(1);
    }
    for (const name of Object.keys(cueQuestions)) {
      expect(cues[name], name).toBeGreaterThanOrEqual(0);
      expect(cues[name], name).toBeLessThanOrEqual(1);
    }
    for (const name of ["articulationDifficulty", "momentum"]) {
      expect(answers[name].score, name).toBeGreaterThanOrEqual(1);
      expect(answers[name].score, name).toBeLessThanOrEqual(5);
      expect(answers[name].confidence, name).toBeGreaterThanOrEqual(0);
      expect(answers[name].confidence, name).toBeLessThanOrEqual(1);
    }
    expect(Object.keys(questions.intervention.criteria)).toContain(answers.intervention.choice);
    // The speaker is weighing the queue against the sync layer and talking to nobody.
    expect(answers.addressesApp.choice).toBe("none");
    expect(answers.seemsFinished.probability).toBeLessThan(0.5);
    expect(body.usage.jevInputTokens).toBeGreaterThan(0);
  });

  it.skipIf(!anthropic)("Haiku patches the state in the transcript's own terms", async () => {
    const res = await post("/v1/compact", compactBody);
    expect(res.status, await res.clone().text()).toBe(200);
    const { patch, usage } = (await res.json()) as {
      patch: StatePatch;
      usage: { inputTokens: number; outputTokens: number };
    };
    const ids = existingIds(compactState(state, ""));
    for (const id of [...patch.resolve, ...patch.remove]) expect(ids).toContain(id);
    for (const added of patch.add) {
      expect(ids).not.toContain(added.id);
      expect(listNames).toContain(added.list);
    }
    const words = [patch.currentThread ?? "", ...patch.add.map((a) => a.text)].join(" ");
    expect(words).toMatch(/queue|sync/i);
    expect(usage.inputTokens).toBeGreaterThan(usage.outputTokens);
  });

  // Two calls of 5 s each when the first sentence runs long and the route asks again.
  it.skipIf(!anthropic)(
    "Sonnet asks about the queue or the sync layer",
    async () => {
      const res = await post("/v1/phrase", phraseBody);
      expect(res.status, await res.clone().text()).toBe(200);
      const { text } = (await res.json()) as { text: string };
      console.log(`phrase: ${text}`);
      expect(text).toMatch(/queue|retr|sync|problem/i);
      expect(text).toMatch(/\?$/);
      expect(text).not.toMatch(/\bI\b/);
    },
    15_000,
  );

  // Opus on 20 lines of the decision fixture: about 4,000 tokens in and 1,400 out.
  it.skipIf(!anthropic)(
    "Opus writes notes about the apartments with spans on the transcript's lines",
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
      const counts = Object.fromEntries(
        sectionNames.map((name) => [name, (body.notes[name] as Item[]).length]),
      );
      console.log(`notes title: ${body.notes.title}`, counts, body.usage);

      expect(body.notes.title).not.toBe(opusNotes.title);
      expect(body.notes.title).toMatch(/apartment|carver|park|commute|bus|money|time/i);
      const items = sectionNames.flatMap((name) => body.notes[name] as Item[]);
      expect(items.map((i) => i.text).join(" ")).toMatch(/carver|park|bus|hour/i);
      // The prompt prints each line's times rounded to the second and asks for them back.
      const near = (a: number, b: number) => Math.abs(a - b) <= 1;
      const spans = items.flatMap((i) => (i.span ? [i.span] : []));
      expect(spans.length).toBeGreaterThan(0);
      for (const span of spans) {
        expect(
          transcript.some((s) => near(s.start, span.start)),
          `start ${span.start}`,
        ).toBe(true);
        expect(
          transcript.some((s) => near(s.end, span.end)),
          `end ${span.end}`,
        ).toBe(true);
      }
      expect(body.usage.inputTokens).toBeGreaterThan(2_000);
      expect(body.usage.outputTokens).toBeGreaterThan(200);
    },
    180_000,
  );

  it.skipIf(!env.ELEVENLABS_API_KEY)("ElevenLabs speaks one short line as MP3", async () => {
    const res = await post("/v1/speak", speakBody);
    expect(res.status, await res.clone().text()).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/mpeg");
    expect(res.headers.get("x-character-count")).toBe(String(speakBody.text.length));
    expect(res.headers.get("request-id")).toMatch(/\S/);
    const bytes = new Uint8Array(await res.arrayBuffer());
    // 64 kbit/s is 8 KB a second, and 52 characters take two to eight seconds to say.
    expect(bytes.byteLength).toBeGreaterThan(12_000);
    expect(bytes.byteLength).toBeLessThan(80_000);
    const id3 = String.fromCharCode(...bytes.slice(0, 3)) === "ID3";
    const frameSync = bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0;
    expect(id3 || frameSync, "no MP3 header").toBe(true);
  });
});
