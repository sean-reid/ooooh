import assert from "node:assert/strict";
import { join } from "node:path";
import { test } from "node:test";
import { phraseSystem, wordLimit } from "../../worker/src/phrasing.ts";
import {
  buildCorpus,
  emptyState,
  recentWindow,
  recordsFor,
} from "./corpus.mjs";
import { fixturesDir, readJSON } from "./io.mjs";
import {
  criterionNames,
  judgeRequest,
  judgeUserMessage,
  parseJudgement,
} from "./judge.mjs";
import { cost, percentile, summarize, table } from "./report.mjs";
import { hardRules } from "./rules.mjs";
import {
  exemplars,
  phraseRequest,
  variantNames,
  variants,
} from "./variants.mjs";

const fixture = readJSON(join(fixturesDir, "decision.fixture.json"));
const labels = readJSON(join(fixturesDir, "decision.labels.json"));
const records = recordsFor(fixture, labels);

test("the decision fixture yields its three intervention moments and skips finished", () => {
  assert.deepEqual(
    records.map((r) => [r.id, r.kind]),
    [
      ["decision:2", "clarify"],
      ["decision:18", "summarize"],
      ["decision:21", "decide"],
    ],
  );
  for (const record of records) {
    const label = labels.labels.find((l) => l.utterance === record.utterance);
    assert.equal(record.at, label.at);
    assert.ok(record.recent.length <= recentWindow);
    assert.equal(record.recent.at(-1).end, label.at);
    assert.equal(
      record.recent.at(-1).text,
      fixture.segments[record.utterance].text,
    );
    assert.deepEqual(record.state, emptyState());
    assert.deepEqual(Object.keys(record.recent[0]), ["text", "start", "end"]);
  }
  assert.equal(records[0].recent.length, 3);
  assert.equal(records[2].recent.length, recentWindow);
});

test("the whole synthetic corpus has one record per labeled intervention", () => {
  const corpus = buildCorpus(fixturesDir);
  assert.equal(corpus.length, 17);
  assert.equal(new Set(corpus.map((r) => r.id)).size, 17);
  assert.deepEqual([...new Set(corpus.map((r) => r.kind))].sort(), [
    "challenge",
    "clarify",
    "decide",
    "deepen",
    "reflect",
    "summarize",
  ]);
});

test("a corpus record renders through the route's own user message", () => {
  const request = phraseRequest("shipping", records[2]);
  const [message] = request.messages;
  assert.equal(message.role, "user");
  assert.match(message.content, /^Kind: decide\nMode: exploring\n/);
  assert.match(message.content, /Nothing said to them yet\./);
  const lastLine = message.content.split("\n").at(-1);
  const last = records[2].recent.at(-1);
  assert.equal(lastLine, `[${last.start.toFixed(0)}s] ${last.text}`);
});

