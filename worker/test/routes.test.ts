import { SELF } from "cloudflare:test";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  bodyOf,
  decideBody,
  fakeUpstream,
  jevReply,
  type FakeUpstream,
  type Reply,
} from "./upstream";

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
