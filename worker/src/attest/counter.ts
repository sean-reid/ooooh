import { DurableObject } from "cloudflare:workers";

const counterKey = "counter";
const seenKey = "seen";
const rateKey = "rate";
const countedKey = "session-counted";
const notesKey = "notes-session";
const sessionsPrefix = "sessions:";
const sessionsKey = (month: string) => `${sessionsPrefix}${month}`;
const spentPrefix = (provider: string) => `spent:${provider}:`;
const spentKey = (provider: string, day: string) => `${spentPrefix(provider)}${day}`;

type Rate = { minute: number; count: number };

/**
 * One per key id, holding the last assertion counter it accepted and when, its requests this
 * minute, its spend per provider by day, and its free sessions by month. The storage calls are
 * synchronous, so a check and the write behind it run with nothing in between.
 */
export class DeviceCounter extends DurableObject<Env> {
  private stored(): number {
    return this.ctx.storage.kv.get<number>(counterKey) ?? 0;
  }

  /**
   * Accepts `counter` when it moves past the stored value and `floor` and stamps `at` as the
   * last time it did; false means a replay.
   */
  advance(counter: number, floor = 0, at = Date.now()): boolean {
    if (counter <= Math.max(this.stored(), floor)) return false;
    this.ctx.storage.kv.put(counterKey, counter);
    this.ctx.storage.kv.put(seenKey, at);
    return true;
  }

  /** When the last assertion was accepted, in ms; undefined for a key that has passed none. */
  lastSeen(): number | undefined {
    return this.ctx.storage.kv.get<number>(seenKey);
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

  /** What the device has spent on `provider` during `day`, a UTC date, in the provider's unit. */
  spent(provider: string, day: string): number {
    return this.ctx.storage.kv.get<number>(spentKey(provider, day)) ?? 0;
  }

  /** Adds `amount` to the device's `provider` spend for `day` and returns the total; the days before are dropped. */
  spend(provider: string, day: string, amount: number): number {
    const total = this.spent(provider, day) + amount;
    this.ctx.storage.kv.put(spentKey(provider, day), total);
    const stale = [
      ...this.ctx.storage.kv.list({ prefix: spentPrefix(provider), end: spentKey(provider, day) }),
    ];
    for (const [key] of stale) this.ctx.storage.kv.delete(key);
    return total;
  }

  /** Takes the one notes call the session that started at `startedAt` gets; false once taken. */
  claimNotes(startedAt: number): boolean {
    if (this.ctx.storage.kv.get<number>(notesKey) === startedAt) return false;
    this.ctx.storage.kv.put(notesKey, startedAt);
    return true;
  }

  /** Free sessions counted toward `month`, a UTC year and month. */
  sessions(month: string): number {
    return this.ctx.storage.kv.get<number>(sessionsKey(month)) ?? 0;
  }

  /**
   * Counts the free session `id` toward `month` and returns the month's total; a session already
   * counted changes nothing, and the months before are dropped.
   */
  countSession(month: string, id: string): number {
    if (this.ctx.storage.kv.get<string>(countedKey) === id) return this.sessions(month);
    const total = this.sessions(month) + 1;
    this.ctx.storage.kv.put(countedKey, id);
    this.ctx.storage.kv.put(sessionsKey(month), total);
    const stale = [
      ...this.ctx.storage.kv.list({ prefix: sessionsPrefix, end: sessionsKey(month) }),
    ];
    for (const [key] of stale) this.ctx.storage.kv.delete(key);
    return total;
  }
}
