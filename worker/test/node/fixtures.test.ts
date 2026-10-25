import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../../src/index";
import { memoryKV } from "../kv";
import {
  compactBody,
  decideBody,
  fakeUpstream,
  haikuReply,
  jevReply,
  notesBody,
  opusReply,
  phraseBody,
  shortSentence,
  sonnetReply,
  sonnetStream,
  type Reply,
} from "../upstream";

// Regenerate with: cd worker && WRITE_FIXTURES=1 npx vitest run --project node
const fixturesDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../Packages/Tests/ProxyTests/Fixtures",
);

export const testEnv: Env = {
  BUDGET: memoryKV(),
  CONFIG_VERSION: "1",
  TYPESAFE_API_KEY: "test-jev",
  ANTHROPIC_API_KEY: "test-anthropic",
};

const call = async (path: string, body: unknown, replies: Reply[], accept = "application/json") => {
  const upstream = fakeUpstream(replies);
  vi.stubGlobal("fetch", upstream.fetch);
  const request = new Request(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", accept },
    body: JSON.stringify(body),
  });
  const response = await worker.fetch(request, testEnv);
  expect(response.status).toBe(200);
  const text = await response.text();
  expect(upstream.pending()).toBe(0);
  return text;
};

const compare = (file: string, actual: string) => {
  if (process.env.WRITE_FIXTURES) {
    mkdirSync(fixturesDir, { recursive: true });
    writeFileSync(file, actual);
  }
  expect(actual).toBe(readFileSync(file, "utf8"));
};

const cases = [
  { name: "decide", path: "/v1/decide", body: decideBody, replies: [{ body: jevReply }] },
  { name: "compact", path: "/v1/compact", body: compactBody, replies: [{ body: haikuReply }] },
  {
    name: "phrase",
    path: "/v1/phrase",
    body: phraseBody,
    replies: [{ body: sonnetReply(shortSentence) }],
  },
  { name: "notes", path: "/v1/notes", body: notesBody, replies: [{ body: opusReply() }] },
];

afterEach(() => vi.unstubAllGlobals());

describe("ProxyTests fixtures", () => {
  for (const { name, path, body, replies } of cases) {
    it(`${name}.json matches what the route emits`, async () => {
      const actual = JSON.parse(await call(path, body, replies));
      compare(resolve(fixturesDir, `${name}.json`), JSON.stringify(actual, null, 2) + "\n");
    });
  }

  it("phrase.sse matches the streamed route", async () => {
    const replies = [
      { body: sonnetStream(shortSentence), headers: { "content-type": "text/event-stream" } },
    ];
    const actual = await call("/v1/phrase", phraseBody, replies, "text/event-stream");
    compare(resolve(fixturesDir, "phrase.sse"), actual);
  });
});
