import { createApp } from "./httpServer.ts";
import { runPayoutBatch } from "./services.ts";

if (!process.env.AUTH_SECRET || process.env.AUTH_SECRET.length < 16) {
  // eslint-disable-next-line no-console
  console.error("Missing AUTH_SECRET (min 16 chars). Example:");
  // eslint-disable-next-line no-console
  console.error(`  export AUTH_SECRET="$(openssl rand -hex 32)"`);
  process.exit(1);
}

const port = Number(process.env.PORT ?? "3000");
const { server, store, persist, dataFilePath } = createApp();

server.listen(port, "0.0.0.0", () => {
  // eslint-disable-next-line no-console
  console.log(`API listening on 0.0.0.0:${port}`);
  // eslint-disable-next-line no-console
  console.log(`Data file: ${dataFilePath}`);
  // eslint-disable-next-line no-console
  console.log(`Admin UI: http://localhost:${port}/admin`);
});

// MVP scheduler: every 60 seconds, attempt to pay due batches.
// For production, replace with a real cron/queue worker.
setInterval(() => {
  try {
    const batch = runPayoutBatch(store, { nowUtcMs: Date.now() });
    if (batch.lineIds.length > 0) {
      persist();
      // eslint-disable-next-line no-console
      console.log(
        `Payout batch ${batch.id}: paid ${batch.lineIds.length} lines (cutoffUtcMs=${batch.cutoffUtcMs})`
      );
    }
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error("payout_batch_runner_error", e);
  }
}, 60_000);

