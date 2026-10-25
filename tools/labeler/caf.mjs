// Core Audio Format: a "caff" header, then chunks of a 4 byte type, a big
// endian int64 size, and the payload. The recorder writes linear PCM only.
const IS_FLOAT = 1;
const IS_LITTLE_ENDIAN = 2;

const fourCC = (bytes, offset) =>
  String.fromCharCode(...bytes.subarray(offset, offset + 4));

function readDesc(view, bytes, offset) {
  return {
    sampleRate: view.getFloat64(offset),
    formatID: fourCC(bytes, offset + 8),
    formatFlags: view.getUint32(offset + 12),
    bytesPerPacket: view.getUint32(offset + 16),
    framesPerPacket: view.getUint32(offset + 20),
    channelsPerFrame: view.getUint32(offset + 24),
    bitsPerChannel: view.getUint32(offset + 28),
  };
}

function sampleReader(view, desc) {
  const isFloat = (desc.formatFlags & IS_FLOAT) !== 0;
  const little = (desc.formatFlags & IS_LITTLE_ENDIAN) !== 0;
  const key = `${isFloat ? "f" : "i"}${desc.bitsPerChannel}`;
  switch (key) {
    case "f32":
      return (o) => view.getFloat32(o, little);
    case "f64":
      return (o) => view.getFloat64(o, little);
    case "i16":
      return (o) => view.getInt16(o, little) / 32768;
    case "i32":
      return (o) => view.getInt32(o, little) / 2147483648;
    default:
      throw new Error(
        `CAF sample format ${isFloat ? "float" : "int"}${desc.bitsPerChannel} is not supported`,
      );
  }
}

// Returns { sampleRate, channels }, channels being one Float32Array each.
export function parseCAF(buffer) {
  const bytes = new Uint8Array(buffer);
  const view = new DataView(buffer);
  if (bytes.length < 8 || fourCC(bytes, 0) !== "caff")
    throw new Error("not a CAF file");
  const version = view.getUint16(4);
  if (version !== 1) throw new Error(`CAF version ${version} is not supported`);

  let desc = null;
  let data = null;
  let offset = 8;
  while (offset + 12 <= bytes.length) {
    const type = fourCC(bytes, offset);
    const size = view.getBigInt64(offset + 4);
    const start = offset + 12;
    const length =
      size === -1n
        ? bytes.length - start
        : Math.min(Number(size), bytes.length - start);
    if (type === "desc") desc = readDesc(view, bytes, start);
    if (type === "data") data = { start: start + 4, length: length - 4 };
    offset = start + length;
  }
  if (!desc) throw new Error("CAF has no desc chunk");
  if (!data) throw new Error("CAF has no data chunk");
  if (desc.formatID !== "lpcm")
    throw new Error(`CAF holds ${desc.formatID.trim()}, not linear PCM`);

  const read = sampleReader(view, desc);
  const channelCount = desc.channelsPerFrame;
  const bytesPerSample = desc.bitsPerChannel / 8;
  const frames = Math.floor(data.length / desc.bytesPerPacket);
  const channels = Array.from(
    { length: channelCount },
    () => new Float32Array(frames),
  );
  for (let frame = 0; frame < frames; frame++) {
    const base = data.start + frame * desc.bytesPerPacket;
    for (let channel = 0; channel < channelCount; channel++) {
      channels[channel][frame] = read(base + channel * bytesPerSample);
    }
  }
  return { sampleRate: desc.sampleRate, channels };
}
