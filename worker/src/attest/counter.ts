import { DurableObject } from "cloudflare:workers";

const key = "counter";

/**
 * One per key id, holding the last assertion counter it accepted. The object runs one call at
 * a time, so the check and the write that follows it cannot interleave with another request.
 */
export class DeviceCounter extends DurableObject<Env> {
  private async stored(): Promise<number> {
    return (await this.ctx.storage.get<number>(key)) ?? 0;
  }

  /** Accepts `counter` when it moves past the stored value and `floor`; false means a replay. */
  async advance(counter: number, floor = 0): Promise<boolean> {
    if (counter <= Math.max(await this.stored(), floor)) return false;
    await this.ctx.storage.put(key, counter);
    return true;
  }

  /** Lifts the stored value to `floor` when it sits below it. */
  async raise(floor: number): Promise<void> {
    if (floor > (await this.stored())) await this.ctx.storage.put(key, floor);
  }

  current(): Promise<number> {
    return this.stored();
  }
}
