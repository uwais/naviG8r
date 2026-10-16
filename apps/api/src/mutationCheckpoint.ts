import type { Store } from "./store.ts";

const checkpoints = new WeakMap<Store, () => void>();

export function registerMutationCheckpointer(store: Store, checkpoint: () => void): void {
  checkpoints.set(store, checkpoint);
}

/**
 * Remember the current in-memory store as the rollback point for this mutation.
 * Call only after an external side effect has succeeded and the store already
 * records that result, so a later failed save cannot repeat the side effect.
 */
export function checkpointMutation(store: Store): void {
  checkpoints.get(store)?.();
}
