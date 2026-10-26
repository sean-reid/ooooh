import { DurableObject } from "cloudflare:workers";

const key = "counter";

/**
 * One per key id, holding the last assertion counter it accepted. The storage calls are
 * synchronous, so a check and the write behind it run with nothing in between.
 */
export class DeviceCounter extends DurableObject<Env> {
  private stored(): number {
    return this.ctx.storage.kv.get<number>(key) ?? 0;
  }

  /** Accepts `counter` when it moves past the stored value and `floor`; false means a replay. */
  advance(counter: number, floor = 0): boolean {
    if (counter <= Math.max(this.stored(), floor)) return false;
    this.ctx.storage.kv.put(key, counter);
    return true;
  }

  /** Lifts the stored value to `floor` when it sits below it. */
  raise(floor: number): void {
    if (floor > this.stored()) this.ctx.storage.kv.put(key, floor);
  }

  current(): number {
    return this.stored();
  }
}
