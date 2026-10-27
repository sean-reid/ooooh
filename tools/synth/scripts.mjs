#!/usr/bin/env node
import { mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { KINDS } from "../labeler/labels.mjs";
import { loadSDK } from "../label/model.mjs";
import { MODEL } from "../label/proposal.mjs";
import { STYLE_PATH } from "./style.mjs";
import { SCHEMA_PATH, estimateDuration } from "./synth.mjs";
import { validate } from "./validate.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const VOICE_SCRIPTS_DIR = resolve(
  here,
  "../../fixtures/synthetic/voice/scripts",
);
// Thinking shares this; a five minute script is about 8,000 tokens of JSON.
export const MAX_TOKENS = 32_000;
export const DEADLINE_MS = 600_000;
// Opus 5.5 list prices per million tokens, for the cost line.
export const PRICE = { input: 4, output: 20 };

export const TOPICS = [
  {
    name: "work-decision",
    topic:
      "whether to take a role leading a new team at work or stay hands-on; the offer is real and the answer is due this week",
  },
  {
    name: "product-idea",
    topic:
      "a small product idea that keeps coming back, what it would take to try it in a weekend, and whether anyone would pay",
  },
  {
    name: "hard-conversation",
    topic:
      "a conversation I keep putting off with someone close, what I want to say, and what I am afraid they will say back",
  },
  {
    name: "trip-planning",
    topic:
      "planning a trip with two other people, too many places and not enough days, and the one thing I will not give up",
  },
  {
    name: "money-question",
    topic:
      "whether to spend on something big this year or hold the money, and what the number would need to be to feel fine",
  },
  {
    name: "stalled-project",
    topic:
      "a side project that stalled months ago, what stopped it, and whether to finish it or let it go",
  },
];

const kindNames = KINDS.map((k) => k.kind);
const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));

// Structured outputs take types, enums, required, and additionalProperties; the
// script schema's lengths and ranges are checked after the answer arrives.
export const outputSchema = {
  type: "object",
  additionalProperties: false,
  required: ["summary", "utterances"],
  properties: {
    summary: { type: "string" },
    utterances: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["text", "pauseAfter", "label", "note"],
        properties: {
          text: { type: "string" },
          pauseAfter: { type: "number" },
          label: {
            anyOf: [{ type: "string", enum: kindNames }, { type: "null" }],
          },
          note: { anyOf: [{ type: "string" }, { type: "null" }] },
        },
      },
    },
  },
};

export const RULES = {
  speechSeconds: [180, 300],
  pauseSeconds: [0.3, 60],
  interventionPause: 5,
  leavePause: 15,
  longPause: 4,
  longPauseEvery: 120,
  interventions: [2, 6],
};

const seconds = (value) => `${value} s`;

