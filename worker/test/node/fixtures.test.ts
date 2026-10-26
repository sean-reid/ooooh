import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeAll, describe, expect, it, vi } from "vitest";
import { jsonRequest, openSession, origin, startRequest } from "../request";
import { appAccountTokenFor } from "../../src/entitlement";
import worker from "../../src/index";
import { canonicalClientData, clientDataHash } from "../../src/attest/clientdata";
import { sha256, toBase64, toHex } from "../../src/bytes";
import { memoryKV } from "../kv";
import { memoryObjects } from "../objects";
import { makeStoreChain, signTransaction, transactionPayload, type StoreChain } from "../storekit";
import {
  audioBytes,
  bodyOf,
  compactBody,
  decideBody,
  haikuReply,
  jevReply,
  notesBody,
  opusReply,
  phraseBody,
  shortSentence,
  sonnetReply,
  sonnetStream,
  stubUpstream,
  type Reply,
} from "../upstream";

// Regenerate with: cd worker && WRITE_FIXTURES=1 npx vitest run --project node
const fixturesDir = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "../../../Packages/Tests/ProxyTests/Fixtures",
);

// The phone's bodies, written by WRITE_REQUEST_FIXTURES=1 swift test --package-path Packages.
const requestFixture = (route: string) =>
  readFileSync(resolve(fixturesDir, "requests", `${route}.json`), "utf8");

export const testEnv = {
  BUDGET: memoryKV(),
  ...memoryObjects(),
  TYPESAFE_API_KEY: "test-jev",
  ANTHROPIC_API_KEY: "test-anthropic",
  ELEVENLABS_API_KEY: "test-elevenlabs",
  REQUIRE_ATTESTATION: "false",
} as Env;

const call = async (
  path: string,
  body: unknown,
  replies: Reply[],
  accept = "application/json",
  device?: string,
) => {
  const upstream = stubUpstream(...replies);
  const request = jsonRequest(path, body, { accept, ...(device && { "x-device": device }) });
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

const pretty = (value: unknown) => JSON.stringify(value, null, 2) + "\n";

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
    expect((await worker.fetch(startRequest(), testEnv)).status).toBe(200);
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
    const request = jsonRequest("/v1/session/end", { minutes: 1 }, { "x-device": device });
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

  it("config.json is what /v1/config serves", async () => {
    const response = await worker.fetch(new Request(`${origin}/v1/config`), testEnv);
    expect(response.status).toBe(200);
    compare(resolve(fixturesDir, "config.json"), pretty(await response.json()));
  });

  const refused = async (device: string) => {
    const request = jsonRequest("/v1/decide", decideBody, { "x-device": device });
    const response = await worker.fetch(request, testEnv);
    expect(response.status).toBe(402);
    return pretty(await response.json());
  };

  it("no-session-not-started.json is a prompt from a device with no session", async () => {
    compare(resolve(fixturesDir, "no-session-not-started.json"), await refused("fixture-idle"));
  });

  it("no-session-free-used.json is a prompt after the month's free sessions", async () => {
    for (let i = 0; i < 3; i++) {
      await startSession("fixture-spent");
      await endSession("fixture-spent");
    }
    compare(resolve(fixturesDir, "no-session-free-used.json"), await refused("fixture-spent"));
  });

  it("no-session-minutes-used.json is a prompt past a free session's minutes", async () => {
    const started = new Date(Date.now() - 21 * 60_000);
    expect((await openSession(testEnv, "fixture-late", started)).status).toBe(200);
    compare(resolve(fixturesDir, "no-session-minutes-used.json"), await refused("fixture-late"));
  });
});

// Each body the phone posts goes through the route's own readBody, so a field one side renamed is a 422 here.
describe("ProxyTests request fixtures", () => {
  beforeAll(async () => {
    expect((await worker.fetch(startRequest(), testEnv)).status).toBe(200);
  });

  const accepted = [
    { route: "compact", path: "/v1/compact", replies: [{ body: haikuReply }] },
    { route: "phrase", path: "/v1/phrase", replies: [{ body: sonnetReply(shortSentence) }] },
    { route: "notes", path: "/v1/notes", replies: [{ body: opusReply() }] },
    {
      route: "speak",
      path: "/v1/speak",
      replies: [{ body: audioBytes, headers: { "content-type": "audio/mpeg" } }],
    },
    { route: "session-start", path: "/v1/session/start", replies: [] },
  ];

  for (const { route, path, replies } of accepted) {
    it(`requests/${route}.json passes ${path}`, async () => {
      await call(path, requestFixture(route), replies);
    });
  }

  // The state validator defaults every field, so a renamed one would pass as empty; Jev's copy shows what survived.
  it("requests/decide.json passes /v1/decide with the whole state", async () => {
    const upstream = stubUpstream({ body: jevReply });
    const request = jsonRequest("/v1/decide", requestFixture("decide"));
    expect((await worker.fetch(request, testEnv)).status).toBe(200);
    const posted = JSON.parse(requestFixture("decide"));
    const { lastIntervention, ...state } = posted.state;
    const jev = bodyOf<{ state: Record<string, unknown> }>(upstream.requests[0]).state;
    expect(jev).toEqual({
      state,
      lastIntervention,
      signals: posted.signals,
      recentTranscript: expect.stringContaining(posted.recentTranscript[1].text),
      earlierLinesInWindow: 0,
    });
  });
});

const postEntitlement = (device: string, transaction: string, chain: StoreChain) =>
  worker.fetch(jsonRequest("/v1/entitlement", { transaction }, { "x-device": device }), {
    ...testEnv,
    APPLE_ROOT_PEM: chain.rootPem,
  });

// Fixed dates, so the signed transactions and the answers come out the same on every run.
describe("entitlement fixtures", () => {
  let chain: StoreChain;
  let paid: string;

  beforeAll(async () => {
    chain = await makeStoreChain({
      leafNotBefore: new Date("2026-01-01T00:00:00Z"),
      leafNotAfter: new Date("2036-01-01T00:00:00Z"),
    });
    paid = await signTransaction(
      chain,
      transactionPayload(new Date("2026-10-25T10:00:00Z").getTime(), {
        appAccountToken: await appAccountTokenFor("fixture-entitled"),
        expiresDate: new Date("2099-01-01T00:00:00Z").getTime(),
      }),
    );
  });

  it("entitlement-paid.json is a subscription that runs into the future", async () => {
    const res = await postEntitlement("fixture-entitled", paid, chain);
    expect(res.status).toBe(200);
    compare(
      resolve(fixturesDir, "entitlement-paid.json"),
      JSON.stringify(await res.json(), null, 2) + "\n",
    );
  });

  it("entitlement-free.json is a subscription that ran out", async () => {
    const lapsed = await signTransaction(
      chain,
      transactionPayload(new Date("2026-05-01T00:00:00Z").getTime(), {
        originalTransactionId: "2000000123456001",
        appAccountToken: await appAccountTokenFor("fixture-lapsed"),
        expiresDate: new Date("2026-06-01T00:00:00Z").getTime(),
      }),
    );
    const res = await postEntitlement("fixture-lapsed", lapsed, chain);
    expect(res.status).toBe(200);
    compare(
      resolve(fixturesDir, "entitlement-free.json"),
      JSON.stringify(await res.json(), null, 2) + "\n",
    );
  });

  it("entitlement-refused.json is a second device posting a claimed transaction", async () => {
    const res = await postEntitlement("fixture-second-phone", paid, chain);
    expect(res.status).toBe(401);
    compare(
      resolve(fixturesDir, "entitlement-refused.json"),
      JSON.stringify(await res.json(), null, 2) + "\n",
    );
  });
});
