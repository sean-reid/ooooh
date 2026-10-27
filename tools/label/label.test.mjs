import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import {
  copyFileSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { test } from "node:test";
import { buildLabels, finalSegments } from "../labeler/labels.mjs";
import { MAX_TOKENS, askModel, requestParams } from "./model.mjs";
import {
  MODEL,
  buildProposed,
  kindNames,
  outputSchema,
  readProposal,
  system,
  transcriptLines,
} from "./proposal.mjs";
import { parseReview, renderReview } from "./review.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const estimate = resolve(here, "../../fixtures/synthetic/estimate");
const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));
const fixture = readJSON(join(estimate, "flowing.fixture.json"));
const committed = readJSON(join(estimate, "flowing.labels.json"));
const finals = finalSegments(fixture);
const schema = readJSON(
  resolve(here, "../../fixtures/synthetic/scripts/script.schema.json"),
);

// What the model answers, as JSON text, unsorted and with one duplicate.
const cannedAnswer = JSON.stringify({
  labels: [
    {
      utterance: 29,
      kind: "finished",
      reason: "They say they are done and stop.",
    },
    {
      utterance: 5,
      kind: "leave",
      reason: "A long pause with the plan still moving.",
    },
    {
      utterance: 15,
      kind: "deepen",
      reason: "The index is named but not worked through.",
    },
    {
      utterance: 15,
      kind: "clarify",
      reason: "A second opinion on the same line.",
    },
  ],
});

