import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, randomBytes } from "node:crypto";
import { createStore } from "../../../store.ts";
import {
  claimPushDeliveries,
  cleanupPushState,
  completePushDelivery,
  decryptPushToken,
  encryptPushToken,
  enqueuePushIntentForNotification,
  pushFcmMessage,
  registerPushDevice,
  revokePushDevice,
} from "../push.ts";
import { HttpV1FcmSender } from "../fcmSender.ts";
import type { Membership, Notification, Organization, Shipment, User } from "../../../types.ts";

const env = {
  registration: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
  enqueue: process.env.PUSH_ENQUEUE_ENABLED,
  environment: process.env.PUSH_ENVIRONMENT,
  encryptionKey: process.env.PUSH_TOKEN_ENCRYPTION_KEY,
  fcmServiceAccount: process.env.FCM_SERVICE_ACCOUNT_JSON,
};

test("push credentials encrypt at rest and ownership generations fence stale revocation", () => {
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  const store = createStore();
  const firstToken = "fcm-registration-token-user-a-1234567890";
  const first = registerPushDevice(store, {
    userId: "user-a", installationId: "install-0000000000001", token: firstToken,
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 100,
  });
  assert.notEqual(first.tokenCiphertext, firstToken);
  assert.equal(first.tokenCiphertext.includes(firstToken), false);
  assert.equal(decryptPushToken(first.tokenCiphertext), firstToken);
  assert.equal(decryptPushToken(encryptPushToken(firstToken)), firstToken);

  const reassigned = registerPushDevice(store, {
    userId: "user-b", installationId: "install-0000000000001", token: "fcm-registration-token-user-b-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 200,
  });
  assert.equal(reassigned.id, first.id);
  assert.equal(reassigned.ownershipGeneration, first.ownershipGeneration + 1);
  assert.equal(revokePushDevice(store, { userId: "user-a", deviceId: first.id, ownershipGeneration: first.ownershipGeneration, nowUtcMs: 300 }), false);
  assert.equal(revokePushDevice(store, { userId: "user-b", deviceId: first.id, ownershipGeneration: reassigned.ownershipGeneration, nowUtcMs: 400 }), true);
  assert.equal(store.pushDevices.get(first.id)?.tokenCiphertext, "");
});

test("reactivating a revoked installation cannot exceed the active device cap", () => {
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  const store = createStore();
  const target = registerPushDevice(store, {
    userId: "capped-user",
    installationId: "install-revoked-target-0001",
    token: "fcm-token-revoked-target-1234567890",
    consented: true,
    permissionGranted: true,
    channelEnabled: true,
    nowUtcMs: 50,
  });
  revokePushDevice(store, {
    userId: "capped-user",
    deviceId: target.id,
    ownershipGeneration: target.ownershipGeneration,
    nowUtcMs: 75,
  });
  Array.from({ length: 5 }, (_, index) => registerPushDevice(store, {
    userId: "capped-user",
    installationId: `install-capped-${String(index).padStart(8, "0")}`,
    token: `fcm-token-capped-${index}-1234567890`,
    consented: true,
    permissionGranted: true,
    channelEnabled: true,
    nowUtcMs: 100 + index,
  }));
  assert.throws(() => registerPushDevice(store, {
    userId: "capped-user",
    installationId: target.installationId,
    token: "fcm-token-reactivated-1234567890",
    consented: true,
    permissionGranted: true,
    channelEnabled: true,
    nowUtcMs: 300,
  }), /push_device_limit_reached/);
});

test("push cleanup cursor eventually reaches records beyond the first batch", () => {
  const store = createStore();
  const old = 1;
  for (let index = 0; index < 501; index++) {
    const id = `device-${String(index).padStart(4, "0")}`;
    store.pushDevices.set(id, {
      id,
      installationId: `installation-${id}`,
      userId: "cleanup-user",
      platform: "ANDROID",
      tokenCiphertext: "",
      tokenHash: "",
      environment: "DEVELOPMENT",
      consentedAtUtcMs: old,
      permissionGrantedHint: false,
      channelEnabledHint: false,
      ownershipGeneration: 2,
      createdAtUtcMs: old,
      updatedAtUtcMs: old,
      lastSeenAtUtcMs: old,
      revokedAtUtcMs: old,
    });
  }
  const now = 31 * 24 * 60 * 60 * 1000;
  cleanupPushState(store, now, 500);
  assert.equal(store.pushDevices.size, 1);
  cleanupPushState(store, now, 500);
  assert.equal(store.pushDevices.size, 0);
});

