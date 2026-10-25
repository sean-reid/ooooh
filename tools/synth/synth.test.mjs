import assert from "node:assert/strict";
import { existsSync, readdirSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import {
  SCHEMA_PATH,
  buildFixture,
  buildLabels,
  estimateDuration,
  listScripts,
  loadScript,
  synthesize,
  timeline,
} from "./synth.mjs";
import {
  SAMPLE_RATE,
  elevenLabsClient,
  pickSayVoice,
  wavFromPCM,
} from "./tts.mjs";
import { validate } from "./validate.mjs";
import {
  ESTIMATE_DIR,
  SCRIPTS_DIR,
  afinfoDuration,
  hasTool,
  readJSON,
  scripts,
  tempDir,
  wavDuration,
} from "./testing.mjs";

const schema = JSON.parse(readFileSync(SCHEMA_PATH, "utf8"));
const hasFfmpeg = hasTool("ffmpeg");
const hasAfinfo = hasTool("afinfo");

const minimalScript = (overrides = {}) => ({
  name: "tiny",
  summary:
    "A two line script that exists only so the tests have something small to render.",
  utterances: [
    { text: "um, so the first thing.", pauseAfter: 0.5, label: "clarify" },
    { text: "and that is it.", pauseAfter: 2, label: "finished" },
  ],
  ...overrides,
});

test("schema accepts a minimal script and rejects a bad kind", () => {
  assert.deepEqual(validate(minimalScript(), schema), []);
  const bad = minimalScript();
  bad.utterances[0].label = "nudge";
  const errors = validate(bad, schema);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /\/utterances\/0\/label: "nudge" is not one of/);
});

test("schema rejects unknown properties, negative pauses, and bad names", () => {
  assert.match(
    validate(minimalScript({ extra: 1 }), schema)[0],
    /unknown property extra/,
  );
  const negative = minimalScript();
  negative.utterances[1].pauseAfter = -1;
  assert.match(validate(negative, schema)[0], /-1 is below 0/);
  assert.match(
    validate(minimalScript({ name: "Has Spaces" }), schema)[0],
    /does not match/,
  );
  assert.match(validate({ name: "x" }, schema).join("\n"), /missing summary/);
});

test("loadScript throws with the failing path when a file breaks the schema", (t) => {
  const dir = tempDir(t);
  const file = join(dir, "broken.json");
  writeFileSync(file, JSON.stringify(minimalScript({ utterances: [] })));
  assert.throws(
    () => loadScript(file),
    /broken\.json fails the schema[\s\S]*fewer than 1 items/,
  );
});

test("estimateDuration is word count over 2.6 plus 0.3, to the millisecond", () => {
  assert.equal(estimateDuration("one two three"), 1.454);
  assert.equal(estimateDuration("  spaced   out words here  "), 1.838);
  assert.equal(estimateDuration("um."), 0.685);
});

test("timeline accumulates durations and pauses exactly", () => {
  assert.deepEqual(timeline([1.5, 2.25], [0.5, 3]), [
    { start: 0, end: 1.5 },
    { start: 2, end: 4.25 },
  ]);
  const hundred = timeline(Array(100).fill(0.1), Array(100).fill(0.1));
  assert.equal(hundred.at(-1).end, 19.9);
  assert.equal(hundred[57].start, 11.4);
  assert.throws(() => timeline([1], []), /one pause per utterance/);
});

test("labels point at the labeled segment and carry its end time", () => {
  const script = minimalScript();
  const fixture = buildFixture(script, [1.234, 0.9]);
  const labels = buildLabels(script, fixture);
  assert.deepEqual(labels, {
    fixture: "tiny",
    labels: [
      { utterance: 0, at: 1.234, kind: "clarify" },
      { utterance: 1, at: 2.634, kind: "finished" },
    ],
  });
  assert.ok(fixture.segments.every((s) => s.isFinal === true));
});

test("estimate mode is deterministic and matches the checked-in fixtures", async (t) => {
  const a = tempDir(t);
  const b = tempDir(t);
  for (const file of listScripts(SCRIPTS_DIR)) {
    await synthesize(file, { out: a, tts: "estimate" });
    await synthesize(file, { out: b, tts: "estimate" });
  }
  for (const name of readdirSync(a)) {
    const fresh = readFileSync(join(a, name), "utf8");
    assert.equal(
      fresh,
      readFileSync(join(b, name), "utf8"),
      `${name} differs between runs`,
    );
    assert.equal(
      fresh,
      readFileSync(join(ESTIMATE_DIR, name), "utf8"),
      `${name} is stale; rerun estimate mode`,
    );
  }
  for (const [name, script] of Object.entries(scripts)) {
    const fixture = readJSON(join(a, `${name}.fixture.json`));
    const labels = readJSON(join(a, `${name}.labels.json`));
    assert.equal(labels.fixture, name);
    assert.equal(fixture.segments.length, script.utterances.length);
    for (const label of labels.labels) {
      assert.equal(label.at, fixture.segments[label.utterance].end);
      assert.equal(label.kind, script.utterances[label.utterance].label);
    }
  }
});

test("synthesize rejects an unknown tts mode", async (t) => {
  const dir = tempDir(t);
  await assert.rejects(
    synthesize(join(SCRIPTS_DIR, "flowing.json"), { out: dir, tts: "shout" }),
    /--tts must be one of/,
  );
});

test("pickSayVoice prefers Premium or Enhanced and falls back to Samantha", () => {
  assert.equal(
    pickSayVoice(["Alex", "Ava (Premium)", "Samantha"]),
    "Ava (Premium)",
  );
  assert.equal(
    pickSayVoice(["Alex", "Samantha (Enhanced)"]),
    "Samantha (Enhanced)",
  );
  assert.equal(pickSayVoice(["Alex", "Fred"]), "Samantha");
});

