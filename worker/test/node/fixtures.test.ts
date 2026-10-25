import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, expect, it, vi } from "vitest";
import worker from "../../src/index";
import { canonicalClientData, clientDataHash } from "../../src/attest/clientdata";
import { sha256, toHex } from "../../src/bytes";
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
import { vars } from "./env";

// Regenerate with: cd worker && WRITE_FIXTURES=1 npx vitest run --project node
const fixturesDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../Packages/Tests/ProxyTests/Fixtures",
);

export const testEnv: Env = {
  ...vars,
  BUDGET: memoryKV(),
  TYPESAFE_API_KEY: "test-jev",
  ANTHROPIC_API_KEY: "test-anthropic",
  ELEVENLABS_API_KEY: "test-elevenlabs",
  REQUIRE_ATTESTATION: "false",
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

/** One request the Swift side signs the same way; both suites check against the written file. */
const signedRequest = {
  method: "POST",
  path: "/v1/notes",
  time: 1761430000,
  body: JSON.stringify({ state: {}, transcript: [] }),
};

afterEach(() => vi.unstubAllGlobals());

describe("ProxyTests fixtures", () => {
  for (const { name, path, body, replies } of cases) {
    it(`${name}.json matches what the route emits`, async () => {
      const actual = JSON.parse(await call(path, body, replies));
      compare(resolve(fixturesDir, `${name}.json`), JSON.stringify(actual, null, 2) + "\n");
    });
  }

  it("clientdata.json matches the string an assertion covers", async () => {
    const { method, path, time } = signedRequest;
    const body = new TextEncoder().encode(signedRequest.body);
    const canonical = canonicalClientData(method, path, time, await sha256(body));
    const hash = toHex(await clientDataHash(method, path, time, body));
    const actual = JSON.stringify({ ...signedRequest, canonical, hash }, null, 2) + "\n";
    compare(resolve(fixturesDir, "clientdata.json"), actual);
  });

  it("phrase.sse matches the streamed route", async () => {
    const replies = [
      { body: sonnetStream(shortSentence), headers: { "content-type": "text/event-stream" } },
    ];
    const actual = await call("/v1/phrase", phraseBody, replies, "text/event-stream");
    compare(resolve(fixturesDir, "phrase.sse"), actual);
  });
});