export function systemPrompt(style) {
  const p = style.pauses;
  const kinds = KINDS.map(({ kind, meaning }) => `- ${kind}: ${meaning}`).join(
    "\n",
  );
  return `You write scripts for one person thinking aloud alone, into a phone, with no one answering. The scripts stand in for real recordings of one speaker, so they have to sound like that speaker, whose style is given below as numbers measured from their recordings. Nothing of what they said is included; match the numbers, not a guess at the person.

The speaker's style, measured from ${style.sessions} real sessions transcribed by a phone:
- A session runs about ${style.session.meanSeconds} s and ${style.session.meanWords} words, at ${style.session.wordsPerMinute} words a minute while talking.
- They talk in long runs between real pauses: words between pauses of a second or more have a median of ${style.wordsPerRun.median} and a 75th percentile of ${style.wordsPerRun.p75}. The transcriber cut those runs into pieces with a median of ${style.wordsPerUtterance.median} words, mostly at breaths, so the sentences run on.
- Pauses: ${Math.round(p.shareUnderOneSecond * 100)} percent of gaps are under a second. A session has about ${p.perSessionOverOneSecond} pauses over a second (median ${seconds(p.overOneSecond.median)}, 75th percentile ${seconds(p.overOneSecond.p75)}) and about ${p.perSessionOverFiveSeconds} over five seconds; the longest was ${seconds(p.max)}.
- Fillers (um, uh, you know, like, a sentence opening with so): ${style.fillersPer100Words} per 100 words in the transcript. Phones drop most ums, so the spoken rate is higher; write two to three per 100 words.
- Restarts: ${style.restartsPer100Words} per 100 words, a word said twice or a sentence dropped and started over.
- Questions to themselves: ${style.questionsPerUtterance} per utterance. They mostly state and weigh, they rarely ask.
- Endings: the last line averages ${style.endings.meanWords} words, is a question ${Math.round(style.endings.questionShare * 100)} percent of the time, and uses a closing word (okay, that's it, done) ${Math.round(style.endings.closerShare * 100)} percent of the time. They stop when the thought is complete, without announcing it.
- Labels a reviewer gave per session, on average: ${Object.entries(
    style.labelsPerSession,
  )
    .map(([k, v]) => `${k} ${v}`)
    .join(", ")}.

A quiet listener may say one short sentence in a pause, only when it would help. Each utterance may carry one label naming what the listener should do in the pause right after it. The kinds:
${kinds}

Rules for the script:
- Speech between ${RULES.speechSeconds[0]} and ${RULES.speechSeconds[1]} seconds at 2.6 words a second, so ${Math.round(RULES.speechSeconds[0] * 2.6)} to ${Math.round(RULES.speechSeconds[1] * 2.6)} words in total.
- One utterance is what the speaker says between two pauses, as spoken: fillers, restarts, half sentences, concrete names and numbers, no polish. Vary length the way the measurements do, from one word to a long run.
- pauseAfter is the silence after the utterance in seconds, between ${RULES.pauseSeconds[0]} and ${RULES.pauseSeconds[1]}. Most are short, following the measured distribution. Put a pause of ${RULES.longPause} s or more in every ${RULES.longPauseEvery} s of the session.
- Most utterances have no label. Give the session ${RULES.interventions[0]} to ${RULES.interventions[1]} interventions (clarify, deepen, reflect, decide, summarize, challenge), each on an utterance whose pauseAfter is at least ${RULES.interventionPause}. Mark leave on long productive silences, pauseAfter at least ${RULES.leavePause}. Put finished on the last utterance only, once. Use recall and wrapUp only if the speaker talks to the phone directly, and most sessions do not.
- note, when given, is one line in plain words saying what in the text earns the label; null otherwise.
- summary is two or three sentences: what the session is about and where it lands, then "Labels:" and why each labeled moment earns its kind, the way a reviewer would write it.
- Fresh topic as given, first person, present day, a specific situation with stakes. No names of real companies or people.`;
}

export function userMessage({ topic, name }, violations = []) {
  let message = `Write the script named "${name}". Topic: ${topic}.`;
  if (violations.length) {
    message += `\n\nThe previous attempt broke these rules, fix them and keep the rest:\n${violations
      .map((v) => `- ${v}`)
      .join("\n")}`;
  }
  return message;
}

export const requestParams = (system, user) => ({
  model: MODEL,
  max_tokens: MAX_TOKENS,
  betas: ["server-side-fallback-2026-07-01"],
  fallbacks: "default",
  thinking: { type: "adaptive" },
  system,
  messages: [{ role: "user", content: user }],
  output_config: {
    effort: "high",
    format: { type: "json_schema", schema: outputSchema },
  },
});

// The model's JSON as a script: nulls dropped, the name set here, then the real schema.
export function readScript(parsed, name, schema = readJSON(SCHEMA_PATH)) {
  if (!parsed || !Array.isArray(parsed.utterances))
    throw new Error("the model's answer has no utterances array");
  const script = {
    name,
    summary: String(parsed.summary ?? "").trim(),
    utterances: parsed.utterances.map((u) => {
      const out = {
        text: String(u.text ?? "").trim(),
        pauseAfter: u.pauseAfter,
      };
      if (u.label != null) out.label = u.label;
      if (u.note != null && String(u.note).trim())
        out.note = String(u.note).trim();
      return out;
    }),
  };
  const errors = validate(script, schema);
  if (errors.length)
    throw new Error(`the script fails the schema:\n  ${errors.join("\n  ")}`);
  return script;
}

