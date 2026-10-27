// Runs one variant over the corpus and records each line with its latency and tokens.
//   node tools/judge/phrase.mjs <variant> [--ref <git ref>] [--name <label>] [--corpus <file>] [--dir <dir>] [--out <file>]
// Moments from one fixture run in order, and each line is given the lines produced before it as `said`.
import { join } from "node:path";
import { saidWindow } from "../../worker/src/phrasing.ts";
import { client, concurrency, textOf, timed, usageOf } from "./api.mjs";
import { dataDir, parseArgs, pool, readJsonl, writeJsonl } from "./io.mjs";
import { loadPrompt, phraseRequest, variantNames } from "./variants.mjs";

const { flags, words } = parseArgs(process.argv.slice(2));
const [variant] = words;
if (!variantNames.includes(variant)) {
  console.error(
    `usage: phrase.mjs <${variantNames.join("|")}> [--ref <git ref>] [--name <label>] [--corpus <file>] [--dir <dir>] [--out <file>]`,
  );
  process.exit(2);
}

const dir = flags.dir ?? dataDir;
const name = flags.name ?? variant;
const corpus = readJsonl(flags.corpus ?? join(dir, "corpus.jsonl"));
const prompt = await loadPrompt(flags.ref);
const anthropic = client();

const byFixture = Map.groupBy(corpus, (record) => record.fixture);

const sessions = await pool(
  [...byFixture.values()],
  concurrency,
  async (records) => {
    const lines = [];
    const said = [];
    for (const record of records) {
      const input = { ...record, said: said.slice(-saidWindow) };
      const { message, latencyMs } = await timed(() =>
        anthropic.beta.messages.create(phraseRequest(variant, input, prompt)),
      );
      const text = textOf(message.content).trim();
      console.log(`${record.id} ${latencyMs}ms ${text}`);
      lines.push({
        id: record.id,
        kind: record.kind,
        variant: name,
        text,
        said: input.said,
        model: message.model,
        latencyMs,
        usage: usageOf(message),
      });
      said.push({ kind: record.kind, text, at: record.at });
    }
    return lines;
  },
);

const lines = sessions.flat();
const out = flags.out ?? join(dir, `lines.${name}.jsonl`);
writeJsonl(out, lines);
console.log(`${lines.length} lines -> ${out}`);