test("variants keep the shipping request and change only model, prompt, and effort", () => {
  assert.deepEqual(variantNames, ["shipping", "exemplars", "opus"]);
  const shipping = phraseRequest("shipping", records[0]);
  assert.equal(shipping.model, "claude-sonnet-5-5");
  assert.equal(shipping.system, phraseSystem);
  assert.deepEqual(shipping.output_config, { effort: "low" });
  assert.equal(shipping.fallbacks, "default");
  assert.deepEqual(shipping.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(shipping.max_tokens, 1024);
  assert.equal("thinking" in shipping, false);

  const withExemplars = phraseRequest("exemplars", records[0]);
  assert.ok(withExemplars.system.startsWith(phraseSystem));
  assert.equal(withExemplars.model, shipping.model);
  assert.deepEqual(withExemplars.messages, shipping.messages);
  for (const [kind, line] of Object.entries(exemplars)) {
    assert.ok(withExemplars.system.includes(`- ${kind}: ${line}`));
    assert.equal(hardRules(line).pass, true, `${kind}: ${line}`);
  }
  assert.deepEqual(
    Object.keys(exemplars),
    Object.keys(variants).length === 3 && [
      "clarify",
      "deepen",
      "reflect",
      "decide",
      "summarize",
      "challenge",
    ],
  );

  const opus = phraseRequest("opus", records[0]);
  assert.equal(opus.model, "claude-opus-5-5");
  assert.deepEqual(opus.thinking, { type: "adaptive" });
  assert.equal(opus.system, phraseSystem);
  assert.throws(
    () => phraseRequest("haiku", records[0]),
    /unknown variant haiku/,
  );
});

test("hard rules pass a plain question and fail each broken rule", () => {
  assert.deepEqual(
    hardRules("Which part of the handoff is the part that keeps slipping?"),
    {
      oneSentence: true,
      underLimit: true,
      noI: true,
      plain: true,
      pass: true,
    },
  );
  assert.equal(
    hardRules("Slow was fine. Is that the point?").oneSentence,
    false,
  );
  assert.equal(
    hardRules("Is it the 3.5 week gap or the handoff?").oneSentence,
    true,
  );
  const sixteen =
    Array.from({ length: wordLimit + 1 }, (_, i) => `w${i}`).join(" ") + "?";
  assert.equal(hardRules(sixteen).underLimit, false);
  assert.equal(hardRules(sixteen.replace(/ w\d+\?$/, "?")).underLimit, true);
  assert.equal(hardRules("").underLimit, false);
  assert.equal(hardRules("I think the queue is the part you mean?").noI, false);
  assert.equal(hardRules("Is Friday the part you mean?").noI, true);
  assert.equal(hardRules('So "slow was fine" is the point?').plain, false);
  const curly = (text) =>
    text
      .replace(/\[/g, String.fromCharCode(0x201c))
      .replace(/]/g, String.fromCharCode(0x201d));
  assert.equal(
    hardRules(curly("So [slow was fine] is the point?")).plain,
    false,
  );
  assert.equal(hardRules("So *slow* was fine?").plain, false);
  assert.equal(hardRules("- So slow was fine?").plain, false);
  assert.equal(hardRules("Isn't slow fine, then?").plain, true);
});

test("the judge sees the window, the kind, and the line, and never the variant", () => {
  const line = {
    id: records[1].id,
    variant: "exemplars",
    text: "Three threads, then?",
  };
  const request = judgeRequest(records[1], line.text);
  assert.equal(request.model, "claude-opus-5-5");
  assert.deepEqual(request.thinking, { type: "adaptive" });
  assert.equal(request.output_config.format.type, "json_schema");
  assert.deepEqual(request.output_config.format.schema.required, [
    ...criterionNames,
    "note",
  ]);
  const content = request.messages[0].content;
  assert.equal(content, judgeUserMessage(records[1], line.text));
  assert.match(content, /^Kind: summarize\n/);
  assert.ok(content.includes(records[1].recent[0].text));
  assert.ok(content.endsWith("Sentence: Three threads, then?"));
  assert.equal(JSON.stringify(request).includes("exemplars"), false);
  assert.equal(JSON.stringify(request).includes("shipping"), false);
});

test("the judge's parser reads a canned answer and rejects a bad one", () => {
  const answer =
    '{"ownWords": 5, "oneThing": 4, "notAdvice": 5, "fitsKind": 3, "welcome": 4, "note": "Their words, but the side thread."}';
  assert.deepEqual(parseJudgement(answer), {
    scores: { ownWords: 5, oneThing: 4, notAdvice: 5, fitsKind: 3, welcome: 4 },
    note: "Their words, but the side thread.",
  });
  assert.throws(
    () => parseJudgement(answer.replace('"welcome": 4', '"welcome": 6')),
    /welcome/,
  );
  assert.throws(
    () => parseJudgement(answer.replace('"welcome": 4', '"welcome": 4.5')),
    /welcome/,
  );
  assert.throws(
    () => parseJudgement(answer.replace('"fitsKind": 3, ', "")),
    /fitsKind/,
  );
  assert.throws(
    () => parseJudgement(answer.replace(/, "note".*}$/, "}")),
    /note/,
  );
  assert.throws(() => parseJudgement("Here are the scores"), SyntaxError);
});

