// Helpers that need the Workers runtime: the test Worker itself and its KV namespace.
import { env, SELF } from "cloudflare:test";
import { jsonRequest } from "./request";

export const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  SELF.fetch(jsonRequest(path, body, headers));

/** Every key in the shared namespace, so one suite's counters never reach the next. */
export const wipeKV = async () => {
  const { keys } = await env.BUDGET.list();
  await Promise.all(keys.map((k) => env.BUDGET.delete(k.name)));
};
