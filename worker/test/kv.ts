// Enough of KVNamespace for the budget guard when a test builds its own Env.
export class MemoryKV {
  store = new Map<string, string>();

  async get(key: string, type?: "text" | "json"): Promise<unknown> {
    const value = this.store.get(key) ?? null;
    return type === "json" && value !== null ? JSON.parse(value) : value;
  }

  async put(key: string, value: string): Promise<void> {
    this.store.set(key, value);
  }

  async delete(key: string): Promise<void> {
    this.store.delete(key);
  }

  async list(): Promise<{ keys: { name: string }[] }> {
    return { keys: [...this.store.keys()].map((name) => ({ name })) };
  }
}

export const memoryKV = () => new MemoryKV() as unknown as KVNamespace;

// A test that runs with attestation off never reaches the counter, so the binding only has to exist.
export const noCounter = {
  getByName() {
    throw new Error("no DeviceCounter with attestation off");
  },
} as unknown as Env["DEVICE_COUNTER"];