test("wavFromPCM writes a header the duration parser agrees with", (t) => {
  const dir = tempDir(t);
  const file = join(dir, "one-second.wav");
  writeFileSync(file, wavFromPCM(Buffer.alloc(SAMPLE_RATE * 2)));
  assert.equal(wavDuration(file), 1);
});

test("elevenlabs client refuses to start without a key or a voice", () => {
  assert.throws(
    () => elevenLabsClient({ apiKey: "", voice: "v" }),
    /ELEVENLABS_API_KEY is not set/,
  );
  assert.throws(() => elevenLabsClient({ apiKey: "k" }), /needs --voice/);
});

function fakeElevenLabs(t, handler) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      requests.push({
        url: req.url,
        headers: req.headers,
        body,
        at: Date.now(),
      });
      handler(requests.length, res);
    });
  });
  return new Promise((resolveServer) => {
    server.listen(0, "127.0.0.1", () => {
      t.after(() => server.close());
      resolveServer({
        baseURL: `http://127.0.0.1:${server.address().port}`,
        requests,
      });
    });
  });
}

test("elevenlabs client backs off on 429 then returns PCM with the right duration", async (t) => {
  const { baseURL, requests } = await fakeElevenLabs(t, (n, res) => {
    if (n === 1) {
      res.writeHead(429, { "retry-after": "0.3" });
      res.end("slow down");
      return;
    }
    res.writeHead(200, { "content-type": "audio/pcm" });
    res.end(Buffer.alloc(SAMPLE_RATE * 2 * 1.5));
  });
  const client = elevenLabsClient({
    apiKey: "test-key",
    baseURL,
    voice: "voice123",
  });
  const { pcm, duration } = await client.speak("hello there");
  assert.equal(requests.length, 2);
  assert.ok(
    requests[1].at - requests[0].at >= 290,
    `retried after ${requests[1].at - requests[0].at} ms`,
  );
  assert.equal(duration, 1.5);
  assert.equal(pcm.length, SAMPLE_RATE * 3);
  assert.equal(
    requests[0].url,
    `/v1/text-to-speech/voice123?output_format=pcm_${SAMPLE_RATE}`,
  );
  assert.equal(requests[0].headers["xi-api-key"], "test-key");
  assert.deepEqual(JSON.parse(requests[0].body), {
    text: "hello there",
    model_id: "eleven_flash_v2_5",
  });
});

test("elevenlabs client gives up after maxAttempts of 429 and surfaces other errors", async (t) => {
  const { baseURL, requests } = await fakeElevenLabs(t, (n, res) => {
    res.writeHead(n < 3 ? 429 : 500, { "retry-after": "0" });
    res.end(n < 3 ? "busy" : "boom");
  });
  const client = elevenLabsClient({
    apiKey: "k",
    baseURL,
    voice: "v",
    maxAttempts: 2,
  });
  await assert.rejects(client.speak("x"), /ElevenLabs 429 for "x": busy/);
  assert.equal(requests.length, 2);
  const patient = elevenLabsClient({
    apiKey: "k",
    baseURL,
    voice: "v",
    maxAttempts: 9,
  });
  await assert.rejects(patient.speak("y"), /ElevenLabs 500 for "y": boom/);
});

test(
  "elevenlabs mode splices fake clips into audio whose length matches the fixture",
  { skip: !hasFfmpeg && "ffmpeg not installed" },
  async (t) => {
    const seconds = [1.5, 0.5, 2];
    const { baseURL } = await fakeElevenLabs(t, (n, res) => {
      res.writeHead(200, { "content-type": "audio/pcm" });
      res.end(Buffer.alloc(SAMPLE_RATE * 2 * seconds[n - 1]));
    });
    const dir = tempDir(t);
    const script = minimalScript({
      name: "fake",
      utterances: [
        { text: "first", pauseAfter: 0.5 },
        { text: "second", pauseAfter: 3, label: "leave" },
        { text: "third", pauseAfter: 1, label: "finished" },
      ],
    });
    writeFileSync(join(dir, "fake.json"), JSON.stringify(script));
    const saved = {
      key: process.env.ELEVENLABS_API_KEY,
      base: process.env.ELEVENLABS_BASE_URL,
    };
    process.env.ELEVENLABS_API_KEY = "k";
    process.env.ELEVENLABS_BASE_URL = baseURL;
    t.after(() => {
      process.env.ELEVENLABS_API_KEY = saved.key ?? "";
      process.env.ELEVENLABS_BASE_URL = saved.base ?? "";
    });
    const result = await synthesize(join(dir, "fake.json"), {
      out: dir,
      tts: "elevenlabs",
      voice: "v",
    });
    assert.deepEqual(
      result.fixture.segments.map((s) => [s.start, s.end]),
      [
        [0, 1.5],
        [2, 2.5],
        [5.5, 7.5],
      ],
    );
    assert.deepEqual(result.labels.labels, [
      { utterance: 1, at: 2.5, kind: "leave" },
      { utterance: 2, at: 7.5, kind: "finished" },
    ]);
    assert.equal(result.total, 8.5);
    assert.ok(Math.abs(wavDuration(join(dir, "fake.wav")) - 8.5) < 0.1);
    assert.ok(existsSync(join(dir, "fake.m4a")));
    if (hasAfinfo)
      assert.ok(Math.abs(afinfoDuration(join(dir, "fake.m4a")) - 8.5) < 0.1);
  },
);
