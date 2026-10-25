import { env, SELF } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  audioBytes,
  bodyOf,
  compactBody,
  decideBody,
  fakeUpstream,
  haikuPatch,
  haikuReply,
  jevReply,
  longSentence,
  notesBody,
  opusNotes,
  opusReply,
  phraseBody,
  shortSentence,
  sonnetReply,
  sonnetStream,
  speakBody,
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

const today = new Date().toISOString().slice(0, 10);
const spent = async () => Number((await env.BUDGET.get(`budget:anthropic:${today}`)) ?? 0);

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
        cues: {
          hangingQuestion: 0.61,
          repeatsPoint: 0.44,
          trailsOff: 0.12,
          contradictsEarlier: 0.07,
          unnamedDecision: 0.09,
        },
      },
      questionsVersion: 2,
      usage: { jevInputTokens: 412 },
    });

    expect(upstream.requests[0].url).toBe("https://api.typesafe.ai/v1/systemone");
    expect(upstream.requests[0].headers.authorization).toBe("Bearer test-jev");
    const sent = bodyOf(upstream.requests[0]);
    expect(sent.model).toBe("jev-latest");
    expect(Object.keys(sent.questions as object).sort()).toEqual([
      "addressesApp",
      "articulationDifficulty",
      "contradictsEarlier",
      "goodMoment",
      "hangingQuestion",
      "intervention",
      "momentum",
      "repeatsPoint",
      "seemsFinished",
      "trailsOff",
      "unnamedDecision",
    ]);
    const state = sent.state as { recentTranscript: string; signals: { pauseLength: number } };
    expect(state.recentTranscript.split("\n")).toHaveLength(2);
    expect(state.signals.pauseLength).toBe(2.5);
  });

  it("backs off twice on 429 then returns 503 with retryAfter", async () => {
    const limited = { status: 429, body: { error: "rate limited" } };
    expectUpstream(limited, limited, limited);

    const started = Date.now();
    const res = await post("/v1/decide", decideBody);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "jev unavailable", retryAfter: 1 });
    expect(Date.now() - started).toBeGreaterThanOrEqual(700);
    expect(upstream.requests).toHaveLength(3);
  });

  it("waits the Retry-After it is given, and gives up at once when that is too long", async () => {
    expectUpstream(
      { status: 429, body: { error: "rate limited" }, headers: { "retry-after": "1" } },
      { body: jevReply },
    );
    const started = Date.now();
    expect((await post("/v1/decide", decideBody)).status).toBe(200);
    expect(Date.now() - started).toBeGreaterThanOrEqual(1000);
    expect(upstream.requests).toHaveLength(2);

    expectUpstream({
      status: 429,
      body: { error: "rate limited" },
      headers: { "retry-after": "7" },
    });
    const res = await post("/v1/decide", decideBody);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "jev unavailable", retryAfter: 7 });
    expect(upstream.requests).toHaveLength(1);
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

    const before = await spent();
    const res = await post("/v1/compact", compactBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: "bad patch", field: "add.sync-rebuild" });
    expect(await spent()).toBe(before + 1100);
  });

  it("names a reply cut off at max_tokens and still charges it", async () => {
    expectUpstream({ body: { ...haikuReply, stop_reason: "max_tokens" } });

    const before = await spent();
    const res = await post("/v1/compact", compactBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "anthropic truncated", maxTokens: 4096 });
    expect(await spent()).toBe(before + 1100);
  });
});

