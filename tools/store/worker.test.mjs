import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { after, before, test } from "node:test";
import { fileURLToPath } from "node:url";

const here = new URL("./", import.meta.url);
const fixtures = new URL("../../Packages/Tests/ProxyTests/Fixtures/", here);
const readJSON = (url) => JSON.parse(readFileSync(url, "utf8"));
const seed = readJSON(new URL("seed.json", here));

let worker;
let origin;

before(async () => {
  worker = spawn(
    process.execPath,
    [fileURLToPath(new URL("worker.mjs", here)), "0"],
    {
      stdio: ["ignore", "pipe", "inherit"],
    },
  );
  origin = await new Promise((resolve, reject) => {
    let out = "";
    worker.stdout.on("data", (chunk) => {
      out += chunk;
      const match = out.match(/store worker on (http:\/\/127\.0\.0\.1:\d+)/);
      if (match) resolve(match[1]);
    });
    worker.on("exit", (code) =>
      reject(new Error(`worker exited with ${code}`)),
    );
  });
});

after(() => worker.kill());

const get = (path, headers = {}) => fetch(origin + path, { headers });
const post = (path, body, headers = {}) =>
  fetch(origin + path, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: JSON.stringify(body),
  });

test("/v1/notes serves the notes recorded in seed.json", async () => {
  const response = await post("/v1/notes", {});
  assert.equal(response.status, 200);
  assert.equal(
    await response.text(),
    JSON.stringify({
      notes: seed.notes,
      usage: { inputTokens: 0, outputTokens: 0 },
    }),
  );
});

test("/v1/session/start and /v1/compact serve the Proxy fixtures", async () => {
  for (const [path, name] of [
    ["/v1/session/start", "session-start-free.json"],
    ["/v1/compact", "compact.json"],
  ]) {
    const response = await post(path, {});
    assert.equal(response.status, 200, path);
    assert.equal(
      await response.text(),
      JSON.stringify(readJSON(new URL(name, fixtures))),
      path,
    );
  }
});

test("/v1/phrase answers the recorded question, plain and streamed", async () => {
  const plain = await post("/v1/phrase", {});
  assert.deepEqual(await plain.json(), { text: seed.question });

  const streamed = await post(
    "/v1/phrase",
    {},
    { accept: "text/event-stream" },
  );
  assert.equal(streamed.headers.get("content-type"), "text/event-stream");
  const frames = (await streamed.text()).split("\n\n").filter(Boolean);
  const events = frames.map((frame) => {
    const [event, data] = frame.split("\n");
    return {
      event: event.slice("event: ".length),
      data: JSON.parse(data.slice("data: ".length)),
    };
  });
  assert.deepEqual(events.at(-1), {
    event: "done",
    data: { text: seed.question },
  });
  const deltas = events.slice(0, -1);
  assert.ok(deltas.every((entry) => entry.event === "delta"));
  assert.equal(
    deltas
      .map((entry) => entry.data.text)
      .join("")
      .trim(),
    seed.question,
  );
});

test("/v1/decide scores the recorded moment above the speak bar and nothing else", async () => {
  const decide = (text) =>
    post("/v1/decide", { recentTranscript: [{ text }] }).then((response) =>
      response.json(),
    );
  const forced = await decide(seed.moment);
  assert.equal(forced.answers.goodMoment.probability, 0.96);
  assert.equal(forced.answers.intervention.choice, seed.kind);
  const other = await decide("something else entirely");
  assert.equal(other.answers.goodMoment.probability, 0.08);
});

test("an unknown route is refused as upstream", async () => {
  const response = await get("/v1/nothing");
  assert.equal(response.status, 502);
  assert.deepEqual(await response.json(), {
    error: "upstream",
    status: 0,
    detail: "not served here",
  });
});