const lines = (variant, texts, latencies, model = "claude-sonnet-5-5") =>
  texts.map((text, i) => ({
    id: `fixture:${i}`,
    variant,
    text,
    model,
    latencyMs: latencies[i],
    usage: { input: 1000, output: 20, cacheRead: 0, cacheWrite: 0 },
  }));

const score = (id, values) => ({
  id,
  scores: Object.fromEntries(
    criterionNames.map((name, i) => [name, values[i]]),
  ),
  judgeUsage: { input: 500, output: 100, cacheRead: 0, cacheWrite: 0 },
});

test("percentiles use the nearest rank", () => {
  assert.equal(percentile([4, 1, 3, 2], 50), 2);
  assert.equal(percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 90), 9);
  assert.equal(percentile([7], 90), 7);
  assert.equal(percentile([], 50), null);
});

test("cost follows the price table per million tokens", () => {
  assert.equal(cost("claude-sonnet-5-5", { input: 1e6, output: 0 }), 2);
  assert.equal(
    cost("claude-opus-5-5", { input: 0, output: 1e6, cacheRead: 1e6 }),
    20.2,
  );
  assert.throws(
    () => cost("claude-3-opus", { input: 1, output: 1 }),
    /no price for claude-3-opus/,
  );
});

test("the report table carries means, distributions, hard rules, latency, and cost", () => {
  const variantLines = lines(
    "shipping",
    [
      "Is it the queue?",
      "I think so. Yes.",
      "Which part is slow?",
      "Is Friday the deadline that counts?",
    ],
    [900, 1500, 1200, 3000],
  );
  const scores = [
    score("fixture:0", [5, 4, 5, 4, 4]),
    score("fixture:1", [1, 2, 1, 2, 1]),
    score("fixture:2", [3, 4, 5, 4, 3]),
  ];
  const summary = summarize("shipping", variantLines, scores);
  assert.equal(summary.lines, 4);
  assert.equal(summary.scored, 3);
  assert.equal(summary.hardPass, 3);
  assert.equal(summary.criteria.ownWords.mean, 3);
  assert.deepEqual(summary.criteria.ownWords.distribution, [1, 0, 1, 0, 1]);
  assert.deepEqual(summary.criteria.notAdvice.distribution, [1, 0, 0, 0, 2]);
  assert.equal(summary.overall, (22 + 7 + 19) / 15);
  assert.equal(summary.p50, 1200);
  assert.equal(summary.p90, 3000);
  assert.equal(summary.cost, (4 * (1000 * 2 + 20 * 10)) / 1e6);
  assert.equal(summary.judgeCost, (3 * (500 * 4 + 100 * 20)) / 1e6);

  const markdown = table([
    summary,
    summarize(
      "opus",
      lines("opus", ["Settled, then?"], [2500], "claude-opus-5-5"),
    ),
  ]);
  const rows = markdown.split("\n");
  assert.equal(
    rows[0],
    "| variant | lines | hard rules | ownWords | oneThing | notAdvice | fitsKind | welcome | overall | p50 ms | p90 ms | cost |",
  );
  assert.equal(
    rows[2],
    "| shipping | 4 | 3/4 | 3.00 | 3.33 | 3.67 | 3.33 | 2.67 | 3.20 | 1200 | 3000 | $0.009 |",
  );
  assert.equal(
    rows[3],
    "| opus | 1 | 1/1 | - | - | - | - | - | - | 2500 | 2500 | $0.004 |",
  );
  assert.ok(rows.includes("| shipping | ownWords | 1 | 0 | 1 | 0 | 1 |"));
  assert.ok(rows.includes("| opus | welcome | 0 | 0 | 0 | 0 | 0 |"));
  assert.equal(
    rows.at(-1),
    "Judge: 3 lines scored by claude-opus-5-5 for $0.012.",
  );
});
