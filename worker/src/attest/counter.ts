import { DurableObject } from "cloudflare:workers";

const counterKey = "counter";
const rateKey = "rate";

type Rate = { minute: number; count: number };

/**
 * One per key id, holding the last assertion counter it accepted and its requests this minute.
 * The storage calls are synchronous, so a check and the write behind it run with nothing in
 * between.
 */
export class DeviceCounter extends DurableObject<Env> {
  private stored(): number {
    return this.ctx.storage.kv.get<number>(counterKey) ?? 0;
  }

  /** Accepts `counter` when it moves past the stored value and `floor`; false means a replay. */
  advance(counter: number, floor = 0): boolean {
    if (counter <= Math.max(this.stored(), floor)) return false;
    this.ctx.storage.kv.put(counterKey, counter);
    return true;
  }

  /** Lifts the stored value to `floor` when it sits below it. */
  raise(floor: number): void {
    if (floor > this.stored()) this.ctx.storage.kv.put(counterKey, floor);
  }

  current(): number {
    return this.stored();
  }

  /** Counts one request in `minute` and admits it while the minute has fewer than `limit`. */
  hit(minute: number, limit: number): boolean {
    const rate = this.ctx.storage.kv.get<Rate>(rateKey);
    const count = rate?.minute === minute ? rate.count : 0;
    if (count >= limit) return false;
    this.ctx.storage.kv.put(rateKey, { minute, count: count + 1 });
    return true;
  }
}
