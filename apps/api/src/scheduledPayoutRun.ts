import { randomUUID } from "node:crypto";
import { authorizationContext } from "./rbac.ts";
import { runPayoutBatch } from "./services.ts";
import type { Store } from "./store.ts";
import type { PayoutBatch } from "./types.ts";

type RunSerialized = <T>(operation: () => Promise<T> | T, captureSnapshot?: boolean) => Promise<T>;

/** The payout timer's run, queued behind every other writer so no request changes the store mid-run. */
export function runScheduledPayouts(options: {
  store: Store;
  runSerialized: RunSerialized;
  persist: () => Promise<void>;
  nowUtcMs?: number;
}): Promise<PayoutBatch> {
  // No snapshot: on a failed save the queue would roll memory back past payouts already sent, erasing their
  // records. runPayoutBatch handles a failed save itself, one carrier at a time.
  return options.runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
    const batch = await runPayoutBatch(options.store, { nowUtcMs: options.nowUtcMs ?? Date.now(), saveBeforePayout: options.persist });
    // Save whenever a payout was attempted, not only when lines were paid: unresolved requests are recorded too.
    if (batch.transfers.some((t) => t.status !== "SKIPPED_NO_FUND_ACCOUNT")) await options.persist();
    return batch;
  }), false);
}
