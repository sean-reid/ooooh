// Turns the labeled moments in a fixture directory into phrasing inputs, one per line.
//   node tools/judge/corpus.mjs [--fixtures <dir>] [--out <file>]
import { readdirSync } from "node:fs";
import { basename, join } from "node:path";
import { kindGuide } from "../../worker/src/phrasing.ts";
import {
  dataDir,
  fixturesDir,
  parseArgs,
  readJSON,
  writeJsonl,
} from "./io.mjs";

export const interventionKinds = Object.keys(kindGuide);

/** SessionLoop.recentWindow: the finals the phone sends with each phrase request. */
export const recentWindow = 6;

export const emptyState = () => ({
  currentThread: "",
  mainIdeas: [],
  openQuestions: [],
  uncertainties: [],
  decisions: [],
  recentTopics: [],
  mode: "exploring",
});

const segmentOf = ({ text, start, end }) => ({ text, start, end });

/** One record per label whose kind the phrase route accepts; finished, leave, and commands are skipped. */
export const recordsFor = (fixture, labels) => {
  const finals = fixture.segments.filter((s) => s.isFinal !== false);
  return labels.labels
    .filter((label) => interventionKinds.includes(label.kind))
    .map((label) => {
      const upTo = finals.filter((s) => s.end <= label.at);
      return {
        id: `${labels.fixture}:${label.utterance}`,
        fixture: labels.fixture,
        utterance: label.utterance,
        at: label.at,
        kind: label.kind,
        state: emptyState(),
        recent: upTo.slice(-recentWindow).map(segmentOf),
      };
    });
};

export const buildCorpus = (dir) =>
  readdirSync(dir)
    .filter((name) => name.endsWith(".labels.json"))
    .sort()
    .flatMap((name) => {
      const stem = basename(name, ".labels.json");
      return recordsFor(
        readJSON(join(dir, `${stem}.fixture.json`)),
        readJSON(join(dir, name)),
      );
    });

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const { flags } = parseArgs(process.argv.slice(2));
  const records = buildCorpus(flags.fixtures ?? fixturesDir);
  const out = flags.out ?? join(dataDir, "corpus.jsonl");
  writeJsonl(out, records);
  console.log(`${records.length} moments -> ${out}`);
}
