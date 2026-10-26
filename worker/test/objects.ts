// The Durable Object bindings for the node project, which has no Workers runtime: each name gets
// one instance of the shipped class over a Map, so the counting under test is the real code.
import { DeviceCounter } from "../src/attest/counter";
import { ProviderBudget } from "../src/spend";

class MemoryStorage {
  private map = new Map<string, unknown>();

  get<T>(key: string): T | undefined {
    return this.map.get(key) as T | undefined;
  }

  put<T>(key: string, value: T): void {
    this.map.set(key, value);
  }

  delete(key: string): boolean {
    return this.map.delete(key);
  }

  list<T>(options: { prefix?: string; end?: string } = {}): [string, T][] {
    return [...this.map.entries()]
      .filter(([key]) => key.startsWith(options.prefix ?? ""))
      .filter(([key]) => options.end === undefined || key < options.end)
      .sort(([a], [b]) => (a < b ? -1 : 1)) as [string, T][];
  }
}

/** The object behind a stub whose every method answers a promise, as an RPC call does. */
const stub = <T extends object>(object: T) =>
  new Proxy(object, {
    get(target, property) {
      const value = Reflect.get(target, property) as unknown;
      if (typeof value !== "function") return value;
      return async (...args: unknown[]) =>
        (value as (...a: unknown[]) => unknown).apply(target, args);
    },
  });

const namespace = <T extends object>(make: (ctx: DurableObjectState) => T) => {
  const objects = new Map<string, T>();
  return {
    getByName(name: string) {
      let object = objects.get(name);
      if (!object) {
        object = stub(
          make({ storage: { kv: new MemoryStorage() } } as unknown as DurableObjectState),
        );
        objects.set(name, object);
      }
      return object;
    },
  };
};

export const memoryObjects = () => ({
  DEVICE_COUNTER: namespace(
    (ctx) => new DeviceCounter(ctx, {} as Env),
  ) as unknown as Env["DEVICE_COUNTER"],
  PROVIDER_BUDGET: namespace(
    (ctx) => new ProviderBudget(ctx, {} as Env),
  ) as unknown as Env["PROVIDER_BUDGET"],
});
