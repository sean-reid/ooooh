// Runs one variant over the corpus and records each line with its latency and tokens.
//   node tools/judge/phrase.mjs <variant> [--corpus <file>] [--out <file>]
import { join } from "node:path";
import { client, concurrency, textOf, timed, usageOf } from "./api.mjs";
import { dataDir, parseArgs, pool, readJsonl, writeJsonl } from "./io.mjs";
import { phraseRequest, variantNames } from "./variants.mjs";

const { flags, words } = parseArgs(process.argv.slice(2));
const [variant] = words;
if (!variantNames.includes(variant)) {
  console.error(
    `usage: phrase.mjs <${variantNames.join("|")}> [--corpus <file>] [--out <file>]`,
  );
  process.exit(2);
}

const corpus = readJsonl(flags.corpus ?? join(dataDir, "corpus.jsonl"));
const anthropic = client();

const lines = await pool(corpus, concurrency, async (record) => {
  const { message, latencyMs } = await timed(() =>
    anthropic.beta.messages.create(phraseRequest(variant, record)),
  );
  const text = textOf(message.content).trim();
  console.log(`${record.id} ${latencyMs}ms ${text}`);
  return {
    id: record.id,
    kind: record.kind,
    variant,
    text,
    model: message.model,
    latencyMs,
    usage: usageOf(message),
  };
});

const out = flags.out ?? join(dataDir, `lines.${variant}.jsonl`);
writeJsonl(out, lines);
console.log(`${lines.length} lines -> ${out}`);
