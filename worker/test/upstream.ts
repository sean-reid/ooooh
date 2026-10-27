// Request bodies the phone sends and upstream replies shaped like recorded ones.
import { vi } from "vitest";

export const state = {
  currentThread: "Whether to rebuild the sync layer or patch the queue.",
  mainIdeas: [
    { id: "sync-rebuild", text: "A rebuild would remove the retry queue.", resolved: false },
  ],
  openQuestions: [
    { id: "who-owns-sync", text: "Who owns the sync layer after the move?", resolved: false },
  ],
  uncertainties: [],
  decisions: [],
  recentTopics: ["sync", "queue"],
  mode: "exploring",
};

export const segments = [
  {
    text: "So the queue keeps retrying and I think that's the actual problem.",
    start: 120,
    end: 126,
  },
  {
    text: "Or maybe it's the sync layer, I keep going back and forth on that.",
    start: 127,
    end: 133,
  },
];

export const decideBody = {
  state,
  recentTranscript: segments,
  signals: {
    pauseLength: 2.5,
    speechDensity: 0.6,
    awaitingFinishedReply: false,
    secondsSinceStart: 135.5,
    wordsSoFar: 27,
    promptsSoFar: 1,
    secondsSincePrompt: 75.5,
  },
  lastIntervention: { kind: "clarify", text: "Which part feels least clear?", at: 60 },
};

export const compactBody = { state, transcript: segments };

export const phraseBody = { kind: "clarify", state, recent: segments };

export const notesBody = { state, transcript: segments };
export const speakBody = { text: "Which part feels least clear, the queue or the sync?" };

// Stands in for an MP3 body. The Worker passes bytes through without looking at them.
export const audioBytes = Uint8Array.from({ length: 2048 }, (_, i) => (i * 37 + 11) % 256);

export const jevReply = {
  answers: {
    goodMoment: { type: "noul", noul: 0.82 },
    intervention: {
      type: "choice",
      choice: "clarify",
      confidence: 0.71,
      probabilities: {
        clarify: 0.71,
        deepen: 0.12,
        reflect: 0.08,
        decide: 0.05,
        summarize: 0.02,
        challenge: 0.02,
      },
    },
    articulationDifficulty: {
      type: "score",
      score: 2.35,
      confidence: 0.64,
      probabilities: [0.1, 0.5, 0.35, 0.05, 0],
      legend: ["fluent", "mostly fluent", "mixed", "laboured", "struggling"],
    },
    momentum: {
      type: "score",
      score: 1.8,
      confidence: 0.58,
      probabilities: [0.2, 0.5, 0.25, 0.05, 0],
      legend: ["stalled", "slowing", "steady", "gaining", "building"],
    },
    seemsFinished: { type: "noul", noul: 0.04 },
    addressesApp: {
      type: "choice",
      choice: "none",
      confidence: 0.97,
      probabilities: { none: 0.97, recall: 0.02, wrapUp: 0.01 },
    },
    hangingQuestion: { type: "noul", noul: 0.61 },
    repeatsPoint: { type: "noul", noul: 0.44 },
    trailsOff: { type: "noul", noul: 0.12 },
    contradictsEarlier: { type: "noul", noul: 0.07 },
    unnamedDecision: { type: "noul", noul: 0.09 },
  },
  usage: { input_tokens: 412 },
};

export const haikuPatch = {
  currentThread: "Deciding between rebuilding the sync layer and patching the retry queue.",
  mode: "converging",
  recentTopics: ["sync", "queue", "retries"],
  add: [
    {
      list: "uncertainties",
      id: "queue-or-sync",
      text: "Unsure whether the queue or the sync layer is the real problem.",
    },
  ],
  resolve: [],
  remove: [],
};

const message = (
  text: string,
  usage = { input_tokens: 980, output_tokens: 120 },
  model = "claude-haiku-5-5",
) => ({
  id: "msg_01",
  type: "message",
  role: "assistant",
  model,
  content: [{ type: "text", text }],
  stop_reason: "end_turn",
  stop_sequence: null,
  stop_details: null,
  usage: { ...usage, cache_creation_input_tokens: 0, cache_read_input_tokens: 0 },
});