const INTERVENTIONS = new Set([
  "clarify",
  "deepen",
  "reflect",
  "decide",
  "summarize",
  "challenge",
]);

// The rules the checked-in corpus tests hold every script to.
export function checkScript(script) {
  const out = [];
  const utterances = script.utterances;
  const speech = utterances.reduce(
    (sum, u) => sum + estimateDuration(u.text),
    0,
  );
  const [minSpeech, maxSpeech] = RULES.speechSeconds;
  if (speech < minSpeech || speech > maxSpeech)
    out.push(
      `speech is ${speech.toFixed(0)} s at 2.6 words a second, it must be ${minSpeech} to ${maxSpeech}`,
    );
  const [minPause, maxPause] = RULES.pauseSeconds;
  utterances.forEach((u, i) => {
    if (u.pauseAfter < minPause || u.pauseAfter > maxPause)
      out.push(
        `utterance ${i} pauses ${u.pauseAfter} s, allowed ${minPause} to ${maxPause}`,
      );
    if (INTERVENTIONS.has(u.label) && u.pauseAfter < RULES.interventionPause)
      out.push(
        `utterance ${i} (${u.label}) pauses ${u.pauseAfter} s, an intervention needs ${RULES.interventionPause}`,
      );
    if (u.label === "leave" && u.pauseAfter < RULES.leavePause)
      out.push(
        `utterance ${i} (leave) pauses ${u.pauseAfter} s, leave needs ${RULES.leavePause}`,
      );
  });
  const closing = utterances
    .map((u, i) => (u.label === "finished" || u.label === "wrapUp" ? i : -1))
    .filter((i) => i >= 0);
  if (closing.length !== 1 || closing[0] !== utterances.length - 1)
    out.push(
      "finished or wrapUp must sit on the last utterance and nowhere else",
    );
  const interventions = utterances.filter((u) =>
    INTERVENTIONS.has(u.label),
  ).length;
  const [minInt, maxInt] = RULES.interventions;
  if (interventions < minInt || interventions > maxInt)
    out.push(
      `${interventions} interventions, the session needs ${minInt} to ${maxInt}`,
    );
  let clock = 0;
  const points = [0];
  for (const u of utterances) {
    clock += estimateDuration(u.text);
    if (u.pauseAfter >= RULES.longPause) points.push(clock);
    clock += u.pauseAfter;
  }
  points.push(clock);
  const widest = Math.max(...points.slice(1).map((p, i) => p - points[i]));
  if (widest > RULES.longPauseEvery)
    out.push(
      `${widest.toFixed(0)} s pass without a pause of ${RULES.longPause} s; one is needed every ${RULES.longPauseEvery} s`,
    );
  if (!/\b(um|uh)\b/i.test(utterances.map((u) => u.text).join(" ")))
    out.push("no um or uh anywhere; the speaker uses fillers");
  return out;
}

const textOf = (message) =>
  message.content
    .filter((block) => block.type === "text")
    .map((block) => block.text ?? "")
    .join("");

// One streamed call; the parsed JSON and what it cost.
export async function askModel(client, system, user) {
  const stream = client.beta.messages.stream(requestParams(system, user));
  const message = await stream.finalMessage();
  if (message.stop_reason === "max_tokens")
    throw new Error(`the answer was cut off at ${MAX_TOKENS} tokens`);
  if (message.stop_reason === "refusal")
    throw new Error(
      `the model refused: ${JSON.stringify(message.stop_details)}`,
    );
  return {
    parsed: JSON.parse(textOf(message)),
    usage: message.usage,
    model: message.model,
  };
}

export const costOf = (usage) =>
  (usage.input_tokens * PRICE.input + usage.output_tokens * PRICE.output) /
  1_000_000;

