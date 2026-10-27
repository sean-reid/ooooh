// Prints the per-variant table from the lines and scores under data/, or under --dir.
//   node tools/judge/report.mjs [--dir <dir>] [name ...]
import { existsSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { dataDir, parseArgs, readJsonl } from "./io.mjs";
import { criterionNames, judgeModel } from "./judge.mjs";
import { hardRules } from "./rules.mjs";

/** Dollars per million tokens. Cache writes cost 1.25 times input; reads are a flat 0.20 on both families. */
export const prices = {
  "claude-sonnet-5-5": {
    input: 2,
    output: 10,
    cacheRead: 0.2,
    cacheWrite: 2.5,
  },
  "claude-opus-5-5": { input: 4, output: 20, cacheRead: 0.2, cacheWrite: 5 },
  "claude-opus-4-8": { input: 5, output: 25, cacheRead: 0.5, cacheWrite: 6.25 },
};

export const cost = (model, usage) => {
  const price = prices[model];
  if (!price) throw new Error(`no price for ${model}`);
  return (
    (usage.input * price.input +
      usage.output * price.output +
      (usage.cacheRead ?? 0) * price.cacheRead +
      (usage.cacheWrite ?? 0) * price.cacheWrite) /
    1e6
  );
};

const mean = (values) =>
  values.length ? values.reduce((sum, v) => sum + v, 0) / values.length : null;

/** Nearest rank: p50 of [1, 2, 3, 4] is 2, p90 of ten values is the ninth. */
export const percentile = (values, p) => {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil((p / 100) * sorted.length) - 1)];
};

const distribution = (values) =>
  [1, 2, 3, 4, 5].map((v) => values.filter((x) => x === v).length);

export const summarize = (variant, lines, scores = []) => {
  const byId = new Map(scores.map((s) => [s.id, s]));
  const scored = lines.map((line) => byId.get(line.id)).filter(Boolean);
  const perCriterion = Object.fromEntries(
    criterionNames.map((name) => {
      const values = scored.map((s) => s.scores[name]);
      return [name, { mean: mean(values), distribution: distribution(values) }];
    }),
  );
  const latencies = lines.map((line) => line.latencyMs);
  return {
    variant,
    lines: lines.length,
    scored: scored.length,
    hardPass: lines.filter((line) => hardRules(line.text).pass).length,
    criteria: perCriterion,
    overall: mean(
      scored.flatMap((s) => criterionNames.map((name) => s.scores[name])),
    ),
    p50: percentile(latencies, 50),
    p90: percentile(latencies, 90),
    cost: lines.reduce((sum, line) => sum + cost(line.model, line.usage), 0),
    judgeCost: scored.reduce(
      (sum, s) => sum + cost(judgeModel, s.judgeUsage),
      0,
    ),
  };
};

const num = (value, digits = 2) =>
  value === null ? "-" : value.toFixed(digits);
const dollars = (value) => `$${value.toFixed(3)}`;
const row = (cells) => `| ${cells.join(" | ")} |`;

export const table = (summaries) => {
  const head = [
    "variant",
    "lines",
    "hard rules",
    ...criterionNames,
    "overall",
    "p50 ms",
    "p90 ms",
    "cost",
  ];
  const out = [row(head), row(head.map(() => "---"))];
  for (const s of summaries) {
    out.push(
      row([
        s.variant,
        s.lines,
        `${s.hardPass}/${s.lines}`,
        ...criterionNames.map((name) => num(s.criteria[name].mean)),
        num(s.overall),
        s.p50 ?? "-",
        s.p90 ?? "-",
        dollars(s.cost),
      ]),
    );
  }
  out.push(
    "",
    row(["variant", "criterion", "1", "2", "3", "4", "5"]),
    row(Array(7).fill("---")),
  );
  for (const s of summaries) {
    for (const name of criterionNames) {
      out.push(row([s.variant, name, ...s.criteria[name].distribution]));
    }
  }
  const judgeSpend = summaries.reduce((sum, s) => sum + s.judgeCost, 0);
  const scored = summaries.reduce((sum, s) => sum + s.scored, 0);
  out.push(
    "",
    `Judge: ${scored} lines scored by ${judgeModel} for ${dollars(judgeSpend)}.`,
  );
  return out.join("\n");
};

export const namesOnDisk = (dir) =>
  readdirSync(dir)
    .map((name) => name.match(/^lines\.(.+)\.jsonl$/)?.[1])
    .filter(Boolean)
    .sort();

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const { flags, words } = parseArgs(process.argv.slice(2));
  const dir = flags.dir ?? dataDir;
  const names = words.length ? words : namesOnDisk(dir);
  const summaries = names.map((name) => {
    const scoresFile = join(dir, `scores.${name}.jsonl`);
    return summarize(
      name,
      readJsonl(join(dir, `lines.${name}.jsonl`)),
      existsSync(scoresFile) ? readJsonl(scoresFile) : [],
    );
  });
  console.log(table(summaries));
}
