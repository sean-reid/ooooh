import assert from "node:assert/strict";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import {
  MAX_TOKENS,
  TOPICS,
  checkScript,
  costOf,
  generateScript,
  main,
  outputSchema,
  parseTopics,
  readScript,
  requestParams,
  systemPrompt,
  userMessage,
} from "./scripts.mjs";
import { estimateDuration } from "./synth.mjs";
import { tempDir } from "./testing.mjs";

const style = JSON.parse(
  readFileSync(new URL("./fixtures/style.json", import.meta.url), "utf8"),
);

// A model answer that passes every rule: 30 lines of 18 words, a 5 s pause
// every eighth line carrying an intervention, finished at the end.
function cannedAnswer() {
  const line =
    "um so the thing I keep coming back to is the number and whether it even matters here";
  const utterances = Array.from({ length: 30 }, (_, i) => {
    const intervention = (i + 1) % 8 === 0;
    return {
      text: line,
      pauseAfter: intervention ? 5 : 1,
      label: intervention ? "clarify" : null,
      note: intervention ? "the number is never named" : null,
    };
  });
  utterances.at(-1).label = "finished";
  utterances.at(-1).pauseAfter = 3;
  return {
    summary:
      "Weighing a number that never gets named, and landing on asking for it. Labels: clarify where the number is left vague.",
    utterances,
  };
}

test("the system prompt carries the style numbers and the label kinds, never text", () => {
  const prompt = systemPrompt(style);
  assert.match(prompt, /4 real sessions/);
  assert.match(prompt, /about 170\.5 s and 320 words/);
  assert.match(prompt, /median of 45/);
  assert.match(prompt, /80 percent of gaps are under a second/);
  assert.match(prompt, /1\.2 per 100 words/);
  assert.match(
    prompt,
    /- leave: The pause after this utterance is long and productive/,
  );
  assert.match(prompt, /deepen 0\.5, leave 1\.25/);
  assert.match(prompt, /468 to 780 words/);
  assert.doesNotMatch(prompt, /\[\d+\] \d+:/);
});

test("the user message names the script and feeds violations back", () => {
  const entry = { name: "x", topic: "a thing" };
  assert.equal(
    userMessage(entry),
    'Write the script named "x". Topic: a thing.',
  );
  assert.match(
    userMessage(entry, ["too short"]),
    /previous attempt broke[\s\S]*- too short/,
  );
});

test("request params use the labeler's model with adaptive thinking and the output schema", () => {
  const params = requestParams("sys", "user");
  assert.equal(params.model, "claude-opus-5-5");
  assert.equal(params.max_tokens, MAX_TOKENS);
  assert.deepEqual(params.thinking, { type: "adaptive" });
  assert.equal(params.fallbacks, "default");
  assert.equal(params.output_config.format.schema, outputSchema);
  assert.deepEqual(params.messages, [{ role: "user", content: "user" }]);
  const label = outputSchema.properties.utterances.items.properties.label;
  assert.ok(label.anyOf[0].enum.includes("wrapUp"));
  assert.deepEqual(label.anyOf[1], { type: "null" });
});

test("readScript drops nulls, sets the name, and validates against the real schema", () => {
  const script = readScript(cannedAnswer(), "canned");
  assert.equal(script.name, "canned");
  assert.equal(script.utterances.length, 30);
  assert.deepEqual(Object.keys(script.utterances[0]), ["text", "pauseAfter"]);
  assert.deepEqual(Object.keys(script.utterances[7]), [
    "text",
    "pauseAfter",
    "label",
    "note",
  ]);
  assert.equal(script.utterances[7].label, "clarify");
  assert.throws(() => readScript({ summary: "x" }, "n"), /no utterances array/);
  const bad = cannedAnswer();
  bad.utterances[0].pauseAfter = -1;
  assert.throws(
    () => readScript(bad, "n"),
    /fails the schema[\s\S]*-1 is below 0/,
  );
  assert.throws(() => readScript(cannedAnswer(), "Bad Name"), /does not match/);
});

