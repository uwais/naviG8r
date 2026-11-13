import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { randomBytes } from "node:crypto";
import { createApp } from "../../../httpServer.ts";
import { loadStoreFromDisk } from "../../../persistence.ts";
import { createStore } from "../../../store.ts";
import { enqueuePushIntentForNotification, registerPushDevice } from "../push.ts";
import { runPushDeliveryTick } from "../pushWorker.ts";
import type { FcmDeliveryMessage, FcmSender, FcmSendResult } from "../fcmSender.ts";
import type { Membership, Notification, Organization, Shipment, User } from "../../../types.ts";

test("push worker persists a lease, sends outside the mutation queue, and conditionally saves completion", async () => {
  const env = {
    persistence: process.env.PERSISTENCE,
    dataFile: process.env.DATA_FILE,
    registration: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
    enqueue: process.env.PUSH_ENQUEUE_ENABLED,
    sender: process.env.PUSH_SENDER_ENABLED,
    environment: process.env.PUSH_ENVIRONMENT,
    encryptionKey: process.env.PUSH_TOKEN_ENCRYPTION_KEY,
    authSecret: process.env.AUTH_SECRET,
    fcmServiceAccount: process.env.FCM_SERVICE_ACCOUNT_JSON,
  };
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "navig8r-push-worker-"));
  process.env.PERSISTENCE = "FILE";
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_ENQUEUE_ENABLED = "1";
  process.env.PUSH_SENDER_ENABLED = "1";
  process.env.PUSH_ENVIRONMENT = "DEVELOPMENT";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  process.env.AUTH_SECRET = "synthetic-test-signing-value-only";
  process.env.FCM_SERVICE_ACCOUNT_JSON = "{}";
  const app = await createApp({ dataFilePath: path.join(dir, "store.json") });
  const store = app.store;
  const user = { id: "user-1", phone: "8000000001", fullName: "User", createdAtUtcMs: 1 } as User;
  const organization = { id: "org-1", displayName: "Shipper", kind: "CUSTOMER", createdAtUtcMs: 1 } as Organization;
  const membership = { userId: user.id, orgId: organization.id, role: "CUSTOMER_ADMIN", createdAtUtcMs: 1 } as Membership;
  const shipment = { id: "shipment-1", customerOrgId: organization.id, carrierId: "carrier-1", status: "BOOKED", createdAtUtcMs: 1000 } as Shipment;
  const notification: Notification = {
    id: "notification-1", recipientSequence: 1, eventId: "event-1", eventKey: "shipment.booked",
    recipientUserId: user.id, recipientOrgId: organization.id, shipmentId: shipment.id, createdAtUtcMs: 1000,
  };
  store.users.set(user.id, user);
  store.organizations.set(organization.id, organization);
  store.memberships.set(`${user.id}:${organization.id}`, membership);
  store.membershipRoles.set(`${user.id}:${organization.id}`, ["SHIPPER"]);
  store.shipments.set(shipment.id, shipment);
  store.notifications.set(notification.id, notification);
  registerPushDevice(store, {
    userId: user.id, installationId: "install-0000000000001", token: "fcm-registration-token-user-1-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 1000,
  });
  enqueuePushIntentForNotification(store, notification);

  let signalStarted!: () => void;
  const started = new Promise<void>(resolve => { signalStarted = resolve; });
  let finishSend!: (value: FcmSendResult) => void;
  const sendResult = new Promise<FcmSendResult>(resolve => { finishSend = resolve; });
  const sender: FcmSender = {
    async send(_message: FcmDeliveryMessage) {
      signalStarted();
      return sendResult;
    },
  };

  const tick = runPushDeliveryTick({ store, sender, runSerialized: app.runSerialized, persist: app.persist, nowUtcMs: 2000 });
  await started;
  const delivery = [...store.pushDeliveries.values()][0]!;
  assert.ok(delivery.leaseId);
  assert.ok(delivery.leaseUntilUtcMs);

  await app.runSerialized(async () => {
    store.notificationSequence = 2;
    await app.persist();
  });
  assert.equal(store.notificationSequence, 2, "another mutation completes while FCM network I/O is pending");

  finishSend({ kind: "accepted", providerMessageId: "provider-message" });
  assert.equal(await tick, 1);
  assert.equal(store.pushDeliveries.get(delivery.id)?.status, "ACCEPTED");
  const reloaded = loadStoreFromDisk(path.join(dir, "store.json"));
  assert.equal(reloaded.pushDeliveries.get(delivery.id)?.status, "ACCEPTED");
  assert.equal(reloaded.notificationSequence, 2);

  fs.rmSync(dir, { recursive: true, force: true });
  const values = [
    ["PERSISTENCE", env.persistence], ["DATA_FILE", env.dataFile],
    ["PUSH_DEVICE_REGISTRATION_ENABLED", env.registration], ["PUSH_ENQUEUE_ENABLED", env.enqueue],
    ["PUSH_SENDER_ENABLED", env.sender], ["PUSH_ENVIRONMENT", env.environment],
    ["PUSH_TOKEN_ENCRYPTION_KEY", env.encryptionKey], ["AUTH_SECRET", env.authSecret],
    ["FCM_SERVICE_ACCOUNT_JSON", env.fcmServiceAccount],
  ] as const;
  for (const [key, value] of values) if (value == null) delete process.env[key]; else process.env[key] = value;
});