describe("POST /v1/notes", () => {
  const sent = () =>
    bodyOf<{
      model: string;
      fallbacks: string;
      thinking: { type: string };
      output_config: { effort: string; format: { type: string; schema: { required: string[] } } };
      messages: { content: string }[];
    }>(upstream.requests[0]);

  it("returns the notes and usage, dropping null spans and summary", async () => {
    expectUpstream({ body: opusReply() });

    const res = await post("/v1/notes", notesBody);
    expect(res.status).toBe(200);
    const { summary, openThreads, ...rest } = opusNotes;
    void summary;
    expect(await res.json()).toEqual({
      notes: { ...rest, openThreads: [{ id: "who-owns-sync", text: openThreads[0].text }] },
      usage: { inputTokens: 3100, outputTokens: 820 },
    });
    const request = sent();
    expect(request.model).toBe("claude-opus-5-5");
    expect(request.thinking).toEqual({ type: "adaptive" });
    expect(request.fallbacks).toBe("default");
    expect(upstream.requests[0].headers["anthropic-beta"]).toContain("server-side-fallback");
    expect(request.output_config.effort).toBe("high");
    expect(request.output_config.format.type).toBe("json_schema");
    expect(request.output_config.format.schema.required).toContain("openThreads");
    expect(request.messages[0].content).toContain("1. [120s to 126s] So the queue keeps retrying");
  });

  it("clamps a span that runs past the transcript and nulls one outside it", async () => {
    const stray = {
      ...opusNotes,
      quotes: [
        { ...opusNotes.quotes[0], span: { start: 125, end: 140 } },
        { id: "after-the-end", text: "Said after the recording.", span: { start: 200, end: 210 } },
        { id: "reversed", text: "Ends before it starts.", span: { start: 130, end: 121 } },
      ],
    };
    expectUpstream({ body: opusReply(stray) });

    const res = await post("/v1/notes", notesBody);
    expect(res.status).toBe(200);
    const { notes } = (await res.json()) as { notes: typeof opusNotes };
    expect(notes.quotes).toEqual([
      { ...opusNotes.quotes[0], span: { start: 125, end: 133 } },
      { id: "after-the-end", text: "Said after the recording." },
      { id: "reversed", text: "Ends before it starts." },
    ]);
  });

  it("refuses notes that reuse an id across sections", async () => {
    const colliding = {
      ...opusNotes,
      decisions: [{ id: "queue-or-sync", text: "Patch the queue first.", span: null }],
    };
    expectUpstream({ body: opusReply(colliding) });

    const res = await post("/v1/notes", notesBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({
      error: "bad notes",
      field: "questions.queue-or-sync",
      expected: "unique id",
    });
  });

  it("charges input plus output tokens to the anthropic budget", async () => {
    expectUpstream({ body: opusReply() });
    const env = {
      BUDGET: memoryKV(),
      ANTHROPIC_API_KEY: "sk-key",
      REQUIRE_ATTESTATION: "false",
    } as Env;
    const res = await worker.fetch(
      new Request("https://ooooh.test/v1/notes", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(notesBody),
      }),
      env,
    );
    expect(res.status).toBe(200);
    const day = new Date().toISOString().slice(0, 10);
    expect(await env.BUDGET.get(`budget:anthropic:${day}`)).toBe("3920");
  });

  it("refuses an id that is not a slug", async () => {
    const shouty = {
      ...opusNotes,
      ideas: [{ id: "Rebuild Removes Queue", text: "A rebuild.", span: null }],
    };
    expectUpstream({ body: opusReply(shouty) });

    const res = await post("/v1/notes", notesBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ field: "ideas.Rebuild Removes Queue" });
  });
});

describe("Anthropic credentials", () => {
  const env = { BUDGET: memoryKV(), REQUIRE_ATTESTATION: "false" } as Env;
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

  it("sends the same 503 body as an error event when the stream never starts", async () => {
    const limited: Reply = {
      status: 429,
      body: { error: { type: "rate_limit_error" } },
      headers: { "retry-after-ms": "1" },
    };
    expectUpstream(limited, limited, limited);

    const res = await post("/v1/phrase", phraseBody, { accept: "text/event-stream" });
    expect(res.status).toBe(200);
    const [event, data] = (await res.text()).trim().split("\n");
    expect(event).toBe("event: error");
    expect(JSON.parse(data.slice(6))).toEqual({ error: "anthropic unavailable", retryAfter: 5 });
  });
});

describe("labels", () => {
  it("falls back to the address when x-device is too long for a KV key", async () => {
    const res = await SELF.fetch("https://ooooh.test/v1/challenge", {
      headers: { "x-device": "d".repeat(600) },
    });
    expect(res.status).toBe(200);
  });

  it("refuses a challenge of the wrong length before looking it up", async () => {
    const res = await post("/v1/attest", {
      keyId: "k",
      attestation: "AAAA",
      challenge: "A".repeat(600),
    });
    expect(res.status).toBe(401);
    expect(await res.json()).toEqual({ error: "unauthorized", reason: "bad-challenge" });
  });
});

