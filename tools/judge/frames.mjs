// Counts, per variant, the lines that share a stock frame and the lines that name a word from the last two utterances.
//   node tools/judge/frames.mjs [--dir <dir>] [--corpus <file>] [--show] [name ...]
// --show prints the lines under each count; leave it off over private recordings.
import { join } from "node:path";
import { dataDir, parseArgs, readJsonl } from "./io.mjs";
import { namesOnDisk } from "./report.mjs";

/** The shapes the owner heard again and again; each is one regex over the whole line. */
export const frames = {
  "how does X sit": /\bhow does\b.{0,40}?\bsit\b/i,
  "what makes X": /\bwhat makes\b/i,
  "why does X matter":
    /\b(why|does|do|did|would|should)\b.{0,40}?\bmatters?\b|\bwhy (is|are|was|were)\b.{0,40}?\bimportant\b|\bwhy\b.{0,40}?\bcounts?\b|\bso what\b/i,
  "which part of X": /\bwhich (part|piece|bit) of\b/i,
  "is it X or Y": /\bis it\b.{1,40}?\bor\b/i,
};

export const frameNames = Object.keys(frames);

export const frameOf = (text) =>
  frameNames.find((name) => frames[name].test(text)) ?? null;

const stopwords = new Set(
  "that this with what which there their they them then than from have been were just like about into over also some more very really think know going want need maybe because would could should kind sort thing things something anything right yeah okay actually probably".split(
    " ",
  ),
);

/** Lowercased words of four letters or more that carry content, in order of appearance. */
export const contentWords = (text) =>
  [...new Set(text.toLowerCase().match(/[a-z']{4,}/g) ?? [])].filter(
    (word) => !stopwords.has(word),
  );

/** The content words a line shares with the speaker's last two utterances. */
export const namedWords = (text, transcript) => {
  const recent = new Set(
    transcript.slice(-2).flatMap((segment) => contentWords(segment.text)),
  );
  return contentWords(text).filter((word) => recent.has(word));
};

export const tally = (lines, corpus) => {
  const byFrame = Object.fromEntries(frameNames.map((name) => [name, []]));
  const named = [];
  const unnamed = [];
  for (const line of lines) {
    const frame = frameOf(line.text);
    if (frame) byFrame[frame].push(line);
    const record = corpus.get(line.id);
    if (!record) throw new Error(`${line.id} is not in the corpus`);
    (namedWords(line.text, record.transcript).length ? named : unnamed).push(
      line,
    );
  }
  return {
    lines: lines.length,
    framed: Object.values(byFrame).reduce((sum, hits) => sum + hits.length, 0),
    byFrame,
    named,
    unnamed,
  };
};

const show = (label, hits, verbose) => {
  console.log(`  ${label}: ${hits.length}`);
  if (verbose)
    for (const line of hits) console.log(`    ${line.id}  ${line.text}`);
};

if (process.argv[1] === new URL(import.meta.url).pathname) {
  const { flags, words } = parseArgs(process.argv.slice(2));
  const dir = flags.dir ?? dataDir;
  const verbose = flags.show === true;
  const corpus = new Map(
    readJsonl(flags.corpus ?? join(dir, "corpus.jsonl")).map((record) => [
      record.id,
      record,
    ]),
  );
  for (const name of words.length ? words : namesOnDisk(dir)) {
    const counts = tally(readJsonl(join(dir, `lines.${name}.jsonl`)), corpus);
    console.log(
      `${name}: ${counts.lines} lines, ${counts.framed} in a stock frame, ${counts.named.length} name a word from the last two utterances`,
    );
    for (const frame of frameNames) show(frame, counts.byFrame[frame], verbose);
    show("names nothing recent", counts.unnamed, verbose);
  }
}
