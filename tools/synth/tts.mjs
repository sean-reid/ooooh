import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { setTimeout as sleep } from "node:timers/promises";

export const SAMPLE_RATE = 22050;
export const ELEVENLABS_MODEL = "eleven_flash_v2_5";

export function listSayVoices() {
  const out = execFileSync("say", ["-v", "?"], { encoding: "utf8" });
  return out
    .split("\n")
    .filter(Boolean)
    .map((line) => line.split(/\s{2,}/)[0].trim());
}

export function pickSayVoice(voices) {
  return voices.find((voice) => /Premium|Enhanced/.test(voice)) ?? "Samantha";
}

export function sayUtterance(text, voice, file) {
  execFileSync(
    "say",
    ["-o", file, `--data-format=LEF32@${SAMPLE_RATE}`, "-v", voice],
    {
      input: text,
    },
  );
  return measureDuration(file);
}

export function measureDuration(file) {
  const out = execFileSync("afinfo", [file], { encoding: "utf8" });
  const match = out.match(/estimated duration: ([\d.]+) sec/);
  if (!match) throw new Error(`afinfo gave no duration for ${file}`);
  return Number(match[1]);
}

export function wavFromPCM(pcm, sampleRate = SAMPLE_RATE) {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0);
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8);
  header.write("fmt ", 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36);
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}

export function elevenLabsClient({
  apiKey = process.env.ELEVENLABS_API_KEY,
  baseURL = process.env.ELEVENLABS_BASE_URL ?? "https://api.elevenlabs.io",
  voice,
  model = ELEVENLABS_MODEL,
  settings,
  sampleRate = SAMPLE_RATE,
  maxAttempts = 6,
  wait = sleep,
} = {}) {
  if (!apiKey) {
    throw new Error(
      "ELEVENLABS_API_KEY is not set; export it or use --tts say or --tts estimate",
    );
  }
  if (!voice) throw new Error("elevenlabs mode needs --voice <voice id>");
  const url = `${baseURL}/v1/text-to-speech/${voice}?output_format=pcm_${sampleRate}`;
  const body = { text: "", model_id: model };
  if (settings) body.voice_settings = settings;

  // Returns 16-bit mono PCM at sampleRate, so the byte count is the duration.
  // 429 and 5xx wait out Retry-After, or double from a second, up to maxAttempts.
  async function speak(text) {
    let backoff = 1;
    for (let attempt = 1; ; attempt += 1) {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "xi-api-key": apiKey,
          "content-type": "application/json",
          accept: "audio/pcm",
        },
        body: JSON.stringify({ ...body, text }),
      });
      const retryable = response.status === 429 || response.status >= 500;
      if (retryable && attempt < maxAttempts) {
        const retryAfter = Number.parseFloat(
          response.headers.get("retry-after"),
        );
        const seconds = Number.isFinite(retryAfter) ? retryAfter : backoff;
        backoff *= 2;
        await wait(seconds * 1000);
        continue;
      }
      if (!response.ok) {
        const body = await response.text();
        throw new Error(
          `ElevenLabs ${response.status} for "${text.slice(0, 40)}": ${body}`,
        );
      }
      const pcm = Buffer.from(await response.arrayBuffer());
      return {
        pcm,
        duration: pcm.length / 2 / sampleRate,
        characters: text.length,
      };
    }
  }

  return { speak, model, sampleRate };
}

export function spliceClips(clips, pauses, outputs) {
  const lines = pauses.map(
    (pause, i) => `aevalsrc=0:d=${pause}:s=${SAMPLE_RATE}:c=mono[s${i}]`,
  );
  const chain = clips.map((_, i) => `[${i}:a][s${i}]`).join("");
  lines.push(
    `${chain}concat=n=${clips.length * 2}:v=0:a=1[out]`,
    "[out]asplit=2[m4a][wav]",
  );
  const work = mkdtempSync(join(tmpdir(), "synth-splice-"));
  try {
    const filter = join(work, "filter.txt");
    writeFileSync(filter, lines.join(";\n") + "\n");
    const args = ["-loglevel", "error", "-y"];
    for (const clip of clips) args.push("-i", clip);
    args.push("-/filter_complex", filter);
    args.push(
      "-map",
      "[m4a]",
      "-c:a",
      "aac",
      "-ar",
      String(SAMPLE_RATE),
      "-ac",
      "1",
      outputs.m4a,
    );
    args.push(
      "-map",
      "[wav]",
      "-c:a",
      "pcm_s16le",
      "-ar",
      "16000",
      "-ac",
      "1",
      outputs.wav,
    );
    execFileSync("ffmpeg", args, { stdio: ["ignore", "ignore", "inherit"] });
  } finally {
    rmSync(work, { recursive: true, force: true });
  }
}
