import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { join } from "node:path";
import { test } from "node:test";
import { elevenLabsClient } from "./tts.mjs";
import {
  MAX_CHARACTERS,
  MODEL,
  SAMPLE_RATE,
  assemble,
  clipCache,
  clipKey,
  main,
  padToMillisecond,
  plan,
  renderClips,
  silence,
  workerVoiceId,
} from "./voice.mjs";
import { tempDir, wavDuration } from "./testing.mjs";

const BYTES_PER_SECOND = SAMPLE_RATE * 2;
const script = {
  name: "tiny",
  summary:
    "Two lines and a long pause, enough to check the timeline and the WAV length.",
  utterances: [
    { text: "first line, um, here.", pauseAfter: 0.5, label: "clarify" },
    { text: "second.", pauseAfter: 3, label: "finished" },
  ],
};

function fakeClient(seconds = 1) {
  const calls = [];
  return {
    calls,
    async speak(text) {
      calls.push(text);
      return {
        pcm: Buffer.alloc(BYTES_PER_SECOND * seconds),
        duration: seconds,
      };
    },
  };
}

test("the voice id comes from the Worker's wrangler vars", (t) => {
  assert.equal(workerVoiceId(), "SAz9YHcvj6GT2YYXdXww");
  const dir = tempDir(t);
  writeFileSync(join(dir, "w.jsonc"), '{ "vars": { "OTHER": "x" } }');
  assert.throws(
    () => workerVoiceId(join(dir, "w.jsonc")),
    /no ELEVENLABS_VOICE_ID/,
  );
});

test("clips pad to a whole millisecond and silence is exact at 16 kHz", () => {
  assert.equal(padToMillisecond(Buffer.alloc(33)).length, 64);
  assert.equal(padToMillisecond(Buffer.alloc(64)).length, 64);
  assert.equal(silence(0.5).length, BYTES_PER_SECOND / 2);
  assert.equal(silence(2.0004).length, 2 * BYTES_PER_SECOND);
});

test("assemble lays clips and pauses on one timeline the sidecar describes", () => {
  const clips = [
    Buffer.alloc(BYTES_PER_SECOND * 1.5),
    Buffer.alloc(BYTES_PER_SECOND * 0.5 + 2),
  ];
  const { pcm, sidecar } = assemble(script, clips, { voice: "v" });
  assert.equal(pcm.length, 5501 * 32);
  assert.equal(sidecar.seconds, 5.501);
  assert.equal(sidecar.characters, 28);
  assert.deepEqual(
    sidecar.utterances.map((u) => [u.start, u.end, u.label]),
    [
      [0, 1.5, "clarify"],
      [2, 2.501, "finished"],
    ],
  );
  assert.equal(sidecar.model, MODEL);
  assert.throws(() => assemble(script, [clips[0]]), /1 clips for 2 utterances/);
});

test("the cache keys by model, voice, and text, and renderClips skips what it holds", async (t) => {
  const cache = clipCache(join(tempDir(t), "cache"));
  assert.notEqual(clipKey("a", { voice: "v" }), clipKey("a", { voice: "w" }));
  assert.notEqual(clipKey("a", { voice: "v" }), clipKey("a ", { voice: "v" }));
  const client = fakeClient();
  const first = await renderClips(script, { client, cache, voice: "v" });
  assert.equal(first.length, 2);
  assert.deepEqual(client.calls, ["first line, um, here.", "second."]);
  const second = await renderClips(script, { client, cache, voice: "v" });
  assert.equal(client.calls.length, 2);
  assert.deepEqual(second, first);
  const planned = plan([script], cache, "v");
  assert.equal(planned.characters, 28);
  assert.equal(planned.uncached, 0);
  assert.equal(plan([script], cache, "other").uncached, 28);
});

test("main counts characters first and refuses over the budget without rendering", async (t) => {
  const dir = tempDir(t);
  writeFileSync(join(dir, "tiny.json"), JSON.stringify(script));
  const client = fakeClient();
  const code = await main(
    [
      "--scripts",
      dir,
      "--out",
      join(dir, "out"),
      "--cache",
      join(dir, "cache"),
      "--max-characters",
      "27",
    ],
    { client, log: () => {} },
  );
  assert.equal(code, 2);
  assert.equal(client.calls.length, 0);
  assert.ok(!existsSync(join(dir, "out")));
  await assert.rejects(
    main(["--scripts", dir, "--max-characters", "lots"]),
    /whole number/,
  );
  assert.equal(MAX_CHARACTERS, 40000);
});

test("main renders within the budget, writes the WAV and sidecar, and a rerun costs nothing", async (t) => {
  const dir = tempDir(t);
  writeFileSync(join(dir, "tiny.json"), JSON.stringify(script));
  const client = fakeClient(2);
  const args = [
    "--scripts",
    dir,
    "--out",
    join(dir, "out"),
    "--cache",
    join(dir, "cache"),
  ];
  assert.equal(await main(args, { client, log: () => {} }), 0);
  assert.equal(client.calls.length, 2);
  const wav = join(dir, "out", "tiny.wav");
  assert.equal(wavDuration(wav), 2 + 0.5 + 2 + 3);
  const sidecar = JSON.parse(
    readFileSync(join(dir, "out", "tiny.timeline.json"), "utf8"),
  );
  assert.equal(sidecar.voice, "SAz9YHcvj6GT2YYXdXww");
  assert.deepEqual(
    sidecar.utterances.map((u) => [u.start, u.end]),
    [
      [0, 2],
      [2.5, 4.5],
    ],
  );
  assert.equal(await main(args, { client, log: () => {} }), 0);
  assert.equal(client.calls.length, 2);
});

function fakeElevenLabs(t, handler) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      requests.push({ url: req.url, body: JSON.parse(body), at: Date.now() });
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

test("the client sends the Worker's model and settings at 16 kHz and waits out a 503", async (t) => {
  const { baseURL, requests } = await fakeElevenLabs(t, (n, res) => {
    if (n === 1) {
      res.writeHead(503, { "retry-after": "0.2" });
      res.end("busy");
      return;
    }
    res.writeHead(200, { "content-type": "audio/pcm" });
    res.end(Buffer.alloc(BYTES_PER_SECOND * 0.25));
  });
  const client = elevenLabsClient({
    apiKey: "k",
    baseURL,
    voice: "v",
    model: MODEL,
    settings: { stability: 0.6, similarity_boost: 0.75 },
    sampleRate: SAMPLE_RATE,
  });
  const { duration, characters } = await client.speak("hello");
  assert.equal(duration, 0.25);
  assert.equal(characters, 5);
  assert.equal(requests.length, 2);
  assert.ok(requests[1].at - requests[0].at >= 190);
  assert.equal(requests[0].url, "/v1/text-to-speech/v?output_format=pcm_16000");
  assert.deepEqual(requests[0].body, {
    text: "hello",
    model_id: "eleven_v4_turbo",
    voice_settings: { stability: 0.6, similarity_boost: 0.75 },
  });
});