// Asks until the script passes the rules, at most `attempts` times, feeding the
// violations back each time.
export async function generateScript(
  client,
  system,
  entry,
  { attempts = 3, log } = {},
) {
  let violations = [];
  let usage = { input_tokens: 0, output_tokens: 0 };
  let model;
  for (let attempt = 1; attempt <= attempts; attempt++) {
    const answer = await askModel(
      client,
      system,
      userMessage(entry, violations),
    );
    usage = {
      input_tokens: usage.input_tokens + answer.usage.input_tokens,
      output_tokens: usage.output_tokens + answer.usage.output_tokens,
    };
    model = answer.model;
    const script = readScript(answer.parsed, entry.name);
    violations = checkScript(script);
    if (violations.length === 0)
      return { script, usage, model, attempts: attempt };
    log?.(
      `${entry.name}: attempt ${attempt} broke ${violations.length} rule(s)\n  ${violations.join("\n  ")}`,
    );
  }
  throw new Error(
    `${entry.name}: no script passed the rules in ${attempts} attempts`,
  );
}

export function parseTopics(values, count) {
  if (values.topic?.length) {
    return values.topic.map((spec) => {
      const [name, ...rest] = spec.split(":");
      const topic = rest.join(":").trim();
      if (!name || !topic)
        throw new Error(`--topic takes name:topic, got "${spec}"`);
      return { name: name.trim(), topic };
    });
  }
  if (count > TOPICS.length)
    throw new Error(
      `--count ${count} needs --topic entries beyond the ${TOPICS.length} built in`,
    );
  return TOPICS.slice(0, count);
}

const usage = `usage: node tools/synth/scripts.mjs [--style data/style.json] [--count 6] [--out <dir>] [--topic name:topic ...]
Asks the model for new scripts in the speaker's style, writes <out>/<name>.json for each.`;

export async function main(argv, { client } = {}) {
  const { values } = parseArgs({
    args: argv,
    options: {
      style: { type: "string", default: STYLE_PATH },
      count: { type: "string", default: String(TOPICS.length) },
      out: { type: "string", default: VOICE_SCRIPTS_DIR },
      topic: { type: "string", multiple: true },
      help: { type: "boolean", default: false },
    },
  });
  if (values.help) {
    console.log(usage);
    return 0;
  }
  const topics = parseTopics(values, Number(values.count));
  const style = readJSON(values.style);
  const system = systemPrompt(style);
  if (!client) {
    if (!process.env.ANTHROPIC_API_KEY)
      throw new Error("scripts needs ANTHROPIC_API_KEY in the environment");
    const Anthropic = await loadSDK();
    client = new Anthropic({ maxRetries: 2, timeout: DEADLINE_MS });
  }
  mkdirSync(values.out, { recursive: true });
  let total = { input_tokens: 0, output_tokens: 0 };
  for (const entry of topics) {
    const {
      script,
      usage: used,
      model,
      attempts,
    } = await generateScript(client, system, entry, {
      log: (line) => console.error(line),
    });
    total = {
      input_tokens: total.input_tokens + used.input_tokens,
      output_tokens: total.output_tokens + used.output_tokens,
    };
    const file = join(values.out, `${entry.name}.json`);
    writeFileSync(file, JSON.stringify(script, null, 2) + "\n");
    const words = script.utterances.reduce(
      (n, u) => n + u.text.split(/\s+/).length,
      0,
    );
    console.log(
      `${entry.name}: ${script.utterances.length} utterances, ${words} words, ` +
        `${script.utterances.filter((u) => u.label).length} labels, ${attempts} attempt(s), ${model}`,
    );
    console.log(`wrote ${file}`);
  }
  console.log(
    `${total.input_tokens} in, ${total.output_tokens} out, about $${costOf(total).toFixed(2)}`,
  );
  return 0;
}

if (
  process.argv[1] &&
  realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  main(process.argv.slice(2)).then(
    (code) => process.exit(code),
    (error) => {
      console.error(error.message);
      process.exit(1);
    },
  );
}
