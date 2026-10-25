// Enough of RFC 8949 to read an App Attest attestation or assertion: definite lengths only.
export type Bytes = Uint8Array<ArrayBuffer>;
export type Cbor = number | Bytes | string | boolean | null | Cbor[] | Map<Cbor, Cbor>;

export class CborError extends Error {}

export function decodeCbor(bytes: Bytes): Cbor {
  const reader = new Reader(bytes);
  const value = reader.item();
  if (reader.offset !== bytes.length) throw new CborError("trailing bytes");
  return value;
}

class Reader {
  offset = 0;
  constructor(private bytes: Bytes) {}

  item(): Cbor {
    const initial = this.byte();
    const major = initial >> 5;
    const length = this.length(initial & 0x1f);
    switch (major) {
      case 0:
        return length;
      case 1:
        return -1 - length;
      case 2:
        return this.take(length);
      case 3:
        return new TextDecoder("utf-8", { fatal: true }).decode(this.take(length));
      case 4: {
        const items: Cbor[] = [];
        for (let i = 0; i < length; i++) items.push(this.item());
        return items;
      }
      case 5: {
        const map = new Map<Cbor, Cbor>();
        for (let i = 0; i < length; i++) {
          const key = this.item();
          map.set(key, this.item());
        }
        return map;
      }
      case 7:
        if (length === 20) return false;
        if (length === 21) return true;
        if (length === 22) return null;
        throw new CborError(`unsupported simple value ${length}`);
      default:
        throw new CborError(`unsupported major type ${major}`);
    }
  }

  private length(info: number): number {
    if (info < 24) return info;
    if (info === 24) return this.byte();
    if (info === 25) return (this.byte() << 8) | this.byte();
    if (info === 26) return this.uint(4);
    if (info === 27) return this.uint(8);
    throw new CborError("indefinite length");
  }

  private uint(size: number): number {
    let value = 0;
    for (let i = 0; i < size; i++) value = value * 256 + this.byte();
    if (!Number.isSafeInteger(value)) throw new CborError("integer too large");
    return value;
  }

  private byte(): number {
    if (this.offset >= this.bytes.length) throw new CborError("truncated");
    return this.bytes[this.offset++];
  }

  private take(length: number): Bytes {
    if (this.offset + length > this.bytes.length) throw new CborError("truncated");
    const slice = this.bytes.subarray(this.offset, this.offset + length);
    this.offset += length;
    return slice;
  }
}

export const field = <T extends Cbor>(
  map: Cbor,
  key: string,
  check: (v: Cbor) => v is T,
  what: string,
): T => {
  const value = map instanceof Map ? map.get(key) : undefined;
  if (value === undefined || !check(value)) throw new CborError(`${key}: expected ${what}`);
  return value;
};

export const isBytes = (v: Cbor): v is Bytes => v instanceof Uint8Array;
export const isText = (v: Cbor): v is string => typeof v === "string";
export const isList = (v: Cbor): v is Cbor[] => Array.isArray(v);