export const haikuReply = message(JSON.stringify(haikuPatch));

export const opusNotes = {
  title: "Queue or sync layer",
  summary: null,
  ideas: [
    {
      id: "rebuild-removes-queue",
      text: "A rebuild would remove the retry queue.",
      span: { start: 120, end: 126 },
    },
  ],
  decisions: [],
  questions: [
    {
      id: "queue-or-sync",
      text: "Is the queue or the sync layer the actual problem?",
      span: { start: 120, end: 133 },
    },
  ],
  insights: [],
  actions: [],
  openThreads: [
    {
      id: "who-owns-sync",
      text: "Who owns the sync layer after the move.",
      span: null,
    },
  ],
  quotes: [
    {
      id: "back-and-forth",
      text: "I keep going back and forth on that.",
      span: { start: 127, end: 133 },
    },
  ],
};

export const opusReply = (notes: unknown = opusNotes) =>
  message(JSON.stringify(notes), { input_tokens: 3100, output_tokens: 820 }, "claude-opus-5-5");

export const longSentence =
  "Which part of the queue versus the sync layer question feels least clear to you right now today?";
export const shortSentence = "Which part feels least clear, the queue or the sync?";

export const sonnetReply = (text: string) =>
  message(text, { input_tokens: 640, output_tokens: 18 }, "claude-sonnet-5-5");

export const sonnetStream = (text: string) => {
  const events: Array<[string, unknown]> = [
    ["message_start", { type: "message_start", message: { ...sonnetReply(""), content: [] } }],
    [
      "content_block_start",
      { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
    ],
  ];
  for (const word of text.split(" ")) {
    events.push([
      "content_block_delta",
      { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: word + " " } },
    ]);
  }
  events.push(["content_block_stop", { type: "content_block_stop", index: 0 }]);
  events.push([
    "message_delta",
    {
      type: "message_delta",
      delta: { stop_reason: "end_turn", stop_sequence: null },
      usage: { output_tokens: 18 },
    },
  ]);
  events.push(["message_stop", { type: "message_stop" }]);
  return events
    .map(([event, data]) => `event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)
    .join("");
};

export type Reply =
  | {
      status?: number;
      body: unknown;
      headers?: Record<string, string>;
    }
  | { hangs: true };

export type Seen = { url: string; headers: Record<string, string>; body: string };

export type FakeUpstream = {
  fetch: typeof fetch;
  requests: Seen[];
  pending: () => number;
};

// Replies in order, one per outbound request, whatever the origin. A reply that hangs rejects when the request signal aborts.
export function fakeUpstream(replies: Reply[]): FakeUpstream {
  const queue = [...replies];
  const requests: Seen[] = [];
  const impl: typeof fetch = async (input, init) => {
    const request = new Request(input, init);
    requests.push({
      url: request.url,
      headers: Object.fromEntries(request.headers),
      body: await request.text(),
    });
    const reply = queue.shift();
    if (!reply) throw new Error(`unexpected upstream request to ${request.url}`);
    if ("hangs" in reply) {
      return new Promise<Response>((_, reject) => {
        request.signal.addEventListener("abort", () => reject(request.signal.reason));
      });
    }
    const body =
      typeof reply.body === "string" || reply.body instanceof ReadableStream
        ? reply.body
        : reply.body instanceof Uint8Array
          ? new Uint8Array(reply.body)
          : JSON.stringify(reply.body);
    return new Response(body, {
      status: reply.status ?? 200,
      headers: { "content-type": "application/json", ...reply.headers },
    });
  };
  return { fetch: impl, requests, pending: () => queue.length };
}

/** Puts a fake upstream in place of `fetch` for the test; `vi.unstubAllGlobals()` takes it out. */
export const stubUpstream = (...replies: Reply[]) => {
  const upstream = fakeUpstream(replies);
  vi.stubGlobal("fetch", upstream.fetch);
  return upstream;
};

export const bodyOf = <T = Record<string, unknown>>(seen: Seen) => JSON.parse(seen.body) as T;
