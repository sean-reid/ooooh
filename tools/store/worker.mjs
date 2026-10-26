// A Worker stand-in for the store captures: the same routes, canned answers, no provider keys.
// The demo asks one question after the "real money" line and ends with the seeded history's notes,
// so every recording shows the same session. node tools/store/worker.mjs [port]
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { governorConfig } from "../../worker/src/config.ts";

const port = Number(process.argv[2] ?? 8790);
const fixtures = new URL(
  "../../Packages/Tests/ProxyTests/Fixtures/",
  import.meta.url,
);
const fixture = async (name) =>
  JSON.parse(await readFile(new URL(name, fixtures), "utf8"));

const question = "What would make it feel worth the cost?";
const notes = {
  title: "Carver Street or the park",
  ideas: [],
  decisions: [
    {
      id: "make-the-case",
      text: "Make the case for the park place tonight with the numbers",
      span: { start: 0, end: 0 },
    },
  ],
  questions: [],
  insights: [
    {
      id: "real-gap",
      text: "The real gap is six hundred a month, not a thousand",
      span: { start: 0, end: 0 },
    },
  ],
  actions: [],
  openThreads: [
    {
      id: "time-versus-money",
      text: "How Sam and I weight time against money",
    },
    {
      id: "eighteen-month-lease",
      text: "Whether the eighteen month lease is a problem",
    },
  ],
  quotes: [],
};

const json = (res, status, body) => {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
};

const read = (req) =>
  new Promise((resolve) => {
    let data = "";
    req.on("data", (chunk) => (data += chunk));
    req.on("end", () => resolve(data ? JSON.parse(data) : {}));
  });

async function decide(body) {
  const answer = await fixture("decide.json");
  const last = body.recentTranscript?.at(-1)?.text ?? "";
  const moment = last.includes("real money");
  answer.answers.goodMoment.probability = moment ? 0.96 : 0.08;
  answer.answers.intervention.choice = "clarify";
  answer.answers.seemsFinished.probability = 0.02;
  for (const cue of Object.keys(answer.answers.cues))
    answer.answers.cues[cue] = 0.05;
  return answer;
}

function phrase(req, res) {
  if (!req.headers.accept?.includes("text/event-stream"))
    return json(res, 200, { text: question });
  res.writeHead(200, { "content-type": "text/event-stream" });
  for (const word of question.split(" ")) {
    res.write(
      `event: delta\ndata: ${JSON.stringify({ text: word + " " })}\n\n`,
    );
  }
  res.end(`event: done\ndata: ${JSON.stringify({ text: question })}\n\n`);
}

createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  console.log(req.method, path);
  if (path === "/health") return json(res, 200, { ok: true, version: "store" });
  if (path === "/v1/config") return json(res, 200, governorConfig);
  if (path === "/v1/session/start")
    return json(res, 200, {
      allowed: true,
      free: true,
      remainingFree: 2,
      promptMinutes: 20,
    });
  if (path === "/v1/session/end") return res.writeHead(204).end();
  if (path === "/v1/decide")
    return json(res, 200, await decide(await read(req)));
  if (path === "/v1/compact")
    return json(res, 200, await fixture("compact.json"));
  if (path === "/v1/phrase") return phrase(req, res);
  if (path === "/v1/notes")
    return json(res, 200, {
      notes,
      usage: { inputTokens: 0, outputTokens: 0 },
    });
  json(res, 502, { error: "upstream", status: 0, detail: "not served here" });
}).listen(port, "127.0.0.1", () =>
  console.log(`store worker on http://127.0.0.1:${port}`),
);
