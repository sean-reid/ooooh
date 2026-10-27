import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

export const dataDir = fileURLToPath(new URL("data/", import.meta.url));
export const fixturesDir = fileURLToPath(
  new URL("../../fixtures/synthetic/estimate/", import.meta.url),
);

export const readJSON = (path) => JSON.parse(readFileSync(path, "utf8"));

export const readJsonl = (path) =>
  readFileSync(path, "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => JSON.parse(line));

export const writeJsonl = (path, records) => {
  mkdirSync(dataDir, { recursive: true });
  writeFileSync(path, records.map((r) => JSON.stringify(r) + "\n").join(""));
};

/** Runs `fn` over `items` with at most `limit` calls in flight, keeping input order. */
export async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  const lane = async () => {
    while (next < items.length) {
      const index = next++;
      out[index] = await fn(items[index], index);
    }
  };
  await Promise.all(
    Array.from({ length: Math.min(limit, items.length) }, lane),
  );
  return out;
}

/** `--name value` pairs and bare words from argv; a flag with no value after it is `true`. */
export const parseArgs = (argv) => {
  const flags = {};
  const words = [];
  for (let i = 0; i < argv.length; i++) {
    if (!argv[i].startsWith("--")) words.push(argv[i]);
    else if (argv[i + 1] === undefined || argv[i + 1].startsWith("--"))
      flags[argv[i].slice(2)] = true;
    else flags[argv[i].slice(2)] = argv[++i];
  }
  return { flags, words };
};
