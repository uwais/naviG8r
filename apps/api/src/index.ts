import { createApp } from "./httpServer.ts";
import { runPayoutBatch } from "./services.ts";
import { processPendingWebhookDeliveries } from "./integrationWebhooks.ts";

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
  const { server, store, persist, dataFilePath } = app;

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
        const batch = await runPayoutBatch(store, { nowUtcMs: Date.now() });
        if (batch.lineIds.length > 0) {
          await persist();
          // eslint-disable-next-line no-console
          console.log(
            `Payout batch ${batch.id}: paid ${batch.lineIds.length} lines (cutoffUtcMs=${batch.cutoffUtcMs})`,
          );
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
        const n = await processPendingWebhookDeliveries(store);
        if (n > 0) {
          await persist();
          // eslint-disable-next-line no-console
          console.log(`Integration webhooks: processed ${n} delivery attempt(s)`);
        }
      } catch (e) {
        // eslint-disable-next-line no-console
        console.error("integration_webhook_runner_error", e);
      }
    })();
  }, 30_000);
}

main().catch((e) => {
  // eslint-disable-next-line no-console
  console.error("fatal_boot_error", e);
  process.exit(1);
});
