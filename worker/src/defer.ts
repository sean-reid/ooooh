import { AsyncLocalStorage } from "node:async_hooks";

const contexts = new AsyncLocalStorage<ExecutionContext>();

/** Runs `fn` with `ctx` in scope for `deferred`. */
export const withContext = <T>(ctx: ExecutionContext | undefined, fn: () => T): T =>
  ctx ? contexts.run(ctx, fn) : fn();

/**
 * Starts `work` now and lets the response go without waiting for it; a failure is logged
 * under `label`. With no ExecutionContext in scope the work is awaited.
 */
export const deferred = (label: string, work: () => Promise<unknown>): Promise<void> => {
  const settled = work().then(
    () => undefined,
    (e: unknown) => console.error(label, e),
  );
  const ctx = contexts.getStore();
  if (!ctx) return settled;
  ctx.waitUntil(settled);
  return Promise.resolve();
};
