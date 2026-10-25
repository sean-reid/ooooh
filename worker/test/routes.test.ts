import { SELF } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  bodyOf,
  compactBody,
  decideBody,
  fakeUpstream,
  haikuPatch,
  haikuReply,
  jevReply,
  longSentence,
  phraseBody,
  shortSentence,
  sonnetReply,
  sonnetStream,
  type FakeUpstream,
  type Reply,
} from "./upstream";
import worker from "../src/index";
import { memoryKV } from "./kv";

const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  SELF.fetch(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

let upstream: FakeUpstream;
const expectUpstream = (...replies: Reply[]) => {
  upstream = fakeUpstream(replies);
  vi.stubGlobal("fetch", upstream.fetch);
  return upstream;
};

afterEach(() => {
  expect(upstream.pending()).toBe(0);
  vi.unstubAllGlobals();
});

describe("POST /v1/decide", () => {
  it("maps Jev answers onto JevAnswers with scores on a 1 to 5 scale", async () => {
    expectUpstream({ body: jevReply });

    const res = await post("/v1/decide", decideBody);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body).toEqual({
      answers: {
        goodMoment: { probability: 0.82 },
        intervention: { choice: "clarify", confidence: 0.71 },
        articulationDifficulty: { score: 3.35, confidence: 0.64 },
        momentum: { score: 2.8, confidence: 0.58 },
        seemsFinished: { probability: 0.04 },
        addressesApp: { choice: "none", confidence: 0.97 },
      },
      questionsVersion: 1,
      usage: { jevInputTokens: 412 },
    });

    expect(upstream.requests[0].url).toBe("https://api.typesafe.ai/v1/systemone");
    expect(upstream.requests[0].headers.authorization).toBe("Bearer test-jev");
    const sent = bodyOf(upstream.requests[0]);
    expect(sent.model).toBe("jev-latest");
    expect(Object.keys(sent.questions as object).sort()).toEqual([
      "addressesApp",
      "articulationDifficulty",
      "goodMoment",
      "intervention",
      "momentum",
      "seemsFinished",
    ]);
    const state = sent.state as { recentTranscript: string; signals: { pauseLength: number } };
    expect(state.recentTranscript.split("\n")).toHaveLength(2);
    expect(state.signals.pauseLength).toBe(2.5);
  });

  it("backs off twice on 429 then returns 503 with retryAfter", async () => {
    const limited = {
      status: 429,
      body: { error: "rate limited" },
      headers: { "retry-after": "7" },
    };
    expectUpstream(limited, limited, limited);

    const started = Date.now();
    const res = await post("/v1/decide", decideBody);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "jev unavailable", retryAfter: 7 });
    expect(Date.now() - started).toBeGreaterThanOrEqual(700);
    expect(upstream.requests).toHaveLength(3);
  });

  it("returns 422 naming the field", async () => {
    expectUpstream();
    const res = await post("/v1/decide", { ...decideBody, signals: { pauseLength: "soon" } });
    expect(res.status).toBe(422);
    expect(await res.json()).toEqual({
      error: "invalid",
      field: "signals.pauseLength",
      expected: "number",
    });
  });
});

describe("POST /v1/compact", () => {
  it("returns the validated patch and usage", async () => {
    expectUpstream({ body: haikuReply });

    const res = await post("/v1/compact", compactBody);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({
      patch: haikuPatch,
      usage: { inputTokens: 980, outputTokens: 120 },
    });
    expect(upstream.requests[0].url).toBe("https://api.anthropic.com/v1/messages");
    expect(upstream.requests[0].headers.authorization).toBe("Bearer test-anthropic");
    const sent = bodyOf<{
      model: string;
      output_config: { format: { type: string } };
      messages: { content: string }[];
    }>(upstream.requests[0]);
    expect(sent.model).toBe("claude-haiku-5-5");
    expect(sent.output_config.format.type).toBe("json_schema");
    expect(sent.messages[0].content).toContain("sync-rebuild, who-owns-sync");
  });

  it("refuses a patch that reuses an existing id", async () => {
    const colliding = { ...haikuPatch, add: [{ ...haikuPatch.add[0], id: "sync-rebuild" }] };
    expectUpstream({
      body: { ...haikuReply, content: [{ type: "text", text: JSON.stringify(colliding) }] },
    });

    const res = await post("/v1/compact", compactBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: "bad patch", field: "add.sync-rebuild" });
  });
});

