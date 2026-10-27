import { execFileSync } from "node:child_process";
import { mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { pathToFileURL } from "node:url";
import { models } from "../../worker/src/models.ts";
import * as current from "../../worker/src/phrasing.ts";
import { recentWindow } from "./corpus.mjs";

export const exemplars = current.exemplars;

const promptPath = "worker/src/phrasing.ts";

/** The prompt module at a git ref, so an older commit's prompt runs over the same corpus. */
export async function loadPrompt(ref) {
  if (!ref) return current;
  const source = execFileSync("git", ["show", `${ref}:${promptPath}`], {
    encoding: "utf8",
  });
  const file = join(
    mkdtempSync(join(tmpdir(), "ooooh-prompt-")),
    "phrasing.ts",
  );
  writeFileSync(file, source);
  return import(pathToFileURL(file).href);
}

/** What the phone sent at that prompt's commit: the transcript window once it existed, else the last 6 finals. */
export const recentFor = (prompt, transcript) =>
  prompt.phraseWindow
    ? prompt.phraseWindow(transcript)
    : transcript.slice(-recentWindow);

export const variants = {
  shipping: {
    model: models.phrase,
    system: (prompt) => prompt.phraseSystem,
    effort: current.phraseEffort,
  },
  bare: {
    model: models.phrase,
    system: (prompt) => prompt.phraseRules,
    effort: current.phraseEffort,
  },
  opus: {
    model: "claude-opus-5-5",
    system: (prompt) => prompt.phraseSystem,
    effort: "medium",
    thinking: { type: "adaptive" },
  },
};

export const variantNames = Object.keys(variants);

/** The request the Worker's phrase route sends, with the variant's model, prompt, and effort in place. */
export const phraseRequest = (name, record, prompt = current) => {
  const variant = variants[name];
  if (!variant)
    throw new Error(
      `unknown variant ${name}; one of ${variantNames.join(", ")}`,
    );
  const input = {
    ...record,
    recent: record.recent ?? recentFor(prompt, record.transcript),
    said: record.said ?? [],
  };
  return {
    model: variant.model,
    max_tokens: 1024,
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: variant.system(prompt),
    output_config: { effort: variant.effort },
    ...(variant.thinking ? { thinking: variant.thinking } : {}),
    messages: [{ role: "user", content: prompt.phraseUserMessage(input) }],
  };
};