test("push intent snapshots eligible devices once and delivery retries respect retry-after", () => {
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_ENQUEUE_ENABLED = "1";
  process.env.PUSH_ENVIRONMENT = "DEVELOPMENT";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  const store = createStore();
  const user = { id: "user-1", phone: "8000000001", fullName: "User", createdAtUtcMs: 1 } as User;
  const organization = { id: "org-1", displayName: "Shipper", kind: "CUSTOMER", createdAtUtcMs: 1 } as Organization;
  const membership = { userId: user.id, orgId: organization.id, role: "CUSTOMER_ADMIN", createdAtUtcMs: 1 } as Membership;
  const shipment = { id: "shipment-1", customerOrgId: organization.id, carrierId: "carrier-1", status: "BOOKED", createdAtUtcMs: 1000 } as Shipment;
  const notification: Notification = {
    id: "notification-1", recipientSequence: 1, eventId: "event-1", eventKey: "shipment.booked",
    recipientUserId: user.id, recipientOrgId: organization.id, shipmentId: shipment.id,
    createdAtUtcMs: 1000, data: { body: "private shipment detail" },
  };
  store.users.set(user.id, user);
  store.organizations.set(organization.id, organization);
  store.memberships.set(`${user.id}:${organization.id}`, membership);
  store.membershipRoles.set(`${user.id}:${organization.id}`, ["SHIPPER"]);
  store.shipments.set(shipment.id, shipment);
  store.notifications.set(notification.id, notification);
  store.notificationSequence = 1;
  const device = registerPushDevice(store, {
    userId: user.id, installationId: "install-0000000000001", token: "fcm-registration-token-user-1-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 1000,
  });

  const intent = enqueuePushIntentForNotification(store, notification)!;
  assert.ok(intent);
  assert.equal(store.pushDeliveries.size, 1);
  registerPushDevice(store, {
    userId: "user-later", installationId: "install-0000000000002", token: "fcm-registration-token-user-later-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 1100,
  });
  assert.equal(enqueuePushIntentForNotification(store, notification)?.id, intent.id);
  assert.equal(store.pushDeliveries.size, 1, "newly registered devices receive no historical delivery");

  const firstClaim = claimPushDeliveries(store, { nowUtcMs: 1000, limit: 1 });
  assert.equal(firstClaim.claims.length, 1);
  const claim = firstClaim.claims[0]!;
  const message = pushFcmMessage(claim, decryptPushToken(device.tokenCiphertext), 1000);
  assert.equal(message.notificationId, notification.id);
  assert.equal(message.presentationKey, intent.presentationKey);
  assert.equal(JSON.stringify(message).includes("private shipment detail"), false);

  assert.equal(completePushDelivery(store, claim, {
    kind: "transient", errorCode: "FCM_QUOTA_EXCEEDED", retryAfterMs: 90_000, quota: true,
  }, { nowUtcMs: 2000, random: () => 0 }), true);
  const pending = store.pushDeliveries.get(claim.delivery.id)!;
  assert.equal(pending.status, "PENDING");
  assert.equal(pending.nextAttemptAtUtcMs, 92_000, "quota Retry-After is a minimum, never an early retry");

  const laterClaim = claimPushDeliveries(store, { nowUtcMs: 92_000, limit: 1 });
  assert.equal(laterClaim.claims.length, 1);
  const exhausted = laterClaim.claims[0]!;
  store.pushDeliveries.set(exhausted.delivery.id, {
    ...store.pushDeliveries.get(exhausted.delivery.id)!,
    attempts: 8,
    leaseId: null,
    leaseUntilUtcMs: null,
  });
  const afterAttemptCap = claimPushDeliveries(store, {
    nowUtcMs: 92_001,
    limit: 1,
  });
  assert.equal(afterAttemptCap.claims.length, 0);
  assert.equal(store.pushDeliveries.get(exhausted.delivery.id)?.status, "EXPIRED");
  // Restore a pending attempt for the ownership-generation completion assertion.
  store.pushDeliveries.set(exhausted.delivery.id, {
    ...store.pushDeliveries.get(exhausted.delivery.id)!,
    status: "PENDING",
    attempts: 1,
    nextAttemptAtUtcMs: 92_000,
  });
  const ownershipClaim = claimPushDeliveries(store, { nowUtcMs: 92_000, limit: 1 });
  registerPushDevice(store, {
    userId: user.id, installationId: "install-0000000000001", token: "fcm-registration-token-user-1-rotated-1234567890",
    consented: true, permissionGranted: true, channelEnabled: true, nowUtcMs: 93_000,
  });
  const staleClaim = ownershipClaim.claims[0]!;
  assert.equal(completePushDelivery(store, staleClaim, { kind: "accepted", providerMessageId: "message-1" }, { nowUtcMs: 94_000 }), true);
  assert.equal(store.pushDeliveries.get(staleClaim.delivery.id)?.status, "SUPPRESSED");
  assert.notEqual(store.pushDevices.get(device.id)?.ownershipGeneration, staleClaim.delivery.ownershipGeneration);
});

