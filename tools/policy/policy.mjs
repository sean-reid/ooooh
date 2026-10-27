#!/usr/bin/env node
// Fits and evaluates the speak policy from the CSV `eval --features` writes.
//   node tools/policy/policy.mjs fit <csv...> [--lambda 1] [--recall 0.45]
//   node tools/policy/policy.mjs evaluate <csv...> [--lambda 1] [--recall 0.45]
import { parseArgs } from "node:util";
import { parseCsv } from "./csv.mjs";
import {
  baselineMetrics,
  leaveOneSessionOut,
  metrics,
  predict,
} from "./evaluate.mjs";
import { checkColumns, sessions } from "./features.mjs";
import { fitPolicy, rawWeights } from "./logistic.mjs";
import { readFileSync } from "node:fs";

const usage = `usage:
  policy.mjs fit <csv...> [--lambda 1] [--recall 0.45]       weights over every row
  policy.mjs evaluate <csv...> [--lambda 1] [--recall 0.45]  leave one session out`;

const fail = (message) => {
  process.stderr.write(`${message}\n`);
  process.exit(2);
};

const rate = (value) => (value == null ? "-" : value.toFixed(2));
const counts = (m) => `${m.tp}/${m.fp}`;

/** A markdown table: header, rule, one row per entry. */
export const table = (header, rows) =>
  [header, header.map(() => "---"), ...rows]
    .map((cells) => `| ${cells.join(" | ")} |`)
    .join("\n");

export function fitTable(model) {
  const raw = rawWeights(model);
  const order = model.names
    .map((name, j) => [name, model.weights[j], raw.weights[j]])
    .sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]));
  const rows = order.map(([name, w, r]) => [name, w.toFixed(3), r.toFixed(4)]);
  rows.push(["bias", model.bias.toFixed(3), raw.bias.toFixed(4)]);
  return table(["feature", "weight (standardised)", "weight (raw)"], rows);
}

export function metricsTable(label, policy, baseline, threshold) {
  return table(
    ["", "checks", "speak rows", "tp/fp", "precision", "recall", "intrusions"],
    [
      [
        `${label} governor`,
        baseline.n,
        baseline.positives,
        counts(baseline),
        rate(baseline.precision),
        rate(baseline.recall),
        baseline.intrusions,
      ],
      [
        `${label} policy at ${threshold.toFixed(3)}`,
        policy.n,
        policy.positives,
        counts(policy),
        rate(policy.precision),
        rate(policy.recall),
        policy.intrusions,
      ],
    ],
  );
}

export function foldTable(result) {
  const header = [
    "held out",
    "checks",
    "speak rows",
    "governor tp/fp",
    "governor p",
    "governor r",
    "governor intr",
    "threshold",
    "policy tp/fp",
    "policy p",
    "policy r",
    "policy intr",
  ];
  const line = (name, threshold, b, p) => [
    name,
    b.n,
    b.positives,
    counts(b),
    rate(b.precision),
    rate(b.recall),
    b.intrusions,
    threshold,
    counts(p),
    rate(p.precision),
    rate(p.recall),
    p.intrusions,
  ];
  const rows = result.folds.map((fold) =>
    line(fold.session, fold.threshold.toFixed(3), fold.baseline, fold.policy),
  );
  rows.push(line("pooled", "-", result.pooled.baseline, result.pooled.policy));
  return table(header, rows);
}

function loadRows(paths) {
  if (!paths.length) fail(usage);
  const rows = [];
  for (const path of paths) {
    const parsed = parseCsv(readFileSync(path, "utf8"));
    checkColumns(parsed.columns);
    rows.push(...parsed.rows);
  }
  return rows;
}

export function main(argv) {
  const { values, positionals } = parseArgs({
    args: argv,
    options: { lambda: { type: "string" }, recall: { type: "string" } },
    allowPositionals: true,
  });
  const [command, ...paths] = positionals;
  const lambda = Number(values.lambda ?? 1);
  const recall = Number(values.recall ?? 0.45);
  if (!(lambda >= 0) || !(recall > 0 && recall <= 1)) fail(usage);
  const rows = loadRows(paths);
  const out = [];
  out.push(
    `${rows.length} checks over ${sessions(rows).length} sessions, lambda ${lambda}`,
  );
  if (command === "fit") {
    const model = fitPolicy(rows, { lambda });
    const { threshold, predicted } = predict(model, rows, rows, recall);
    out.push("", fitTable(model), "");
    out.push(
      metricsTable(
        "in-sample",
        metrics(predicted, rows),
        baselineMetrics(rows),
        threshold,
      ),
    );
  } else if (command === "evaluate") {
    out.push("", foldTable(leaveOneSessionOut(rows, { recall, lambda })));
  } else {
    fail(usage);
  }
  return out.join("\n");
}

if (
  process.argv[1] &&
  import.meta.url === new URL(`file://${process.argv[1]}`).href
) {
  process.stdout.write(main(process.argv.slice(2)) + "\n");
}
