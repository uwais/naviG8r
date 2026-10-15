import { authorizationContext } from "./rbac.ts";
import { randomUUID } from "node:crypto";
import { createApp } from "./httpServer.ts";
import { runPayoutBatch } from "./services.ts";
import {
  claimPendingWebhookDeliveries,
  completeWebhookDelivery,
  deliverIntegrationWebhook,
} from "./integrationWebhooks.ts";
import { pushFlagEnabled } from "./features/push/push.ts";
import { HttpV1FcmSender } from "./features/push/fcmSender.ts";
import { runPushCleanupTick, runPushDeliveryTick } from "./features/push/pushWorker.ts";

let pushDeliveryTickInFlight = false;

if (!process.env.AUTH_SECRET || process.env.AUTH_SECRET.length < 16) {
  // eslint-disable-next-line no-console
  console.error("Missing AUTH_SECRET (min 16 chars). Example:");
  // eslint-disable-next-line no-console
  console.error(`  export AUTH_SECRET="$(openssl rand -hex 32)"`);
  process.exit(1);
}

async function main(): Promise<void> {
  const port = Number(process.env.PORT ?? "3000");
  const app = await createApp();
  const { server, store, persist, runSerialized, dataFilePath } = app;
  const fcmSender = new HttpV1FcmSender();

  server.listen(port, "0.0.0.0", () => {
    // eslint-disable-next-line no-console
    console.log(`API listening on 0.0.0.0:${port}`);
    // eslint-disable-next-line no-console
    console.log(dataFilePath != null ? `Data file: ${dataFilePath}` : "Persistence: Postgres (Prisma, PERSISTENCE=DB)");
    // eslint-disable-next-line no-console
    console.log(`Admin UI: http://localhost:${port}/admin`);
  });

  setInterval(() => {
    void (async () => {
      try {
        const batch = await runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
          const result = await runPayoutBatch(store, { nowUtcMs: Date.now() });
          if (result.lineIds.length > 0) await persist();
          return result;
        }));
        if (batch.lineIds.length > 0) {
          // eslint-disable-next-line no-console
          console.log(`Payout batch ${batch.id}: paid ${batch.lineIds.length} lines (cutoffUtcMs=${batch.cutoffUtcMs})`);
        }
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error("payout_batch_runner_error", e);
      }
    })();
  }, 60_000);

  setInterval(() => {
    void (async () => {
      try {
        const claims = await runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
          const result = claimPendingWebhookDeliveries(store, { leaseMs: 60_000, limit: 4 });
          if (result.changed) await persist();
          return result.claims;
        }));
        await Promise.all(claims.map(async claim => {
          const result = await deliverIntegrationWebhook(claim.delivery, claim.webhookSecret);
          await runSerialized(() => authorizationContext.run({ system: true, requestId: randomUUID() }, async () => {
            if (completeWebhookDelivery(store, claim, result)) await persist();
          }));
        }));
        if (claims.length > 0) {
          // eslint-disable-next-line no-console
          console.log(`Integration webhooks: processed ${claims.length} delivery attempt(s)`);
        }
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error("integration_webhook_runner_error", e);
      }
    })();
  }, 30_000);

  setInterval(() => {
    if (!pushFlagEnabled("PUSH_SENDER_ENABLED") || pushDeliveryTickInFlight) return;
    pushDeliveryTickInFlight = true;
    void (async () => {
      try {
        const count = await runPushDeliveryTick({ store, sender: fcmSender, runSerialized, persist });
        if (count > 0) {
          // eslint-disable-next-line no-console
          console.log(`FCM: submitted ${count} device delivery attempt(s)`);
        }
      } catch (error) {
        // Deliberately omit provider/token/payload details from logs.
        // eslint-disable-next-line no-console
        console.error("fcm_delivery_worker_error", error instanceof Error ? error.name : "unknown");
      } finally {
        pushDeliveryTickInFlight = false;
      }
    })();
  }, 5_000);

  setInterval(() => {
    void runPushCleanupTick({ store, runSerialized, persist }).catch(error => {
      // eslint-disable-next-line no-console
      console.error("push_state_cleanup_error", error instanceof Error ? error.name : "unknown");
    });
  }, 60 * 60_000);
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error("fatal_boot_error", e);
  process.exit(1);
});
