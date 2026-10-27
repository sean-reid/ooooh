import { featureNames, featureVector, isSpeak } from "./features.mjs";

export const sigmoid = (z) => 1 / (1 + Math.exp(-z));

/** Per-column mean and standard deviation. A column constant to rounding gets a deviation of 1. */
export function standardize(X) {
  const width = X[0].length;
  const means = Array(width).fill(0);
  const stds = Array(width).fill(0);
  for (const x of X) x.forEach((v, i) => (means[i] += v / X.length));
  for (const x of X)
    x.forEach((v, i) => (stds[i] += (v - means[i]) ** 2 / X.length));
  return {
    means,
    stds: stds.map((v, i) => {
      const std = Math.sqrt(v);
      return std > 1e-9 * Math.max(1, Math.abs(means[i])) ? std : 1;
    }),
  };
}

export const scale = (x, means, stds) =>
  x.map((v, i) => (v - means[i]) / stds[i]);

/**
 * Logistic regression by full-batch gradient descent on the mean log loss plus
 * lambda / (2n) times the squared weights. The bias is not penalised.
 */
export function fitLogistic(
  X,
  y,
  { lambda = 1, rate = 0.1, steps = 5000 } = {},
) {
  const n = X.length;
  const width = X[0].length;
  let weights = Array(width).fill(0);
  let bias = 0;
  for (let step = 0; step < steps; step++) {
    const gradient = Array(width).fill(0);
    let biasGradient = 0;
    for (let i = 0; i < n; i++) {
      const p = sigmoid(
        bias + X[i].reduce((sum, v, j) => sum + v * weights[j], 0),
      );
      const error = (p - y[i]) / n;
      X[i].forEach((v, j) => (gradient[j] += v * error));
      biasGradient += error;
    }
    weights = weights.map(
      (w, j) => w - rate * (gradient[j] + (lambda / n) * w),
    );
    bias -= rate * biasGradient;
  }
  return { weights, bias };
}

/** Fits the speak policy over feature rows and keeps the scaling it was fitted under. */
export function fitPolicy(rows, options = {}) {
  const X = rows.map(featureVector);
  const y = rows.map((row) => (isSpeak(row) ? 1 : 0));
  const { means, stds } = standardize(X);
  const { weights, bias } = fitLogistic(
    X.map((x) => scale(x, means, stds)),
    y,
    options,
  );
  return {
    names: featureNames,
    means,
    stds,
    weights,
    bias,
    lambda: options.lambda ?? 1,
  };
}

export const logit = (model, row) =>
  model.bias +
  scale(featureVector(row), model.means, model.stds).reduce(
    (sum, v, j) => sum + v * model.weights[j],
    0,
  );

export const probability = (model, row) => sigmoid(logit(model, row));

/** The same model over raw features: logit = bias + sum(weight * feature). */
export function rawWeights(model) {
  const weights = model.weights.map((w, j) => w / model.stds[j]);
  const bias =
    model.bias - weights.reduce((sum, w, j) => sum + w * model.means[j], 0);
  return { weights, bias };
}