describe("POST /v1/speak", () => {
  const voice = "SAz9YHcvj6GT2YYXdXww";
  const audio = (headers: Record<string, string> = {}): Reply => ({
    body: audioBytes,
    headers: { "content-type": "audio/mpeg", ...headers },
  });

  it("streams the audio through, charges the character count, and never caches", async () => {
    expectUpstream(audio({ "x-character-count": "52", "request-id": "req_01" }));
    const key = `budget:elevenlabs:${new Date().toISOString().slice(0, 10)}`;
    const before = Number((await env.BUDGET.get(key)) ?? 0);

    const res = await post("/v1/speak", speakBody);
    expect(Number(await env.BUDGET.get(key)) - before).toBe(52);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("audio/mpeg");
    expect(res.headers.get("cache-control")).toBe("no-store");
    expect(res.headers.get("x-character-count")).toBe("52");
    expect(res.headers.get("request-id")).toBe("req_01");
    expect(new Uint8Array(await res.arrayBuffer())).toEqual(audioBytes);

    const sent = upstream.requests[0];
    expect(sent.url).toBe(
      `https://api.elevenlabs.io/v1/text-to-speech/${voice}/stream?output_format=mp3_44100_64`,
    );
    expect(sent.headers["xi-api-key"]).toBe("test-elevenlabs");
    expect(bodyOf(sent)).toEqual({
      text: speakBody.text,
      model_id: "eleven_v4_turbo",
      voice_settings: { stability: 0.6, similarity_boost: 0.75 },
    });
  });

  it("counts the characters itself when the upstream header is missing", async () => {
    expectUpstream(audio());
    const res = await post("/v1/speak", speakBody);
    expect(res.status).toBe(200);
    expect(res.headers.get("x-character-count")).toBe(String(speakBody.text.length));
  });

  it("caps the text at 400 characters and names the field", async () => {
    expectUpstream();
    const expected = { error: "invalid", field: "text", expected: "1 to 400 characters" };
    const long = await post("/v1/speak", { text: "a".repeat(401) });
    expect(long.status).toBe(422);
    expect(await long.json()).toEqual(expected);
    const blank = await post("/v1/speak", { text: "   " });
    expect(blank.status).toBe(422);
    expect(await blank.json()).toEqual(expected);
    const missing = await post("/v1/speak", {});
    expect(missing.status).toBe(422);
    expect(await missing.json()).toEqual({ error: "invalid", field: "text", expected: "string" });
  });

  it("accepts exactly 400 characters", async () => {
    expectUpstream(audio());
    const res = await post("/v1/speak", { text: "a".repeat(400) });
    expect(res.status).toBe(200);
    expect(res.headers.get("x-character-count")).toBe("400");
  });

  it("backs off once on 429 then succeeds", async () => {
    expectUpstream({ status: 429, body: { detail: "busy" } }, audio());

    const started = Date.now();
    const res = await post("/v1/speak", speakBody);
    expect(res.status).toBe(200);
    expect(Date.now() - started).toBeGreaterThanOrEqual(250);
    expect(upstream.requests).toHaveLength(2);
  });

  it("backs off once on 429 then returns 503 with retryAfter", async () => {
    const limited: Reply = { status: 429, body: { detail: "busy" } };
    expectUpstream(limited, limited);

    const res = await post("/v1/speak", speakBody);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "elevenlabs unavailable", retryAfter: 5 });
    expect(upstream.requests).toHaveLength(2);
  });

  it("gives up at once when Retry-After is longer than it will wait", async () => {
    expectUpstream({ status: 429, body: { detail: "busy" }, headers: { "retry-after": "7" } });

    const res = await post("/v1/speak", speakBody);
    expect(res.status).toBe(503);
    expect(await res.json()).toEqual({ error: "elevenlabs unavailable", retryAfter: 7 });
    expect(upstream.requests).toHaveLength(1);
  });

  it("returns 502 with the upstream status on other failures", async () => {
    expectUpstream({ status: 401, body: { detail: { status: "invalid_api_key" } } });
    const res = await post("/v1/speak", speakBody);
    expect(res.status).toBe(502);
    expect(await res.json()).toMatchObject({ error: "elevenlabs", status: 401 });
  });
});
