import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { createStore } from "../../../store.ts";
import { dumpStore, loadStoreFromDisk } from "../../../persistence.ts";

test("additive FILE metadata round-trips push rows and reads pre-push v7 notifications unchanged", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-push-persist-"));
  const file = path.join(dir, "store.json");
  const store = createStore();
  store.notificationSequence = 42;
  store.notifications.set("notification-1", {
    id: "notification-1", recipientSequence: 42, eventId: "event-1", eventKey: "shipment.booked",
    recipientUserId: "user-1", recipientOrgId: "org-1", shipmentId: "shipment-1", createdAtUtcMs: 100,
  });
  store.pushIntents.set("intent-1", {
    id: "intent-1", notificationId: "notification-1", recipientUserId: "user-1", recipientOrgId: "org-1",
    shipmentId: "shipment-1", presentationKey: "stable-key", createdAtUtcMs: 100, expiresAtUtcMs: 86_400_100,
  });
  store.pushDevices.set("device-1", {
    id: "device-1", installationId: "install-1", userId: "user-1", platform: "ANDROID", tokenCiphertext: "encrypted-token",
    tokenHash: "hash", environment: "DEVELOPMENT", consentedAtUtcMs: 100, permissionGrantedHint: true,
    channelEnabledHint: true, ownershipGeneration: 1, createdAtUtcMs: 100, updatedAtUtcMs: 100, lastSeenAtUtcMs: 100, revokedAtUtcMs: null,
  });
  fs.writeFileSync(file, JSON.stringify(dumpStore(store)));
  const reloaded = loadStoreFromDisk(file);
  assert.equal(reloaded.notificationSequence, 42);
  assert.equal(reloaded.notifications.get("notification-1")?.eventKey, "shipment.booked");
  assert.equal(reloaded.pushIntents.get("intent-1")?.presentationKey, "stable-key");
  assert.equal(reloaded.pushDevices.get("device-1")?.tokenCiphertext, "encrypted-token");

  const legacy = dumpStore(store) as unknown as Record<string, unknown>;
  delete legacy.pushDevices;
  delete legacy.pushIntents;
  delete legacy.pushDeliveries;
  fs.writeFileSync(file, JSON.stringify(legacy));
  const legacyReloaded = loadStoreFromDisk(file);
  assert.equal(legacyReloaded.notificationSequence, 42);
  assert.equal(legacyReloaded.notifications.get("notification-1")?.id, "notification-1");
  assert.equal(legacyReloaded.pushDevices.size, 0);
  fs.rmSync(dir, { recursive: true, force: true });
});
