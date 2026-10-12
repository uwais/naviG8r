import type { Store } from "../../store.ts";
import { randomUUID } from "node:crypto";
import { authorizationContext } from "../../rbac.ts";
import { cleanupPushState, decryptPushToken, pushFcmMessage, pushFlagEnabled, claimPushDeliveries, completePushDelivery } from "./push.ts";
import type { FcmSender, FcmSendResult } from "./fcmSender.ts";

type RunSerialized = <T>(operation: () => Promise<T> | T) => Promise<T>;

export function runPushCleanupTick(options: {
  store: Store;
  runSerialized: RunSerialized;
  persist: () => Promise<void>;
  nowUtcMs?: number;
}): Promise<number> {
  return options.runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
    const changed = cleanupPushState(options.store, options.nowUtcMs);
    if (changed > 0) await options.persist();
    return changed;
  }));
}

export async function runPushDeliveryTick(options: {
  store: Store;
  sender: FcmSender;
  runSerialized: RunSerialized;
  persist: () => Promise<void>;
  nowUtcMs?: number;
}): Promise<number> {
  if (!pushFlagEnabled("PUSH_SENDER_ENABLED")) return 0;
  const claimed = await options.runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
    const result = claimPushDeliveries(options.store, { nowUtcMs: options.nowUtcMs, limit: 4, leaseMs: 30_000 });
    if (result.changed) await options.persist();
    return result.claims;
  }));
  const completions = await Promise.allSettled(claimed.map(async claim => {
    let result: FcmSendResult;
    try {
      const token = decryptPushToken(claim.device.tokenCiphertext);
      result = await options.sender.send(pushFcmMessage(claim, token, options.nowUtcMs));
    } catch {
      result = { kind: "permanent", errorCode: "FCM_DELIVERY_SETUP_FAILED" };
    }
    await options.runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
      if (completePushDelivery(options.store, claim, result, { nowUtcMs: options.nowUtcMs })) await options.persist();
    }));
  }));
  const failedCompletion = completions.find(
    (completion): completion is PromiseRejectedResult => completion.status === "rejected",
  );
  if (failedCompletion) throw failedCompletion.reason;
  return claimed.length;
}