test("push worker waits for all active sends when one completion save fails", async () => {
  const env = {
    persistence: process.env.PERSISTENCE,
    dataFile: process.env.DATA_FILE,
    registration: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
    enqueue: process.env.PUSH_ENQUEUE_ENABLED,
    sender: process.env.PUSH_SENDER_ENABLED,
    environment: process.env.PUSH_ENVIRONMENT,
    encryptionKey: process.env.PUSH_TOKEN_ENCRYPTION_KEY,
    authSecret: process.env.AUTH_SECRET,
    fcmServiceAccount: process.env.FCM_SERVICE_ACCOUNT_JSON,
  };
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_ENQUEUE_ENABLED = "1";
  process.env.PUSH_SENDER_ENABLED = "1";
  process.env.PUSH_ENVIRONMENT = "DEVELOPMENT";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  const store = createStore();
  let serialized: Promise<unknown> = Promise.resolve();
  const runSerialized = <T>(operation: () => Promise<T> | T): Promise<T> => {
    const result = serialized.then(operation, operation) as Promise<T>;
    serialized = result.then(() => undefined, () => undefined);
    return result;
  };
  const user = { id: "user-1", phone: "8000000001", fullName: "User", createdAtUtcMs: 1 } as User;
  const organization = { id: "org-1", displayName: "Shipper", kind: "CUSTOMER", createdAtUtcMs: 1 } as Organization;
  const membership = { userId: user.id, orgId: organization.id, role: "CUSTOMER_ADMIN", createdAtUtcMs: 1 } as Membership;
  const shipment = { id: "shipment-1", customerOrgId: organization.id, carrierId: "carrier-1", status: "BOOKED", createdAtUtcMs: 1000 } as Shipment;
  const baseNotification: Notification = {
    id: "notification-1", recipientSequence: 1, eventId: "event-1", eventKey: "shipment.booked",
    recipientUserId: user.id, recipientOrgId: organization.id, shipmentId: shipment.id, createdAtUtcMs: 1000,
  };
  store.users.set(user.id, user);
  store.organizations.set(organization.id, organization);
  store.memberships.set(`${user.id}:${organization.id}`, membership);
  store.membershipRoles.set(`${user.id}:${organization.id}`, ["SHIPPER"]);
  store.shipments.set(shipment.id, shipment);
  store.notifications.set(baseNotification.id, baseNotification);
  store.notifications.set("notification-2", {
    ...baseNotification,
    id: "notification-2",
    recipientSequence: 2,
    eventId: "event-2",
    createdAtUtcMs: 1001,
  });
  registerPushDevice(store, {
    userId: user.id, installationId: "install-0000000000001", token: "fcm-registration-token-user-1-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 1000,
  });
  enqueuePushIntentForNotification(store, baseNotification);
  enqueuePushIntentForNotification(store, store.notifications.get("notification-2")!);

  let sendCount = 0;
  let startSecond!: () => void;
  const secondStarted = new Promise<void>(resolve => { startSecond = resolve; });
  let releaseSecond!: (value: FcmSendResult) => void;
  const secondResult = new Promise<FcmSendResult>(resolve => { releaseSecond = resolve; });
  let reportFailedSave!: () => void;
  const failedSave = new Promise<void>(resolve => { reportFailedSave = resolve; });
  let persistCount = 0;
  const persist = async () => {
    persistCount++;
    if (persistCount === 2) {
      reportFailedSave();
      throw new Error("injected completion persistence failure");
    }
    return;
  };
  const sender: FcmSender = {
    async send(_message: FcmDeliveryMessage) {
      sendCount++;
      if (sendCount === 1) return { kind: "accepted", providerMessageId: "first" };
      startSecond();
      return secondResult;
    },
  };

  const tick = runPushDeliveryTick({ store, sender, runSerialized, persist, nowUtcMs: 2000 });
  await secondStarted;
  await failedSave;
  let tickSettled = false;
  void tick.finally(() => { tickSettled = true; }).catch(() => {});
  await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(tickSettled, false, "worker keeps its tick active while another sender is outstanding");
  releaseSecond({ kind: "accepted", providerMessageId: "second" });
  await assert.rejects(tick, /injected completion persistence failure/);
  assert.equal(sendCount, 2);

  const values = [
    ["PERSISTENCE", env.persistence], ["DATA_FILE", env.dataFile],
    ["PUSH_DEVICE_REGISTRATION_ENABLED", env.registration], ["PUSH_ENQUEUE_ENABLED", env.enqueue],
    ["PUSH_SENDER_ENABLED", env.sender], ["PUSH_ENVIRONMENT", env.environment],
    ["PUSH_TOKEN_ENCRYPTION_KEY", env.encryptionKey], ["AUTH_SECRET", env.authSecret],
    ["FCM_SERVICE_ACCOUNT_JSON", env.fcmServiceAccount],
  ] as const;
  for (const [key, value] of values) if (value == null) delete process.env[key]; else process.env[key] = value;
});