test("checkScript passes the canned answer and names each broken rule", () => {
  const good = readScript(cannedAnswer(), "canned");
  assert.deepEqual(checkScript(good), []);
  const speech = good.utterances.reduce(
    (s, u) => s + estimateDuration(u.text),
    0,
  );
  assert.ok(speech > 180 && speech < 300);

  const short = { ...good, utterances: good.utterances.slice(0, 5) };
  short.utterances[4] = { ...short.utterances[4], label: "finished" };
  assert.match(checkScript(short).join("\n"), /speech is \d+ s/);

  const weak = structuredClone(good);
  weak.utterances[7].pauseAfter = 2;
  assert.match(
    checkScript(weak).join("\n"),
    /utterance 7 \(clarify\) pauses 2 s/,
  );

  const early = structuredClone(good);
  early.utterances[3].label = "finished";
  assert.match(
    checkScript(early).join("\n"),
    /finished or wrapUp must sit on the last/,
  );

  const quiet = structuredClone(good);
  quiet.utterances.forEach((u) => (u.text = u.text.replace(/um /, "")));
  assert.match(checkScript(quiet).join("\n"), /no um or uh/);

  const leave = structuredClone(good);
  leave.utterances[1].label = "leave";
  leave.utterances[1].pauseAfter = 10;
  assert.match(
    checkScript(leave).join("\n"),
    /\(leave\) pauses 10 s, leave needs 15/,
  );

  const monotone = structuredClone(good);
  monotone.utterances.forEach((u) => (u.pauseAfter = 1));
  assert.match(checkScript(monotone).join("\n"), /without a pause of 4 s/);
});

function fakeClient(answers) {
  const calls = [];
  return {
    calls,
    beta: {
      messages: {
        stream(params) {
          calls.push(params);
          const answer = answers.shift();
          return {
            finalMessage: async () => ({
              model: "claude-opus-5-5",
              stop_reason: answer.stop_reason ?? "end_turn",
              stop_details: answer.stop_details ?? null,
              content: [{ type: "text", text: JSON.stringify(answer.body) }],
              usage: { input_tokens: 1000, output_tokens: 5000 },
            }),
          };
        },
      },
    },
  };
}

test("generateScript retries with the violations and sums the usage", async () => {
  const broken = cannedAnswer();
  broken.utterances[7].pauseAfter = 1;
  const client = fakeClient([{ body: broken }, { body: cannedAnswer() }]);
  const logged = [];
  const result = await generateScript(client, "sys", TOPICS[0], {
    log: (line) => logged.push(line),
  });
  assert.equal(result.attempts, 2);
  assert.equal(result.script.name, "work-decision");
  assert.deepEqual(result.usage, { input_tokens: 2000, output_tokens: 10000 });
  assert.equal(client.calls.length, 2);
  assert.match(
    client.calls[1].messages[0].content,
    /utterance 7 \(clarify\) pauses 1 s/,
  );
  assert.match(logged[0], /attempt 1 broke 2 rule/);
  assert.equal(costOf(result.usage), 0.208);
});

test("generateScript gives up after the attempts and surfaces refusals and cut-offs", async () => {
  const broken = cannedAnswer();
  broken.utterances.forEach((u) => (u.pauseAfter = 1));
  const always = fakeClient([{ body: broken }, { body: broken }]);
  await assert.rejects(
    generateScript(always, "sys", TOPICS[1], { attempts: 2 }),
    /no script passed the rules in 2 attempts/,
  );
  await assert.rejects(
    generateScript(
      fakeClient([{ body: {}, stop_reason: "max_tokens" }]),
      "s",
      TOPICS[1],
    ),
    /cut off at 32000 tokens/,
  );
  await assert.rejects(
    generateScript(
      fakeClient([
        { body: {}, stop_reason: "refusal", stop_details: { category: "x" } },
      ]),
      "s",
      TOPICS[1],
    ),
    /the model refused: {"category":"x"}/,
  );
});

test("parseTopics takes the built-in list or name:topic pairs", () => {
  assert.deepEqual(parseTopics({}, 2), TOPICS.slice(0, 2));
  assert.equal(TOPICS.length, 6);
  assert.deepEqual(
    parseTopics({ topic: ["a-b: about a thing: with colons"] }, 1),
    [{ name: "a-b", topic: "about a thing: with colons" }],
  );
  assert.throws(() => parseTopics({ topic: ["nocolon"] }, 1), /name:topic/);
  assert.throws(() => parseTopics({}, 7), /--count 7 needs --topic/);
});

test("main writes one validated script per topic with a fake client", async (t) => {
  const dir = tempDir(t);
  const stylePath = join(dir, "style.json");
  writeFileSync(stylePath, JSON.stringify(style));
  const client = fakeClient([
    { body: cannedAnswer() },
    { body: cannedAnswer() },
  ]);
  const code = await main(
    ["--style", stylePath, "--count", "2", "--out", join(dir, "scripts")],
    { client },
  );
  assert.equal(code, 0);
  for (const name of ["work-decision", "product-idea"]) {
    const script = JSON.parse(
      readFileSync(join(dir, "scripts", `${name}.json`), "utf8"),
    );
    assert.equal(script.name, name);
    assert.deepEqual(checkScript(script), []);
  }
  assert.match(client.calls[0].system, /measured from 4 real sessions/);
  assert.match(client.calls[1].messages[0].content, /named "product-idea"/);
});
