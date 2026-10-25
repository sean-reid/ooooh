import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { listScripts } from "./synth.mjs";

const here = dirname(fileURLToPath(import.meta.url));
export const SCRIPTS_DIR = resolve(here, "../../fixtures/synthetic/scripts");
export const ESTIMATE_DIR = resolve(here, "../../fixtures/synthetic/estimate");
export const AUDIO_DIR = resolve(here, "../../fixtures/synthetic/audio");

export const readJSON = (file) => JSON.parse(readFileSync(file, "utf8"));

export const scripts = Object.fromEntries(
  listScripts(SCRIPTS_DIR).map((f) => [basename(f, ".json"), readJSON(f)]),
);

export const hasTool = (name) => {
  try {
    execFileSync("which", [name], { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
};

export const tempDir = (t) => {
  const dir = mkdtempSync(join(tmpdir(), "synth-test-"));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
};

export function wavDuration(file) {
  const buf = readFileSync(file);
  assert.equal(buf.toString("ascii", 0, 4), "RIFF");
  const byteRate = buf.readUInt32LE(28);
  let offset = 12;
  while (offset < buf.length) {
    const id = buf.toString("ascii", offset, offset + 4);
    const size = buf.readUInt32LE(offset + 4);
    if (id === "data") return size / byteRate;
    offset += 8 + size + (size % 2);
  }
  throw new Error(`no data chunk in ${file}`);
}

export function afinfoDuration(file) {
  const out = execFileSync("afinfo", [file], { encoding: "utf8" });
  return Number(out.match(/estimated duration: ([\d.]+) sec/)[1]);
}
