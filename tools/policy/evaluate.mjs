import { baselineSpeaks, isLeave, isSpeak, sessions } from "./features.mjs";
import { fitPolicy, probability } from "./logistic.mjs";

/** The highest probability that still catches `recall` of the positives, 1 when there are none. */
export function thresholdForRecall(probs, y, recall) {
  const positives = probs.filter((_, i) => y[i]).sort((a, b) => b - a);
  if (!positives.length) return 1;
  return positives[Math.ceil(recall * positives.length) - 1];
}

/** Counts over checks: a speak on a speak-labeled row is a hit, on a leave row an intrusion. */
export function metrics(predicted, rows) {
  const out = {
    n: rows.length,
    positives: 0,
    speaks: 0,
    tp: 0,
    fp: 0,
    fn: 0,
    intrusions: 0,
  };
  rows.forEach((row, i) => {
    const speak = predicted[i];
    const labeled = isSpeak(row);
    if (labeled) out.positives++;
    if (speak) out.speaks++;
    if (speak && labeled) out.tp++;
    if (speak && !labeled) out.fp++;
    if (!speak && labeled) out.fn++;
    if (speak && isLeave(row)) out.intrusions++;
  });
  out.precision = out.speaks ? out.tp / out.speaks : null;
  out.recall = out.positives ? out.tp / out.positives : null;
  return out;
}

export const baselineMetrics = (rows) =>
  metrics(rows.map(baselineSpeaks), rows);

/** Predictions for `rows` from a model and the threshold that reached `recall` on `train`. */
export function predict(model, train, rows, recall) {
  const threshold = thresholdForRecall(
    train.map((row) => probability(model, row)),
    train.map(isSpeak),
    recall,
  );
  return {
    threshold,
    predicted: rows.map((row) => probability(model, row) >= threshold),
  };
}

/**
 * Leave one session out: fit on the rest, pick the threshold on the training rows, score the
 * held-out session. Pooled numbers are over every held-out prediction together.
 */
export function leaveOneSessionOut(
  rows,
  { recall = 0.45, ...fitOptions } = {},
) {
  const heldRows = [];
  const heldPredictions = [];
  const folds = sessions(rows).map((session) => {
    const train = rows.filter((row) => row.fixture !== session);
    const test = rows.filter((row) => row.fixture === session);
    const model = fitPolicy(train, fitOptions);
    const { threshold, predicted } = predict(model, train, test, recall);
    const onTrain = metrics(
      predict(model, train, train, recall).predicted,
      train,
    );
    heldRows.push(...test);
    heldPredictions.push(...predicted);
    return {
      session,
      threshold,
      trainPrecision: onTrain.precision,
      policy: metrics(predicted, test),
      baseline: baselineMetrics(test),
    };
  });
  return {
    folds,
    pooled: {
      policy: metrics(heldPredictions, heldRows),
      baseline: baselineMetrics(heldRows),
    },
  };
}