describe("Anthropic credentials", () => {
  const env = { BUDGET: memoryKV(), CONFIG_VERSION: "1" } as Env;
  const request = () =>
    new Request("https://ooooh.test/v1/compact", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify(compactBody),
    });

  it("sends a stored key as a bearer with no oauth beta", async () => {
    expectUpstream({ body: haikuReply });
    const res = await worker.fetch(request(), { ...env, ANTHROPIC_API_KEY: "sk-key" });
    expect(res.status).toBe(200);
    const headers = upstream.requests[0].headers;
    expect(headers.authorization).toBe("Bearer sk-key");
    expect(headers["x-api-key"]).toBeUndefined();
    expect(headers["anthropic-beta"]).toBeUndefined();
  });

  it("sends an oauth token as a bearer with the oauth beta, and the token wins over the key", async () => {
    expectUpstream({ body: haikuReply });
    const res = await worker.fetch(request(), {
      ...env,
      ANTHROPIC_API_KEY: "sk-key",
      ANTHROPIC_AUTH_TOKEN: "oauth-token",
    });
    expect(res.status).toBe(200);
    const headers = upstream.requests[0].headers;
    expect(headers.authorization).toBe("Bearer oauth-token");
    expect(headers["x-api-key"]).toBeUndefined();
    expect(headers["anthropic-beta"]).toBe("oauth-2025-04-20");
  });

  it("keeps the oauth beta next to the fallback beta on the phrase route", async () => {
    expectUpstream({ body: sonnetReply(shortSentence) });
    const res = await worker.fetch(
      new Request("https://ooooh.test/v1/phrase", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(phraseBody),
      }),
      { ...env, ANTHROPIC_AUTH_TOKEN: "oauth-token" },
    );
    expect(res.status).toBe(200);
    const betas = upstream.requests[0].headers["anthropic-beta"].split(",").sort();
    expect(betas).toEqual(["oauth-2025-04-20", "server-side-fallback-2026-07-01"]);
  });
});

describe("POST /v1/phrase", () => {
  it("asks again when the first sentence is over 15 words", async () => {
    expectUpstream({ body: sonnetReply(longSentence) }, { body: sonnetReply(shortSentence) });

    const res = await post("/v1/phrase", phraseBody);
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ text: shortSentence });
    expect(upstream.requests).toHaveLength(2);
    type Sent = {
      model: string;
      fallbacks: string;
      messages: { role: string; content: string }[];
    };
    const bodies = upstream.requests.map((r) => bodyOf<Sent>(r));
    expect(bodies[0].model).toBe("claude-sonnet-5-5");
    expect(bodies[0].fallbacks).toBe("default");
    expect(upstream.requests[0].headers["anthropic-beta"]).toContain("server-side-fallback");
    expect(bodies[1].messages.map((m) => m.role)).toEqual(["user", "assistant", "user"]);
    expect(bodies[1].messages[2].content).toContain("3 words over");
  });

  it("truncates at a sentence boundary when the retry is still too long", async () => {
    expectUpstream(
      { body: sonnetReply(longSentence) },
      {
        body: sonnetReply(
          "Is it the queue? Or is it the sync layer that keeps pulling you back again?",
        ),
      },
    );

    const res = await post("/v1/phrase", phraseBody);
    expect(await res.json()).toEqual({ text: "Is it the queue?" });
  });

  it("streams deltas then a done event over SSE", async () => {
    expectUpstream({
      body: sonnetStream(shortSentence),
      headers: { "content-type": "text/event-stream" },
    });

    const res = await post("/v1/phrase", phraseBody, { accept: "text/event-stream" });
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("text/event-stream");
    const events = (await res.text())
      .trim()
      .split("\n\n")
      .map((chunk) => {
        const [event, data] = chunk.split("\n");
        return { event: event.slice(7), data: JSON.parse(data.slice(6)) as { text: string } };
      });
    const deltas = events.filter((e) => e.event === "delta").map((e) => e.data.text);
    expect(deltas.join("").trim()).toBe(shortSentence);
    expect(events.at(-1)).toEqual({ event: "done", data: { text: shortSentence } });
  });
});
