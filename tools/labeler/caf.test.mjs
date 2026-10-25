import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";
import { hasTool, tempDir } from "../synth/testing.mjs";
import { wavFromPCM } from "../synth/tts.mjs";
import { parseCAF } from "./caf.mjs";

const hasAfconvert = hasTool("afconvert");

const int16Samples = (count) =>
  Array.from({ length: count }, (_, i) =>
    Math.round(Math.sin(i / 7) * 30000 + (i % 3) * 11),
  );

const float32Samples = (count) =>
  Array.from({ length: count }, (_, i) => Math.fround(Math.sin(i / 5) * 0.9));

function chunk(type, payload) {
  const header = Buffer.alloc(12);
  header.write(type, 0, "ascii");
  header.writeBigInt64BE(BigInt(payload.length), 4);
  return Buffer.concat([header, payload]);
}

function desc({ sampleRate, formatID = "lpcm", flags, channels, bits }) {
  const body = Buffer.alloc(32);
  body.writeDoubleBE(sampleRate, 0);
  body.write(formatID, 8, "ascii");
  body.writeUInt32BE(flags, 12);
  body.writeUInt32BE((bits / 8) * channels, 16);
  body.writeUInt32BE(1, 20);
  body.writeUInt32BE(channels, 24);
  body.writeUInt32BE(bits, 28);
  return body;
}

function pcm(frames, { float, little, bits }) {
  const bytes = bits / 8;
  const flat = frames.flat();
  const body = Buffer.alloc(flat.length * bytes);
  flat.forEach((value, i) => {
    const o = i * bytes;
    if (float && bits === 32)
      little ? body.writeFloatLE(value, o) : body.writeFloatBE(value, o);
    else if (float)
      little ? body.writeDoubleLE(value, o) : body.writeDoubleBE(value, o);
    else if (bits === 16)
      little ? body.writeInt16LE(value, o) : body.writeInt16BE(value, o);
    else little ? body.writeInt32LE(value, o) : body.writeInt32BE(value, o);
  });
  return body;
}

// A complete CAF: magic, desc, an optional free chunk, then data with its
// edit count. `frames` is an array of per-frame arrays, one value per channel.
function makeCAF(
  frames,
  {
    sampleRate = 48000,
    float = false,
    little = true,
    bits = 16,
    free = 0,
    openEnded = false,
  } = {},
) {
  const channels = frames[0].length;
  const flags = (float ? 1 : 0) | (little ? 2 : 0);
  const parts = [
    Buffer.from([0x63, 0x61, 0x66, 0x66, 0, 1, 0, 0]),
    chunk("desc", desc({ sampleRate, flags, channels, bits })),
  ];
  if (free) parts.push(chunk("free", Buffer.alloc(free)));
  const data = Buffer.concat([
    Buffer.alloc(4),
    pcm(frames, { float, little, bits }),
  ]);
  const dataChunk = chunk("data", data);
  if (openEnded) dataChunk.writeBigInt64BE(-1n, 4);
  parts.push(dataChunk);
  const whole = Buffer.concat(parts);
  return whole.buffer.slice(whole.byteOffset, whole.byteOffset + whole.length);
}

test("decodes little endian int16 mono at the mic rate", () => {
  const samples = int16Samples(400);
  const out = parseCAF(
    makeCAF(
      samples.map((s) => [s]),
      { sampleRate: 48000 },
    ),
  );
  assert.equal(out.sampleRate, 48000);
  assert.equal(out.channels.length, 1);
  assert.equal(out.channels[0].length, 400);
  samples.forEach((s, i) =>
    assert.equal(out.channels[0][i], Math.fround(s / 32768)),
  );
});

test("decodes big endian int16, the CAF default when the endian flag is clear", () => {
  const samples = int16Samples(300);
  const out = parseCAF(
    makeCAF(
      samples.map((s) => [s]),
      { little: false, sampleRate: 16000 },
    ),
  );
  assert.equal(out.sampleRate, 16000);
  samples.forEach((s, i) =>
    assert.equal(out.channels[0][i], Math.fround(s / 32768)),
  );
});

test("decodes float32 in both byte orders", () => {
  const samples = float32Samples(500);
  for (const little of [true, false]) {
    const out = parseCAF(
      makeCAF(
        samples.map((s) => [s]),
        { float: true, bits: 32, little, sampleRate: 44100 },
      ),
    );
    assert.equal(out.sampleRate, 44100);
    assert.deepEqual([...out.channels[0]], samples);
  }
});

test("decodes int32 and float64", () => {
  const ints = [0, 1 << 30, -(1 << 30), 2147483647, -2147483648];
  const i32 = parseCAF(
    makeCAF(
      ints.map((s) => [s]),
      { bits: 32 },
    ),
  );
  assert.deepEqual(
    [...i32.channels[0]],
    ints.map((s) => Math.fround(s / 2147483648)),
  );
  const floats = [0.25, -0.5, 0.125];
  const f64 = parseCAF(
    makeCAF(
      floats.map((s) => [s]),
      { float: true, bits: 64 },
    ),
  );
  assert.deepEqual([...f64.channels[0]], floats);
});

test("splits interleaved stereo into two channels and skips unknown chunks", () => {
  const frames = Array.from({ length: 250 }, (_, i) => [
    i * 100,
    500 - i * 100,
  ]);
  const out = parseCAF(makeCAF(frames, { free: 37 }));
  assert.equal(out.channels.length, 2);
  frames.forEach(([l, r], i) => {
    assert.equal(out.channels[0][i], Math.fround(l / 32768));
    assert.equal(out.channels[1][i], Math.fround(r / 32768));
  });
});

test("a data chunk sized -1 runs to the end of the file", () => {
  const samples = int16Samples(333);
  const out = parseCAF(
    makeCAF(
      samples.map((s) => [s]),
      { openEnded: true },
    ),
  );
  assert.equal(out.channels[0].length, 333);
  assert.equal(out.channels[0][332], Math.fround(samples[332] / 32768));
});

test("rejects files that are not linear PCM CAF", () => {
  assert.throws(
    () => parseCAF(new Uint8Array([1, 2, 3]).buffer),
    /not a CAF file/,
  );
  const aac = makeCAF([[0]]);
  Buffer.from(aac).write("aac ", 8 + 12 + 8, "ascii");
  assert.throws(() => parseCAF(aac), /holds aac, not linear PCM/);
  const packed = makeCAF([[0], [0], [0]]);
  new DataView(packed).setUint32(8 + 12 + 16, 3);
  new DataView(packed).setUint32(8 + 12 + 28, 24);
  assert.throws(() => parseCAF(packed), /int24 is not supported/);
});

test("decodes CAF files written by afconvert", { skip: !hasAfconvert }, (t) => {
  const dir = tempDir(t);
  const samples = int16Samples(1000);
  const wav = join(dir, "in.wav");
  const raw = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => raw.writeInt16LE(s, i * 2));
  writeFileSync(wav, wavFromPCM(raw, 16000));
  for (const format of ["LEI16", "BEI16", "LEF32"]) {
    const caf = join(dir, `${format}.caf`);
    execFileSync("afconvert", ["-f", "caff", "-d", format, wav, caf], {
      stdio: "ignore",
    });
    const buf = readFileSync(caf);
    const out = parseCAF(
      buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.length),
    );
    assert.equal(out.sampleRate, 16000, format);
    assert.equal(out.channels.length, 1, format);
    assert.equal(out.channels[0].length, 1000, format);
    samples.forEach((s, i) =>
      assert.equal(
        out.channels[0][i],
        Math.fround(s / 32768),
        `${format} sample ${i}`,
      ),
    );
  }
});