const tempDir = (t) => {
  const dir = mkdtempSync(join(tmpdir(), "label-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};

const renderFor = (labels, dir = "/tmp/x") =>
  renderReview({
    name: "flowing",
    fixtureFile: "flowing.fixture.json",
    reviewFile: join(dir, "flowing.review.md"),
    finals,
    labels,
  });

test("the model is asked for the schema's kinds and told what each means", () => {
  const schemaKinds = schema.properties.utterances.items.properties.label.enum;
  assert.deepEqual(kindNames, schemaKinds);
  assert.deepEqual(
    outputSchema.properties.labels.items.properties.kind.enum,
    schemaKinds,
  );
  for (const kind of schemaKinds)
    assert.match(system, new RegExp(`^- ${kind}: `, "m"));
  const params = requestParams(finals);
  assert.equal(params.model, MODEL);
  assert.equal(MODEL, "claude-opus-5-5");
  assert.deepEqual(params.thinking, { type: "adaptive" });
  assert.equal(params.output_config.format.type, "json_schema");
  assert.equal(params.output_config.format.schema, outputSchema);
  assert.match(
    params.messages[0].content,
    /^Transcript, 30 utterances:\n\[0\] 0:00\.000/,
  );
});

test("the transcript the model reads carries index, times, pause, and text", () => {
  const lines = transcriptLines(finals);
  assert.equal(lines.length, 30);
  assert.equal(
    lines[5],
    `[5] 1:13.692 to 1:24.761, pause 15.0 s: ${finals[5].text}`,
  );
  assert.match(lines[29], /^\[29\] \d+:\d\d\.\d{3} to 7:29\.500, end: /);
});

test("a model answer is sorted, checked against the fixture, and one label per utterance", () => {
  const proposal = readProposal(JSON.parse(cannedAnswer), finals);
  assert.deepEqual(
    proposal.map((p) => [p.utterance, p.kind]),
    [
      [5, "leave"],
      [15, "deepen"],
      [29, "finished"],
    ],
  );
  const proposed = buildProposed("flowing", finals, proposal);
  assert.equal(proposed.fixture, "flowing");
  for (const entry of proposed.labels) {
    assert.deepEqual(Object.keys(entry), ["utterance", "at", "kind", "reason"]);
    assert.equal(entry.at, finals[entry.utterance].end);
    assert.ok(entry.reason.length > 0);
  }
  assert.throws(
    () =>
      readProposal(
        { labels: [{ utterance: 30, kind: "leave", reason: "" }] },
        finals,
      ),
    /utterance 30, the fixture has 30/,
  );
  assert.throws(
    () =>
      readProposal(
        { labels: [{ utterance: 1, kind: "nudge", reason: "" }] },
        finals,
      ),
    /unknown kind nudge/,
  );
  assert.throws(() => readProposal({ answer: [] }, finals), /no labels array/);
});

test("the review shows every utterance with its labels and reasons inline", () => {
  const proposal = readProposal(JSON.parse(cannedAnswer), finals);
  const review = renderFor(buildProposed("flowing", finals, proposal).labels);
  assert.match(review, /^# flowing\n\nfixture: flowing\.fixture\.json\n\n/);
  assert.match(review, /To remove one, delete its `label:` line/);
  assert.match(
    review,
    /node tools\/label\/label\.mjs fold \/tmp\/x\/flowing\.review\.md/,
  );
  for (const kind of kindNames)
    assert.match(review, new RegExp(`^- ${kind}: `, "m"));
  finals.forEach((segment, index) => {
    assert.match(
      review,
      new RegExp(`^## ${index}  \\d+:\\d\\d\\.\\d{3} to `, "m"),
    );
    assert.ok(
      review.includes(`\n${segment.text}\n`),
      `utterance ${index} text`,
    );
  });
  assert.match(
    review,
    /## 5  1:13\.692 to 1:24\.761  pause 15\.0 s\n[^\n]+\nlabel: leave\nreason: A long pause/,
  );
  assert.match(review, /## 29 [^\n]+  end\n[^\n]+\nlabel: finished\n/);
  assert.equal(review.match(/^label: /gm).length, 3);
  const parsed = parseReview(review);
  assert.equal(parsed.fixtureFile, "flowing.fixture.json");
  assert.deepEqual(
    [...parsed.labels],
    [
      [5, "leave"],
      [15, "deepen"],
      [29, "finished"],
    ],
  );
});

test("the committed flowing labels survive a review and a fold unchanged", () => {
  const review = renderFor(committed.labels);
  const { labels } = parseReview(review);
  assert.deepEqual(buildLabels("flowing", finals, labels), committed);
});

test("an edited review folds into the labels the owner wrote", () => {
  const proposal = readProposal(JSON.parse(cannedAnswer), finals);
  let review = renderFor(buildProposed("flowing", finals, proposal).labels);
  review = review.replace(
    "label: leave\nreason: A long pause with the plan still moving.\n",
    "",
  );
  review = review.replace("label: deepen", "label: reflect");
  review = review.replace(
    `\n${finals[11].text}\n`,
    `\n${finals[11].text}\nlabel: challenge\n`,
  );
  const { labels } = parseReview(review);
  assert.deepEqual(buildLabels("flowing", finals, labels), {
    fixture: "flowing",
    labels: [
      { utterance: 11, at: finals[11].end, kind: "challenge" },
      { utterance: 15, at: finals[15].end, kind: "reflect" },
      { utterance: 29, at: finals[29].end, kind: "finished" },
    ],
  });
});

test("a review with a bad edit names the line", () => {
  const review = renderFor(committed.labels);
  const lines = review.split("\n");
  const at = lines.findIndex((line) => line === "label: deepen");
  lines[at] = "label: deeper";
  assert.throws(
    () => parseReview(lines.join("\n")),
    new RegExp(`line ${at + 1}: unknown kind "deeper"`),
  );
  lines[at] = "label: deepen";
  lines.splice(at + 1, 0, "label: clarify");
  assert.throws(
    () => parseReview(lines.join("\n")),
    new RegExp(`line ${at + 2}: utterance 15 has two labels`),
  );
  assert.throws(
    () => parseReview(review.replace("fixture: flowing.fixture.json\n", "")),
    /no fixture: line/,
  );
});

test("the CLI reviews a proposal, folds the edit, and refuses to propose without a key", (t) => {
  const dir = tempDir(t);
  const cli = join(here, "label.mjs");
  copyFileSync(
    join(estimate, "flowing.fixture.json"),
    join(dir, "flowing.fixture.json"),
  );
  const proposal = readProposal(JSON.parse(cannedAnswer), finals);
  writeFileSync(
    join(dir, "flowing.labels.proposed.json"),
    JSON.stringify(buildProposed("flowing", finals, proposal), null, 2),
  );
  execFileSync(process.execPath, [
    cli,
    "review",
    join(dir, "flowing.fixture.json"),
  ]);
  const reviewFile = join(dir, "flowing.review.md");
  const review = readFileSync(reviewFile, "utf8");
  assert.match(review, /^fixture: flowing\.fixture\.json$/m);
  writeFileSync(reviewFile, review.replace("label: deepen", "label: decide"));
  const out = execFileSync(process.execPath, [cli, "fold", reviewFile], {
    encoding: "utf8",
  });
  assert.match(out, /^3 labels \(decide 1, finished 1, leave 1\)\n/);
  assert.deepEqual(readJSON(join(dir, "flowing.labels.json")), {
    fixture: "flowing",
    labels: [
      { utterance: 5, at: finals[5].end, kind: "leave" },
      { utterance: 15, at: finals[15].end, kind: "decide" },
      { utterance: 29, at: finals[29].end, kind: "finished" },
    ],
  });

  const env = { ...process.env };
  delete env.ANTHROPIC_API_KEY;
  const refused = spawnSync(
    process.execPath,
    [cli, "propose", join(dir, "flowing.fixture.json")],
    {
      env,
      encoding: "utf8",
    },
  );
  assert.equal(refused.status, 2);
  assert.match(refused.stderr, /ANTHROPIC_API_KEY/);
});

test("askModel sends the request shape once and reads the text blocks back", async () => {
  const sent = [];
  const answers = [];
  class StandIn {
    constructor(options) {
      sent.push(options);
    }
    beta = {
      messages: {
        create: async (params) => (sent.push(params), answers.shift()),
      },
    };
  }
  const reply = (stop_reason, content) => ({
    stop_reason,
    stop_details: stop_reason === "refusal" ? { category: "test" } : null,
    content,
    usage: { input_tokens: 10, output_tokens: 20 },
    model: MODEL,
  });
  answers.push(
    reply("end_turn", [
      { type: "thinking", thinking: "" },
      { type: "text", text: cannedAnswer.slice(0, 40) },
      { type: "text", text: cannedAnswer.slice(40) },
    ]),
  );
  const { parsed, usage, model } = await askModel(
    finals,
    "key-under-test",
    StandIn,
  );
  assert.equal(sent[0].apiKey, "key-under-test");
  assert.deepEqual(sent[1], requestParams(finals));
  assert.equal(parsed.labels.length, 4);
  assert.equal(usage.output_tokens, 20);
  assert.equal(model, MODEL);

  answers.push(reply("max_tokens", [{ type: "text", text: "{" }]));
  await assert.rejects(
    askModel(finals, "k", StandIn),
    new RegExp(`cut off at ${MAX_TOKENS}`),
  );
  answers.push(reply("refusal", []));
  await assert.rejects(
    askModel(finals, "k", StandIn),
    /refused: {"category":"test"}/,
  );
});
