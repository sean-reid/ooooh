import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import {
  forbiddenFrames,
  phraseRules,
  phraseSystem,
  wordLimit,
} from "../../worker/src/phrasing.ts";
import {
  buildCorpus,
  emptyState,
  fixtureFile,
  recentWindow,
  recordsFor,
} from "./corpus.mjs";
import { contentWords, frameOf, namedWords, tally } from "./frames.mjs";
import { fixturesDir, readJSON } from "./io.mjs";
import {
  criterionNames,
  judgeRequest,
  judgeUserMessage,
  judgeWindow,
  parseJudgement,
} from "./judge.mjs";
import { cost, percentile, summarize, table } from "./report.mjs";
import { hardRules, ruleNames } from "./rules.mjs";
import {
  exemplars,
  loadPrompt,
  phraseRequest,
  recentFor,
  variantNames,
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
    assert.equal(record.transcript.length, record.utterance + 1);
    assert.equal(record.transcript.at(-1).end, label.at);
    assert.equal(
      record.transcript.at(-1).text,
      fixture.segments[record.utterance].text,
    );
    assert.deepEqual(record.state, emptyState());
    assert.deepEqual(Object.keys(record.transcript[0]), [
      "text",
      "start",
      "end",
    ]);
  }
});

test("a fixture sits beside its labels under either name", () => {
  assert.equal(
    fixtureFile(fixturesDir, "decision"),
    join(fixturesDir, "decision.fixture.json"),
  );
  const dir = mkdtempSync(join(tmpdir(), "ooooh-corpus-"));
  writeFileSync(
    join(dir, "2026-10-26-185541.json"),
    JSON.stringify({
      segments: [
        { text: "the first thing", start: 0, end: 2, isFinal: true },
        { text: "a partial", start: 2, end: 3, isFinal: false },
        { text: "the second thing", start: 3, end: 5, isFinal: true },
        { text: "after the label", start: 6, end: 8, isFinal: true },
      ],
    }),
  );
  writeFileSync(
    join(dir, "2026-10-26-185541.labels.json"),
    JSON.stringify({
      fixture: "2026-10-26-185541",
      labels: [
        { utterance: 2, at: 5, kind: "deepen" },
        { utterance: 3, at: 8, kind: "leave" },
      ],
    }),
  );
  assert.equal(
    fixtureFile(dir, "2026-10-26-185541"),
    join(dir, "2026-10-26-185541.json"),
  );
  const corpus = buildCorpus(dir);
  assert.deepEqual(
    corpus.map((r) => [r.id, r.kind]),
    [["2026-10-26-185541:2", "deepen"]],
  );
  assert.deepEqual(
    corpus[0].transcript.map((s) => s.text),
    ["the first thing", "the second thing"],
  );
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

test("the window a prompt gets is what the phone sent at that prompt's commit", () => {
  const transcript = records[2].transcript;
  assert.equal(recentWindow, 6);
  assert.deepEqual(
    recentFor({ phraseUserMessage() {} }, transcript),
    transcript.slice(-6),
  );
  const windowed = { phraseWindow: (segments) => segments.slice(-12) };
  assert.deepEqual(recentFor(windowed, transcript), transcript.slice(-12));
});

test("a corpus record renders through the route's own user message", () => {
  const request = phraseRequest("shipping", records[2]);
  const [message] = request.messages;
  assert.equal(message.role, "user");
  assert.match(message.content, /^Kind: decide\nMode: exploring\n/);
  assert.match(message.content, /Nothing said to them yet\./);
  assert.match(message.content, /Recent words, the last two/);
  const lastLine = message.content.split("\n").at(-1);
  const last = records[2].transcript.at(-1);
  assert.equal(lastLine, `[${last.start.toFixed(0)}s] ${last.text}`);
  assert.equal(
    message.content.includes(records[2].transcript.at(-7).text),
    false,
  );

  const said = [
    { kind: "clarify", text: "Carver Street, or the park?", at: 33 },
    {
      kind: "summarize",
      text: "Money, time, and the bus, three threads.",
      at: 274,
    },
  ];
  const withSaid = phraseRequest("shipping", { ...records[2], said });
  assert.match(
    withSaid.messages[0].content,
    /Said to them this session, oldest first.*\n- \(clarify\) Carver Street, or the park\?\n- \(summarize\) Money, time, and the bus, three threads\./,
  );
});

test("an older prompt loads from git and renders the same record", async () => {
  const prompt = await loadPrompt("HEAD");
  assert.equal(typeof prompt.phraseUserMessage, "function");
  assert.equal(prompt.wordLimit, wordLimit);
  const request = phraseRequest("shipping", records[0], prompt);
  assert.equal(request.system, prompt.phraseSystem);
  assert.match(request.messages[0].content, /^Kind: clarify\n/);
  assert.equal(await loadPrompt(undefined), await loadPrompt());
});

test("variants keep the shipping request and change only model, prompt, and effort", () => {
  assert.deepEqual(variantNames, ["shipping", "bare", "opus"]);
  const shipping = phraseRequest("shipping", records[0]);
  assert.equal(shipping.model, "claude-sonnet-5-5");
  assert.equal(shipping.system, phraseSystem);
  assert.ok(phraseSystem.startsWith(phraseRules));
  assert.deepEqual(shipping.output_config, { effort: "low" });
  assert.equal(shipping.fallbacks, "default");
  assert.deepEqual(shipping.betas, ["server-side-fallback-2026-07-01"]);
  assert.equal(shipping.max_tokens, 1024);
  assert.equal("thinking" in shipping, false);

  const bare = phraseRequest("bare", records[0]);
  assert.equal(bare.system, phraseRules);
  assert.equal(bare.model, shipping.model);
  assert.deepEqual(bare.messages, shipping.messages);
  for (const [kind, line] of Object.entries(exemplars)) {
    assert.ok(shipping.system.includes(`- ${kind}: ${line}`));
    assert.equal(bare.system.includes(line), false);
    assert.equal(hardRules(line).pass, true, `${kind}: ${line}`);
  }
  assert.deepEqual(Object.keys(exemplars), [
    "clarify",
    "deepen",
    "reflect",
    "decide",
    "summarize",
    "challenge",
  ]);

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
  assert.deepEqual(ruleNames, [
    "oneSentence",
    "underLimit",
    "noI",
    "plain",
    "noStockFrame",
  ]);
  assert.deepEqual(
    hardRules("Which part of the handoff is the part that keeps slipping?"),
    {
      oneSentence: true,
      underLimit: true,
      noI: true,
      plain: true,
      noStockFrame: true,
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

test("the frame rule fails the three forbidden frames in any wording and passes a named line", () => {
  for (const frame of forbiddenFrames) {
    assert.equal(hardRules(`${frame}?`).noStockFrame, false, frame);
  }
  for (const line of [
    "How does the Friday deadline sit with you?",
    "What makes the small team so important here?",
    "What sits beneath the worry about the cost?",
  ]) {
    assert.equal(hardRules(line).noStockFrame, false, line);
    assert.equal(hardRules(line).pass, false, line);
  }
  for (const line of [
    "Why does Friday count, and not the Monday after?",
    "Where does the review queue sit in the slow build?",
    "Is the cost the money, or the time in review?",
  ]) {
    assert.equal(hardRules(line).noStockFrame, true, line);
  }
});

test("the diagnosis counts stock frames and words named from the last two utterances", () => {
  const transcript = [
    {
      text: "The handoff to the review queue is the slow part.",
      start: 0,
      end: 4,
    },
    {
      text: "Or the build, the build takes an hour on Fridays.",
      start: 5,
      end: 9,
    },
  ];
  assert.deepEqual(contentWords("The build takes an hour, the build."), [
    "build",
    "takes",
    "hour",
  ]);
  assert.deepEqual(
    namedWords("Is it the build or the review queue?", transcript),
    ["build", "review", "queue"],
  );
  assert.deepEqual(namedWords("How does that sit with you?", transcript), []);
  assert.equal(frameOf("How does that sit with you?"), "how does X sit");
  assert.equal(frameOf("What makes the hour matter?"), "what makes X");
  assert.equal(frameOf("Which part of the build is slow?"), "which part of X");
  assert.equal(frameOf("Is it the build or the queue?"), "is it X or Y");
  assert.equal(frameOf("Why does the build take an hour on Fridays?"), null);

  const corpus = new Map([["f:1", { id: "f:1", transcript }]]);
  const lines = [
    { id: "f:1", text: "How does that sit with you?" },
    { id: "f:1", text: "Is it the build or the queue?" },
    { id: "f:1", text: "Why does the build take an hour on Fridays?" },
    { id: "f:1", text: "What makes this so hard?" },
  ];
  const counts = tally(lines, corpus);
  assert.equal(counts.lines, 4);
  assert.equal(counts.framed, 3);
  assert.deepEqual(
    Object.fromEntries(
      Object.entries(counts.byFrame).map(([name, hits]) => [name, hits.length]),
    ),
    {
      "how does X sit": 1,
      "what makes X": 1,
      "which part of X": 0,
      "is it X or Y": 1,
    },
  );
  assert.deepEqual(
    counts.named.map((l) => l.text),
    [
      "Is it the build or the queue?",
      "Why does the build take an hour on Fridays?",
    ],
  );
  assert.equal(counts.unnamed.length, 2);
  assert.throws(
    () => tally([{ id: "f:9", text: "x" }], corpus),
    /not in the corpus/,
  );
});

test("the judge sees the window, the lines said before, the kind, and the line, and never the variant", () => {
  const line = {
    id: records[1].id,
    variant: "exemplars",
    text: "Three threads, then?",
  };
  const said = [
    { kind: "clarify", text: "Carver Street, or the park?", at: 33 },
  ];
  const request = judgeRequest(records[1], line.text, said);
  assert.equal(request.model, "claude-opus-5-5");
  assert.deepEqual(request.thinking, { type: "adaptive" });
  assert.equal(request.output_config.format.type, "json_schema");
  assert.deepEqual(criterionNames, [
    "ownWords",
    "oneThing",
    "notAdvice",
    "fitsKind",
    "welcome",
    "specific",
    "fresh",
  ]);
  assert.deepEqual(request.output_config.format.schema.required, [
    ...criterionNames,
    "note",
  ]);
  for (const name of ["specific", "fresh"]) {
    assert.match(request.system, new RegExp(`- ${name}: it `));
  }
  const content = request.messages[0].content;
  assert.equal(content, judgeUserMessage(records[1], line.text, said));
  assert.match(content, /^Kind: summarize\n/);
  assert.match(
    content,
    /Said before this, oldest first:\n- Carver Street, or the park\?/,
  );
  assert.equal(judgeWindow, 12);
  const shown = records[1].transcript.slice(-judgeWindow);
  assert.ok(content.includes(shown[0].text));
  assert.equal(content.includes(records[1].transcript[0].text), false);
  assert.ok(content.endsWith("Sentence: Three threads, then?"));
  assert.match(
    judgeUserMessage(records[1], line.text),
    /Nothing said before this\./,
  );
  assert.equal(JSON.stringify(request).includes("exemplars"), false);
  assert.equal(JSON.stringify(request).includes("shipping"), false);
});

test("the judge's parser reads a canned answer and rejects a bad one", () => {
  const answer =
    '{"ownWords": 5, "oneThing": 4, "notAdvice": 5, "fitsKind": 3, "welcome": 4, "specific": 5, "fresh": 2, "note": "Their words, but the side thread."}';
  assert.deepEqual(parseJudgement(answer), {
    scores: {
      ownWords: 5,
      oneThing: 4,
      notAdvice: 5,
      fitsKind: 3,
      welcome: 4,
      specific: 5,
      fresh: 2,
    },
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
    () => parseJudgement(answer.replace('"fresh": 2, ', "")),
    /fresh/,
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
      "What makes Friday important?",
    ],
    [900, 1500, 1200, 3000, 1100],
  );
  const scores = [
    score("fixture:0", [5, 4, 5, 4, 4, 5, 5]),
    score("fixture:1", [1, 2, 1, 2, 1, 1, 3]),
    score("fixture:2", [3, 4, 5, 4, 3, 3, 1]),
  ];
  const summary = summarize("shipping", variantLines, scores);
  assert.equal(summary.lines, 5);
  assert.equal(summary.scored, 3);
  assert.equal(summary.hardPass, 3);
  assert.equal(summary.criteria.ownWords.mean, 3);
  assert.deepEqual(summary.criteria.ownWords.distribution, [1, 0, 1, 0, 1]);
  assert.deepEqual(summary.criteria.notAdvice.distribution, [1, 0, 0, 0, 2]);
  assert.deepEqual(summary.criteria.fresh.distribution, [1, 0, 1, 0, 1]);
  assert.equal(summary.overall, (32 + 11 + 23) / 21);
  assert.equal(summary.p50, 1200);
  assert.equal(summary.p90, 3000);
  assert.ok(Math.abs(summary.cost - (5 * (1000 * 2 + 20 * 10)) / 1e6) < 1e-12);
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
    "| variant | lines | hard rules | ownWords | oneThing | notAdvice | fitsKind | welcome | specific | fresh | overall | p50 ms | p90 ms | cost |",
  );
  assert.equal(
    rows[2],
    "| shipping | 5 | 3/5 | 3.00 | 3.33 | 3.67 | 3.33 | 2.67 | 3.00 | 3.00 | 3.14 | 1200 | 3000 | $0.011 |",
  );
  assert.equal(
    rows[3],
    "| opus | 1 | 1/1 | - | - | - | - | - | - | - | - | 2500 | 2500 | $0.004 |",
  );
  assert.ok(rows.includes("| shipping | ownWords | 1 | 0 | 1 | 0 | 1 |"));
  assert.ok(rows.includes("| opus | welcome | 0 | 0 | 0 | 0 | 0 |"));
  assert.equal(
    rows.at(-1),
    "Judge: 3 lines scored by claude-opus-5-5 for $0.012.",
  );
});
