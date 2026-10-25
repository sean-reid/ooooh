import { existsSync, readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const workerDir = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
const devVars = resolve(workerDir, ".dev.vars");

// The vars block of wrangler.jsonc, so node tests see the same defaults as a deployment.
export const vars: Pick<Env, "ELEVENLABS_VOICE_ID"> = JSON.parse(
  readFileSync(resolve(workerDir, "wrangler.jsonc"), "utf8")
    .replace(/^\s*\/\/.*$/gm, "")
    .replace(/,(\s*[}\]])/g, "$1"),
).vars;

// A secret from the environment or .dev.vars, never printed.
export const secret = (name: string): string | undefined => {
  if (process.env[name]) return process.env[name];
  if (!existsSync(devVars)) return undefined;
  const line = readFileSync(devVars, "utf8")
    .split("\n")
    .find((l) => l.startsWith(`${name}=`));
  return (
    line
      ?.slice(name.length + 1)
      .trim()
      .replace(/^"|"$/g, "") || undefined
  );
};
