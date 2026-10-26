import { DurableObject } from "cloudflare:workers";

const prefix = "spent:";
const dayKey = (day: string) => `${prefix}${day}`;

/**
 * One per provider, holding what each UTC day has spent against its cap. The storage calls are
 * synchronous, so two charges landing together both count.
 */
export class ProviderBudget extends DurableObject<Env> {
  spent(day: string): number {
    return this.ctx.storage.kv.get<number>(dayKey(day)) ?? 0;
  }

  /** Adds `amount` to `day` and returns the day's total; the days before it are dropped. */
  add(day: string, amount: number): number {
    const total = this.spent(day) + amount;
    this.ctx.storage.kv.put(dayKey(day), total);
    const stale = [...this.ctx.storage.kv.list({ prefix, end: dayKey(day) })];
    for (const [key] of stale) this.ctx.storage.kv.delete(key);
    return total;
  }
}
