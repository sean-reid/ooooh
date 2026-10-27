import assert from "node:assert/strict";
import { test } from "node:test";
import { parseCsv } from "./csv.mjs";
import {
  baselineMetrics,
  leaveOneSessionOut,
  metrics,
  predict,
  thresholdForRecall,
} from "./evaluate.mjs";
import {
  baselineSpeaks,
  checkColumns,
  featureNames,
  featureVector,
  isLeave,
  isSpeak,
  sessions,
  sincePromptCap,
} from "./features.mjs";
import {
  fitLogistic,
  fitPolicy,
  probability,
  rawWeights,
  scale,
  sigmoid,
  standardize,
} from "./logistic.mjs";
import { fitTable, foldTable, main } from "./policy.mjs";
import { writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// The header `eval --features` writes, pinned on the Swift side by EvalFeaturesTests, and the
// third check of the synthetic decision fixture as it came out of the eval.
const header =
  "fixture,at,pauseLength,speechDensity,awaitingFinishedReply,wordsSoFar,promptsSoFar," +
  "secondsSincePrompt,goodMoment,hangingQuestion,trailsOff,unnamedDecision,contradictsEarlier," +
  "repeatsPoint,momentum,momentumConfidence,articulation,articulationConfidence,seemsFinished," +
  "intervention,interventionConfidence,decision,label,labelKind";
const decisionRow =
  "decision,33.323,0.0,0.9221920763254003,0,70,0,,0.62,0.63,0.08,0.06,0.03,0.12,3.49,0.57," +
  "1.3,0.74,0.04,clarify,0.74,wait,speak,clarify";

/** Rows in the eval's shape with the columns the policy reads set from `fields`. */
const row = (fields) => {
  const values = Object.fromEntries(
    header.split(",").map((name) => [name, ""]),
  );
  return {
    ...values,
    fixture: "s",
    at: "10",
    pauseLength: "0",
    speechDensity: "1",
    promptsSoFar: "0",
    wordsSoFar: "20",
    goodMoment: "0.1",
    momentum: "3",
    articulation: "2",
    seemsFinished: "0.05",
    decision: "wait",
    label: "wait",
    ...fields,
  };
};

const csvOf = (rows) =>
  [
    header,
    ...rows.map((r) =>
      header
        .split(",")
        .map((name) => r[name] ?? "")
        .join(","),
    ),
  ].join("\n") + "\n";

test("the eval's CSV parses into one object per check with every column", () => {
  const parsed = parseCsv(`${header}\n${decisionRow}\n`);
  assert.equal(parsed.columns.length, 24);
  assert.doesNotThrow(() => checkColumns(parsed.columns));
  assert.equal(parsed.rows.length, 1);
  const check = parsed.rows[0];
  assert.equal(check.fixture, "decision");
  assert.equal(check.secondsSincePrompt, "");
  assert.equal(check.labelKind, "clarify");
  assert.ok(isSpeak(check));
  assert.ok(!isLeave(check));
  assert.ok(!baselineSpeaks(check));
  assert.throws(
    () => parseCsv(`${header}\ndecision,1\n`),
    /row 1 has 2 fields/,
  );
  assert.throws(
    () => checkColumns(["fixture", "at"]),
    /lacks columns: pauseLength/,
  );
});

test("the feature vector takes logs, caps seconds since a prompt, and zeroes a missing cue", () => {
  const check = parseCsv(`${header}\n${decisionRow}\n`).rows[0];
  const x = featureVector(check);
  assert.equal(x.length, featureNames.length);
  assert.equal(featureNames.length, 15);
  const at = (name) => x[featureNames.indexOf(name)];
  assert.equal(at("hangingQuestion"), 0.63);
  assert.equal(at("goodMoment"), 0.62);
  assert.equal(at("momentum"), 3.49);
  assert.equal(at("articulation"), 1.3);
  assert.equal(at("logSeconds"), Math.log(34.323));
  assert.equal(at("logSincePrompt"), Math.log(1 + sincePromptCap));
  assert.equal(at("wordsSoFar"), 70);
  const prompted = featureVector(
    row({ secondsSincePrompt: "900", trailsOff: "" }),
  );
  assert.equal(
    prompted[featureNames.indexOf("logSincePrompt")],
    Math.log(1 + sincePromptCap),
  );
  assert.equal(prompted[featureNames.indexOf("trailsOff")], 0);
  assert.equal(
    featureVector(row({ secondsSincePrompt: "40" }))[
      featureNames.indexOf("logSincePrompt")
    ],
    Math.log(41),
  );
});

test("standardising leaves every column at mean 0 and deviation 1", () => {
  const X = [
    [1, 10, 5],
    [3, 20, 5],
    [5, 30, 5],
  ];
  const { means, stds } = standardize(X);
  assert.deepEqual(means, [3, 20, 5]);
  assert.deepEqual(stds, [Math.sqrt(8 / 3), Math.sqrt(200 / 3), 1]);
  const Z = X.map((x) => scale(x, means, stds));
  for (let j = 0; j < 3; j++) {
    const mean = Z.reduce((s, z) => s + z[j], 0) / 3;
    assert.ok(Math.abs(mean) < 1e-12);
  }
  assert.deepEqual(
    Z.map((z) => z[2]),
    [0, 0, 0],
  );
});

/** A fixed-seed generator, so the fit sees the same rows every run. */
const lcg = (seed) => () => {
  seed = (seed * 1664525 + 1013904223) % 2 ** 32;
  return seed / 2 ** 32;
};

test("gradient descent recovers the sign and order of planted weights", () => {
  const random = lcg(7);
  const X = Array.from({ length: 400 }, () => [
    random() * 2 - 1,
    random() * 2 - 1,
    random() * 2 - 1,
  ]);
  const y = X.map((x) =>
    sigmoid(3 * x[0] - 1.5 * x[1] + 0.5) > random() ? 1 : 0,
  );
  const { weights, bias } = fitLogistic(X, y, { lambda: 0.01, steps: 4000 });
  assert.ok(weights[0] > 2 && weights[0] < 4, `w0 ${weights[0]}`);
  assert.ok(weights[1] < -0.8 && weights[1] > -2.5, `w1 ${weights[1]}`);
  assert.ok(Math.abs(weights[2]) < 0.5, `w2 ${weights[2]}`);
  assert.ok(bias > 0 && bias < 1.2, `bias ${bias}`);
  const heavier = fitLogistic(X, y, { lambda: 400, steps: 4000 });
  assert.ok(Math.abs(heavier.weights[0]) < Math.abs(weights[0]));
});

test("the raw weights give the same logit as the standardised ones", () => {
  const random = lcg(3);
  const rows = Array.from({ length: 60 }, (_, i) => {
    const trailsOff = random();
    return row({
      fixture: `s${i % 3}`,
      at: String(10 + i * 7),
      trailsOff: trailsOff.toFixed(2),
      pauseLength: (random() * 5).toFixed(1),
      wordsSoFar: String(20 + i * 9),
      label: trailsOff > 0.5 ? "speak" : "wait",
    });
  });
  const model = fitPolicy(rows, { lambda: 1 });
  const raw = rawWeights(model);
  for (const r of rows.slice(0, 5)) {
    const x = featureVector(r);
    const rawLogit =
      raw.bias + x.reduce((s, v, j) => s + v * raw.weights[j], 0);
    const p = probability(model, r);
    assert.ok(Math.abs(sigmoid(rawLogit) - p) < 1e-9);
  }
  assert.equal(model.names, featureNames);
  assert.ok(model.weights[featureNames.indexOf("trailsOff")] > 1);
});

test("the threshold is the lowest positive still inside the recall", () => {
  const probs = [0.9, 0.8, 0.3, 0.1, 0.7];
  const y = [true, true, true, false, false];
  assert.equal(thresholdForRecall(probs, y, 0.45), 0.8);
  assert.equal(thresholdForRecall(probs, y, 1), 0.3);
  assert.equal(thresholdForRecall(probs, y, 0.1), 0.9);
  assert.equal(thresholdForRecall([0.2], [false], 0.45), 1);
});

test("metrics count hits, misses, and speaks inside a leave window", () => {
  const rows = [
    row({ label: "speak", decision: "prompt:deepen" }),
    row({ label: "speak", decision: "wait" }),
    row({ label: "leave", decision: "prompt:clarify" }),
    row({ label: "wait", decision: "wait" }),
    row({ label: "finished", decision: "askIfFinished" }),
  ];
  const m = metrics([true, false, true, true, false], rows);
  assert.deepEqual(m, {
    n: 5,
    positives: 2,
    speaks: 3,
    tp: 1,
    fp: 2,
    fn: 1,
    intrusions: 1,
    precision: 1 / 3,
    recall: 0.5,
  });
  const b = baselineMetrics(rows);
  assert.equal(b.tp, 1);
  assert.equal(b.fp, 1);
  assert.equal(b.intrusions, 1);
  assert.equal(
    metrics([false, false, false, false, false], rows).precision,
    null,
  );
  assert.equal(metrics([false], [row({})]).recall, null);
});

/**
 * Three sessions where a speak moment is exactly trailsOff above 0.7, nothing sits between 0.5
 * and 0.7, and the governor fires on every seventh check, which is always a leave or a wait.
 */
const planted = () => {
  const random = lcg(11);
  const rows = [];
  for (const session of ["a", "b", "c"]) {
    for (let i = 0; i < 30; i++) {
      const draw = random();
      const trailsOff =
        draw < 0.6 ? draw * (0.5 / 0.6) : 0.7 + (draw - 0.6) * (0.3 / 0.4);
      rows.push(
        row({
          fixture: session,
          at: String(5 + i * 6),
          trailsOff: trailsOff.toFixed(3),
          hangingQuestion: random().toFixed(3),
          wordsSoFar: String(10 + i * 8),
          label: trailsOff > 0.7 ? "speak" : i % 7 === 0 ? "leave" : "wait",
          decision: i % 7 === 0 && trailsOff <= 0.7 ? "prompt:deepen" : "wait",
        }),
      );
    }
  }
  return rows;
};

test("leave one session out fits on the rest and scores only the held-out session", () => {
  const rows = planted();
  assert.deepEqual(sessions(rows), ["a", "b", "c"]);
  const result = leaveOneSessionOut(rows, { recall: 0.45, lambda: 0.1 });
  assert.equal(result.folds.length, 3);
  for (const fold of result.folds) {
    assert.equal(fold.policy.n, 30);
    assert.equal(fold.policy.n, fold.baseline.n);
    assert.ok(fold.threshold > 0 && fold.threshold < 1);
    assert.ok(
      fold.policy.recall > 0,
      `${fold.session} recall ${fold.policy.recall}`,
    );
    assert.equal(fold.policy.fp, 0, `${fold.session} fp ${fold.policy.fp}`);
    assert.equal(fold.policy.intrusions, 0);
    assert.equal(fold.baseline.tp, 0);
    assert.ok(fold.baseline.intrusions > 0);
  }
  const pooled = result.pooled;
  assert.equal(pooled.policy.n, 90);
  assert.equal(
    pooled.policy.tp,
    result.folds.reduce((s, f) => s + f.policy.tp, 0),
  );
  assert.equal(pooled.baseline.speaks, rows.filter(baselineSpeaks).length);
  assert.ok(pooled.baseline.speaks > 0);
  assert.equal(pooled.policy.precision, 1);
});

test("predict applies the training threshold to new rows", () => {
  const rows = planted();
  const train = rows.filter((r) => r.fixture !== "c");
  const model = fitPolicy(train, { lambda: 0.1 });
  const { threshold, predicted } = predict(model, train, train, 1);
  const onTrain = metrics(predicted, train);
  assert.equal(onTrain.recall, 1);
  assert.equal(onTrain.fp, 0);
  const test = rows.filter((r) => r.fixture === "c");
  const held = metrics(predict(model, train, test, 1).predicted, test);
  assert.equal(held.recall, 1);
  assert.equal(held.fp, 0);
  assert.ok(threshold > 0 && threshold < 1);
});

test("the CLI prints weights by size and a fold table with a pooled line", () => {
  const rows = planted();
  const path = join(tmpdir(), `policy-${process.pid}.csv`);
  writeFileSync(path, csvOf(rows));
  const fit = main(["fit", path, "--lambda", "0.1"]);
  assert.match(fit, /^90 checks over 3 sessions, lambda 0.1\n/);
  const lines = fit.split("\n");
  assert.equal(lines[2], "| feature | weight (standardised) | weight (raw) |");
  assert.match(lines[4], /^\| trailsOff \| /);
  assert.match(fit, /\| bias \| /);
  assert.match(fit, /\| in-sample governor \| 90 \| /);
  assert.match(fit, /\| in-sample policy at 0\.\d+ \| 90 \| /);
  const evaluated = main(["evaluate", path, "--lambda", "0.1"]);
  const table = evaluated.split("\n").slice(2);
  assert.equal(table.length, 6);
  assert.match(
    table[0],
    /^\| held out \| checks \| speak rows \| governor tp\/fp \|/,
  );
  assert.match(table[2], /^\| a \| 30 \| /);
  assert.match(table[5], /^\| pooled \| 90 \| /);
  assert.equal(
    fitTable(fitPolicy(rows)).split("\n").length,
    featureNames.length + 3,
  );
  assert.equal(foldTable(leaveOneSessionOut(rows)).split("\n").length, 6);
});