test("FCM HTTP v1 payload uses generic copy, shipment tag, fixed SDK notification id contract, and remaining TTL", async () => {
  const { privateKey } = generateKeyPairSync("rsa", { modulusLength: 2048 });
  process.env.FCM_SERVICE_ACCOUNT_JSON = JSON.stringify({
    project_id: "navig8r-dev", client_email: "fcm@navig8r-dev.iam.gserviceaccount.com", private_key: privateKey.export({ type: "pkcs8", format: "pem" }),
  });
  const requests: Array<{ url: string; init: RequestInit }> = [];
  const fetcher: typeof fetch = async (input, init = {}) => {
    const url = String(input);
    requests.push({ url, init });
    if (url.endsWith("/token")) return new Response(JSON.stringify({ access_token: "access-token", expires_in: 3600 }), { status: 200 });
    return new Response(JSON.stringify({ name: "projects/navig8r-dev/messages/123" }), { status: 200 });
  };
  const sender = new HttpV1FcmSender(fetcher);
  const result = await sender.send({ token: "raw-token-for-test", notificationId: "note-1", presentationKey: "stable-key", ttlMs: 90_000 });
  assert.deepEqual(result, { kind: "accepted", providerMessageId: "projects/navig8r-dev/messages/123" });
  const fcmRequest = requests[1]!;
  const payload = JSON.parse(String(fcmRequest.init.body)) as { message: { notification: { title: string; body: string }; data: Record<string, string>; android: { ttl: string; priority: string; notification: { tag: string; channel_id: string } } } };
  assert.equal(payload.message.notification.title, "Shipment update");
  assert.equal(payload.message.notification.body, "There is an update for a shipment.");
  assert.equal(payload.message.android.notification.tag, "stable-key");
  assert.equal(payload.message.android.notification.channel_id, "shipment_updates");
  assert.equal(payload.message.android.ttl, "90s");
  assert.equal(payload.message.data.notificationId, "note-1");
  assert.equal(JSON.stringify(payload.message.notification).includes("raw-token-for-test"), false);
  assert.equal(JSON.stringify(payload.message.data).includes("raw-token-for-test"), false);
  assert.ok(fcmRequest.init.signal instanceof AbortSignal);
});

test.after(() => {
  for (const [key, value] of Object.entries(env)) {
    const name = ({ registration: "PUSH_DEVICE_REGISTRATION_ENABLED", enqueue: "PUSH_ENQUEUE_ENABLED", environment: "PUSH_ENVIRONMENT", encryptionKey: "PUSH_TOKEN_ENCRYPTION_KEY", fcmServiceAccount: "FCM_SERVICE_ACCOUNT_JSON" } as const)[key as keyof typeof env];
    if (value == null) delete process.env[name]; else process.env[name] = value;
  }
});
