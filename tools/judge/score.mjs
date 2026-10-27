// Scores one variant's lines against the rubric and writes the judge's answers.
//   node tools/judge/score.mjs <variant> [--corpus <file>] [--lines <file>] [--out <file>]
import { join } from "node:path";
import { client, concurrency, textOf, timed, usageOf } from "./api.mjs";
import { dataDir, parseArgs, pool, readJsonl, writeJsonl } from "./io.mjs";
import { judgeRequest, parseJudgement } from "./judge.mjs";

const { flags, words } = parseArgs(process.argv.slice(2));
const [variant] = words;
if (!variant) {
  console.error(
    "usage: score.mjs <variant> [--corpus <file>] [--lines <file>] [--out <file>]",
  );
  process.exit(2);
}

const corpus = new Map(
  readJsonl(flags.corpus ?? join(dataDir, "corpus.jsonl")).map((record) => [
    record.id,
    record,
  ]),
);
const lines = readJsonl(flags.lines ?? join(dataDir, `lines.${variant}.jsonl`));
const anthropic = client();

const scores = await pool(lines, concurrency, async (line) => {
  const record = corpus.get(line.id);
  if (!record) throw new Error(`${line.id} is not in the corpus`);
  const { message, latencyMs } = await timed(() =>
    anthropic.messages.create(judgeRequest(record, line.text)),
  );
  const { scores, note } = parseJudgement(textOf(message.content));
  console.log(`${line.id} ${Object.values(scores).join("")} ${note}`);
  return {
    id: line.id,
    variant,
    scores,
    note,
    judgeLatencyMs: latencyMs,
    judgeUsage: usageOf(message),
  };
});

const out = flags.out ?? join(dataDir, `scores.${variant}.jsonl`);
writeJsonl(out, scores);
console.log(`${scores.length} scores -> ${out}`);
