import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { appAccountTokenFor } from "../../src/entitlement";
import worker from "../../src/index";
import { canonicalClientData, clientDataHash } from "../../src/attest/clientdata";
import { sha256, toBase64, toHex } from "../../src/bytes";
import { memoryKV, noCounter } from "../kv";
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
  DEVICE_COUNTER: noCounter,
  TYPESAFE_API_KEY: "test-jev",
  ANTHROPIC_API_KEY: "test-anthropic",
  ELEVENLABS_API_KEY: "test-elevenlabs",
  REQUIRE_ATTESTATION: "false",
};

const call = async (
  path: string,
  body: unknown,
  replies: Reply[],
  accept = "application/json",
  device?: string,
) => {
  const upstream = fakeUpstream(replies);
  vi.stubGlobal("fetch", upstream.fetch);
  const request = new Request(`https://ooooh.test${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", accept, ...(device && { "x-device": device }) },
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
  beforeAll(async () => {
    const request = new Request("https://ooooh.test/v1/session/start", { method: "POST" });
    expect((await worker.fetch(request, testEnv)).status).toBe(200);
  });

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

  // Key ids in App Attest's shape, base64 of 32 bytes. ProxyTests derives the same tokens from them.
  it("app-account-token.json matches the Worker's derivation", async () => {
    const cases = [];
    for (const name of ["first install", "second install", "third install"]) {
      const keyId = toBase64(await sha256(new TextEncoder().encode(name)));
      cases.push({ keyId, appAccountToken: await appAccountTokenFor(keyId) });
    }
    expect(new Set(cases.map((c) => c.appAccountToken)).size).toBe(cases.length);
    for (const { appAccountToken } of cases) {
      expect(appAccountToken).toMatch(
        /^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
      );
    }
    compare(resolve(fixturesDir, "app-account-token.json"), JSON.stringify(cases, null, 2) + "\n");
  });

  const startSession = (device: string) =>
    call("/v1/session/start", {}, [], "application/json", device).then(JSON.parse);

  const endSession = async (device: string) => {
    const request = new Request("https://ooooh.test/v1/session/end", {
      method: "POST",
      headers: { "content-type": "application/json", "x-device": device },
      body: JSON.stringify({ minutes: 1 }),
    });
    expect((await worker.fetch(request, testEnv)).status).toBe(204);
  };

  it("session-start-free.json is the first session of the month", async () => {
    const actual = await startSession("fixture-free");
    compare(
      resolve(fixturesDir, "session-start-free.json"),
      JSON.stringify(actual, null, 2) + "\n",
    );
  });

  it("session-start-paid.json is a device with a live entitlement", async () => {
    const expiresDate = new Date("2099-01-01T00:00:00Z").getTime();
    await testEnv.BUDGET.put(
      "entitlement:fixture-paid",
      JSON.stringify({ expiresDate, verifiedAt: Date.now() }),
    );
    const actual = await startSession("fixture-paid");
    compare(
      resolve(fixturesDir, "session-start-paid.json"),
      JSON.stringify(actual, null, 2) + "\n",
    );
  });

  it("session-start-refused.json is the fourth session of the month", async () => {
    for (let i = 0; i < 3; i++) {
      await startSession("fixture-refused");
      await endSession("fixture-refused");
    }
    const actual = await startSession("fixture-refused");
    compare(
      resolve(fixturesDir, "session-start-refused.json"),
      JSON.stringify(actual, null, 2) + "\n",
    );
  });

  it("phrase.sse matches the streamed route", async () => {
    const replies = [
      { body: sonnetStream(shortSentence), headers: { "content-type": "text/event-stream" } },
    ];
    const actual = await call("/v1/phrase", phraseBody, replies, "text/event-stream");
    compare(resolve(fixturesDir, "phrase.sse"), actual);
  });
});
