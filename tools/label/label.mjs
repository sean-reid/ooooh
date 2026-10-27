#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, resolve } from "node:path";
import { parseArgs } from "node:util";
import {
  buildLabels,
  countByKind,
  finalSegments,
  fixtureBaseName,
} from "../labeler/labels.mjs";
import { buildProposed, readProposal } from "./proposal.mjs";
import { parseReview, renderReview } from "./review.mjs";

const usage = `usage:
  label.mjs propose <fixture.json> [--out <dir>]   ask the model, write <name>.labels.proposed.json and <name>.review.md
  label.mjs review <fixture.json> [--out <dir>]    rewrite <name>.review.md from <name>.labels.proposed.json
  label.mjs fold <review.md>                       write <name>.labels.json from the edited review
Files land beside the fixture unless --out names a directory.`;

const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));
const writeJSON = (file, value) =>
  writeFileSync(file, JSON.stringify(value, null, 2) + "\n");

const fail = (message) => {
  process.stderr.write(`${message}\n`);
  process.exit(2);
};

const counts = (labels) =>
  countByKind(labels)
    .map(([kind, count]) => `${kind} ${count}`)
    .join(", ") || "none";

function fixturePaths(fixturePath, outDir) {
  const fixtureFile = resolve(fixturePath);
  const name = fixtureBaseName(basename(fixtureFile));
  const dir = resolve(outDir ?? dirname(fixtureFile));
  mkdirSync(dir, { recursive: true });
  return {
    fixtureFile,
    name,
    proposedFile: join(dir, `${name}.labels.proposed.json`),
    reviewFile: join(dir, `${name}.review.md`),
  };
}

function writeReview(paths, finals, labels) {
  const review = renderReview({
    name: paths.name,
    fixtureFile: relative(dirname(paths.reviewFile), paths.fixtureFile),
    reviewFile: relative(process.cwd(), paths.reviewFile),
    finals,
    labels,
  });
  writeFileSync(paths.reviewFile, review);
}

export async function propose(fixturePath, outDir) {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) fail("propose needs ANTHROPIC_API_KEY in the environment");
  const paths = fixturePaths(fixturePath, outDir);
  const finals = finalSegments(readJSON(paths.fixtureFile));
  const { askModel } = await import("./model.mjs");
  const { parsed, usage, model } = await askModel(finals, apiKey);
  const proposal = readProposal(parsed, finals);
  const proposed = buildProposed(paths.name, finals, proposal);
  writeJSON(paths.proposedFile, proposed);
  writeReview(paths, finals, proposed.labels);
  const kinds = counts(new Map(proposal.map((p) => [p.utterance, p.kind])));
  console.log(
    `${model}: ${proposal.length} labels over ${finals.length} utterances (${kinds}), ` +
      `${usage.input_tokens} in, ${usage.output_tokens} out`,
  );
  console.log(`wrote ${paths.proposedFile}\nwrote ${paths.reviewFile}`);
}

export function review(fixturePath, outDir) {
  const paths = fixturePaths(fixturePath, outDir);
  const finals = finalSegments(readJSON(paths.fixtureFile));
  const proposed = readJSON(paths.proposedFile);
  writeReview(paths, finals, proposed.labels);
  console.log(`wrote ${paths.reviewFile}`);
}

export function fold(reviewPath) {
  const reviewFile = resolve(reviewPath);
  const { fixtureFile, labels } = parseReview(readFileSync(reviewFile, "utf8"));
  const fixturePath = resolve(dirname(reviewFile), fixtureFile);
  const finals = finalSegments(readJSON(fixturePath));
  for (const utterance of labels.keys()) {
    if (utterance >= finals.length)
      throw new Error(
        `utterance ${utterance} is past the fixture's ${finals.length}`,
      );
  }
  const name = fixtureBaseName(basename(fixturePath));
  const out = join(dirname(reviewFile), `${name}.labels.json`);
  writeJSON(out, buildLabels(name, finals, labels));
  console.log(`${labels.size} labels (${counts(labels)})\nwrote ${out}`);
  return out;
}

async function main(argv) {
  const { positionals, values } = parseArgs({
    args: argv,
    options: { out: { type: "string" } },
    allowPositionals: true,
  });
  const [command, file] = positionals;
  if (!file) fail(usage);
  try {
    if (command === "propose") await propose(file, values.out);
    else if (command === "review") review(file, values.out);
    else if (command === "fold") fold(file);
    else fail(usage);
  } catch (error) {
    fail(error.message);
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === new URL(import.meta.url).pathname
)
  main(process.argv.slice(2));
