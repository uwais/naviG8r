import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createApp } from "../../httpServer.ts";
import { loadStoreFromDisk } from "../../persistence.ts";

test("serialized persistence failure restores nested Store state before a later save", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-mutation-test-"));
  const filePath = path.join(dir, "store.json");
  let failNextPersist = true;
  const app = await createApp({
    dataFilePath: filePath,
    beforePersist: () => {
      if (failNextPersist) {
        failNextPersist = false;
        throw new Error("injected_persistence_failure");
      }
    },
  });
  const deliveryMap = app.store.integrationWebhookDeliveries;
  const delivery = {
    id: "delivery-1",
    eventId: "event-1",
    orgId: "org-1",
    connectionId: "connection-1",
    webhookUrl: "https://example.invalid/hook",
    payloadJson: "{}",
    status: "PENDING" as const,
    attempts: 0,
    nextRetryAtUtcMs: 1,
    lastHttpStatus: null,
    lastError: null,
    deliveredAtUtcMs: null,
    createdAtUtcMs: 1,
    updatedAtUtcMs: 1,
  };
  const originalDelivery = structuredClone(delivery);
  app.store.integrationWebhookDeliveries.set(delivery.id, delivery);

  await assert.rejects(app.runSerialized(async () => {
    const current = app.store.integrationWebhookDeliveries.get(delivery.id)!;
    current.attempts = 4;
    current.status = "DEAD";
    current.lastError = "temporary mutation";
    app.store.notificationSequence = 17;
    await app.persist();
  }), /injected_persistence_failure/);

  assert.equal(app.store.integrationWebhookDeliveries, deliveryMap, "rollback preserves Store map identity");
  assert.deepEqual(app.store.integrationWebhookDeliveries.get(delivery.id), originalDelivery);
  assert.equal(app.store.notificationSequence, 0);

  await app.runSerialized(async () => {
    app.store.notificationSequence = 1;
    await app.persist();
  });

  const reloaded = loadStoreFromDisk(filePath);
  assert.equal(reloaded.notificationSequence, 1);
  assert.deepEqual(reloaded.integrationWebhookDeliveries.get(delivery.id), originalDelivery);
  fs.rmSync(dir, { recursive: true, force: true });
});

test("runSerialized keeps concurrent mutation jobs in order", async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-mutation-order-"));
  const app = await createApp({ dataFilePath: path.join(dir, "store.json") });
  const order: string[] = [];
  await Promise.all([
    app.runSerialized(async () => {
      order.push("first:start");
      await new Promise(resolve => setTimeout(resolve, 10));
      order.push("first:end");
    }),
    app.runSerialized(() => order.push("second")),
  ]);
  assert.deepEqual(order, ["first:start", "first:end", "second"]);
  fs.rmSync(dir, { recursive: true, force: true });
});
