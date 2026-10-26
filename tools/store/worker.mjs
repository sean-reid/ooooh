// A Worker stand-in for the store captures: the same routes, no provider keys, and the answers
// one real run produced, read from seed.json, so every recording shows the same session.
//   node tools/store/worker.mjs [port]                   answers from seed.json
//   node tools/store/worker.mjs --record <worker> [port]  forwards to a running Worker and writes
//                                                         what it asked and wrote into seed.json
import { createServer, request as httpRequest } from "node:http";
import { readFile, writeFile } from "node:fs/promises";
import { governorConfig } from "../../worker/src/config.ts";

const args = process.argv.slice(2);
const recordAt = args[0] === "--record" ? new URL(args.splice(0, 2)[1]) : null;
const port = Number(args[0] ?? 8790);
const seedFile = new URL("seed.json", import.meta.url);
const fixtures = new URL(
  "../../Packages/Tests/ProxyTests/Fixtures/",
  import.meta.url,
);
const fixture = async (name) =>
  JSON.parse(await readFile(new URL(name, fixtures), "utf8"));

const json = (res, status, body) => {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const read = (req) =>
  new Promise((resolve) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
  });

const parse = (buffer) =>
  buffer.length ? JSON.parse(buffer.toString("utf8")) : {};

// The seeded run: Jev's one good moment is the utterance the real run asked after, the question
// is what Sonnet said there, and the notes are what Opus wrote at the end.
async function serveSeed() {
  const seed = JSON.parse(await readFile(seedFile, "utf8"));

  async function decide(body) {
    const answer = await fixture("decide.json");
    const last = body.recentTranscript?.at(-1)?.text ?? "";
    answer.answers.goodMoment.probability = last === seed.moment ? 0.96 : 0.08;
    answer.answers.intervention.choice = seed.kind;
    answer.answers.seemsFinished.probability = 0.02;
    for (const cue of Object.keys(answer.answers.cues))
      answer.answers.cues[cue] = 0.05;
    return answer;
  }

  function phrase(req, res) {
    if (!req.headers.accept?.includes("text/event-stream"))
      return json(res, 200, { text: seed.question });
    res.writeHead(200, { "content-type": "text/event-stream" });
    for (const word of seed.question.split(" ")) {
      res.write(
        `event: delta\ndata: ${JSON.stringify({ text: word + " " })}\n\n`,
      );
    }
    res.end(
      `event: done\ndata: ${JSON.stringify({ text: seed.question })}\n\n`,
    );
  }

  return async (req, res, path) => {
    if (path === "/health")
      return json(res, 200, { ok: true, version: "store" });
    if (path === "/v1/config") return json(res, 200, governorConfig);
    if (path === "/v1/session/start")
      return json(res, 200, await fixture("session-start-free.json"));
    if (path === "/v1/session/end") return res.writeHead(204).end();
    if (path === "/v1/decide")
      return json(res, 200, await decide(parse(await read(req))));
    if (path === "/v1/compact")
      return json(res, 200, await fixture("compact.json"));
    if (path === "/v1/phrase") return phrase(req, res);
    if (path === "/v1/notes")
      return json(res, 200, {
        notes: seed.notes,
        usage: { inputTokens: 0, outputTokens: 0 },
      });
    json(res, 502, { error: "upstream", status: 0, detail: "not served here" });
  };
}

// Forwards every request to the real Worker and keeps what the demo needs from the answers: the
// utterance the question followed, its kind, the question, and the notes. Prints each provider
// route's usage as the Worker reports it. Jev scores no moment of the demo fixture above the
// speak bar, so the first labeled moment is forced through its answer and Sonnet phrases it.
async function record(upstream) {
  const seed = { recorded: new Date().toISOString().slice(0, 10) };
  const root = new URL("../../", import.meta.url);
  const { segments } = JSON.parse(
    await readFile(
      new URL("fixtures/synthetic/estimate/decision.fixture.json", root),
      "utf8",
    ),
  );
  const { labels } = JSON.parse(
    await readFile(
      new URL("fixtures/synthetic/estimate/decision.labels.json", root),
      "utf8",
    ),
  );
  const forced = {
    text: segments[labels[0].utterance].text,
    kind: labels[0].kind,
  };
  let lastDecided = "";

  const save = async () => {
    await writeFile(seedFile, JSON.stringify(seed, null, 2) + "\n");
    console.log("seed.json written");
  };

  const forward = (req, body) =>
    new Promise((resolve, reject) => {
      // Plain bodies, so the answers can be read here as well as relayed.
      const headers = {
        ...req.headers,
        host: upstream.host,
        "accept-encoding": "identity",
      };
      const out = httpRequest(
        {
          hostname: upstream.hostname,
          port: upstream.port,
          path: req.url,
          method: req.method,
          headers,
        },
        resolve,
      );
      out.on("error", reject);
      out.end(body);
    });

  return async (req, res, path) => {
    const body = await read(req);
    const sent = parse(body);
    if (path === "/v1/decide")
      lastDecided = sent.recentTranscript?.at(-1)?.text ?? lastDecided;
    const started = Date.now();
    const answer = await forward(req, body);
    const chunks = [];
    for await (const chunk of answer) chunks.push(chunk);
    let text = Buffer.concat(chunks).toString("utf8");
    let usage = "";
    if (
      answer.statusCode === 200 &&
      path === "/v1/decide" &&
      lastDecided === forced.text
    ) {
      const parsed = JSON.parse(text);
      parsed.answers.goodMoment.probability = 0.96;
      parsed.answers.intervention.choice = forced.kind;
      text = JSON.stringify(parsed);
      usage = "forced ";
    }
    const headers = {
      ...answer.headers,
      "content-length": Buffer.byteLength(text),
    };
    delete headers["transfer-encoding"];
    res.writeHead(answer.statusCode, headers);
    res.end(text);
    if (answer.statusCode === 200) {
      if (path === "/v1/phrase") {
        const done = text.match(/^event: done\ndata: (.*)$/m);
        seed.question = done ? JSON.parse(done[1]).text : JSON.parse(text).text;
        seed.kind = sent.kind;
        seed.moment = sent.recent?.at(-1)?.text ?? lastDecided;
      } else if (path === "/v1/notes") {
        const parsed = JSON.parse(text);
        seed.notes = parsed.notes;
        usage = JSON.stringify(parsed.usage);
        await save();
      } else if (path === "/v1/decide") {
        const { answers, usage: spent } = JSON.parse(text);
        usage += JSON.stringify({
          ...spent,
          goodMoment: answers.goodMoment.probability,
          intervention: answers.intervention.choice,
          seemsFinished: answers.seemsFinished.probability,
          last: lastDecided.slice(0, 40),
        });
      } else if (path === "/v1/compact") {
        usage = JSON.stringify(JSON.parse(text).usage ?? {});
      }
    }
    console.log(
      req.method,
      path,
      answer.statusCode,
      `${Date.now() - started}ms`,
      usage,
    );
  };
}

const handle = recordAt ? await record(recordAt) : await serveSeed();
const server = createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (!recordAt) console.log(req.method, path);
  try {
    await handle(req, res, path);
  } catch (error) {
    console.error(req.method, path, error.message);
    if (!res.headersSent)
      json(res, 502, { error: "upstream", status: 0, detail: error.message });
    else res.end();
  }
});
server.listen(port, "127.0.0.1", () =>
  console.log(
    `store worker on http://127.0.0.1:${server.address().port}` +
      (recordAt ? `, recording ${recordAt}` : ""),
  ),
);
