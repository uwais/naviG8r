import test from "node:test";
import assert from "node:assert/strict";
import { randomBytes } from "node:crypto";
import { httpFixture } from "../../../../test/httpFixtures.ts";
import { decryptPushToken } from "../push.ts";

const previous = {
  registration: process.env.PUSH_DEVICE_REGISTRATION_ENABLED,
  enqueue: process.env.PUSH_ENQUEUE_ENABLED,
  environment: process.env.PUSH_ENVIRONMENT,
  encryptionKey: process.env.PUSH_TOKEN_ENCRYPTION_KEY,
};

test("push registration and notification-open routes are bearer-scoped without selected-org trust", async t => {
  process.env.PUSH_DEVICE_REGISTRATION_ENABLED = "1";
  process.env.PUSH_ENQUEUE_ENABLED = "1";
  process.env.PUSH_ENVIRONMENT = "DEVELOPMENT";
  process.env.PUSH_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
  t.after(() => {
    const values = [
      ["PUSH_DEVICE_REGISTRATION_ENABLED", previous.registration],
      ["PUSH_ENQUEUE_ENABLED", previous.enqueue],
      ["PUSH_ENVIRONMENT", previous.environment],
      ["PUSH_TOKEN_ENCRYPTION_KEY", previous.encryptionKey],
    ] as const;
    for (const [key, value] of values) if (value == null) delete process.env[key]; else process.env[key] = value;
  });

  const f = await httpFixture(t);
  const installationId = "navig8r-installation-000000001";
  const tokenA = "fcm-token-for-http-test-user-a-123456789";
  const registered = await f.request("/v1/me/push-devices", "PUT", {
    installationId, token: tokenA, consented: true, permissionGranted: true, channelEnabled: true,
  }, f.tokens.shipperA, { "x-organization-id": "stale-unselected-org" });
  assert.equal(registered.status, 200);
  assert.equal(JSON.stringify(registered.body).includes(tokenA), false);
  const device = f.store.pushDevices.get(registered.body.deviceId)!;
  assert.equal(decryptPushToken(device.tokenCiphertext), tokenA);

  const booking = await f.book();
  assert.equal(booking.status, 201);
  const notification = [...f.store.notifications.values()].find(item => item.recipientUserId === f.shipperA.user.id && item.eventKey === "shipment.booked");
  assert.ok(notification);
  assert.equal([...f.store.pushIntents.values()].filter(intent => intent.notificationId === notification!.id).length, 1);
  assert.equal([...f.store.pushDeliveries.values()].filter(delivery => delivery.deviceId === device.id).length, 1);

  const opened = await f.request(`/v1/notifications/${notification.id}/open`, "POST", {}, f.tokens.shipperA, { "x-organization-id": f.shipperB.org.id });
  assert.equal(opened.status, 200);
  assert.equal(opened.body.organizationId, f.shipperA.org.id);
  assert.equal(opened.body.shipmentId, booking.body.shipment.id);
  const crossUser = await f.request(`/v1/notifications/${notification.id}/open`, "POST", {}, f.tokens.shipperB);
  assert.equal(crossUser.status, 404);

  const tokenB = "fcm-token-for-http-test-user-b-123456789";
  const reassigned = await f.request("/v1/me/push-devices", "PUT", {
    installationId, token: tokenB, consented: true, permissionGranted: true, channelEnabled: true,
  }, f.tokens.shipperB);
  assert.equal(reassigned.status, 200);
  assert.equal(reassigned.body.deviceId, device.id);
  assert.equal(reassigned.body.ownershipGeneration, registered.body.ownershipGeneration + 1);

  const staleRevoke = await f.request(`/v1/me/push-devices/${device.id}`, "DELETE", { ownershipGeneration: registered.body.ownershipGeneration }, f.tokens.shipperA);
  assert.equal(staleRevoke.status, 200);
  assert.equal(staleRevoke.body.revoked, false);
  const currentRevoke = await f.request(`/v1/me/push-devices/${device.id}`, "DELETE", { ownershipGeneration: reassigned.body.ownershipGeneration }, f.tokens.shipperB);
  assert.equal(currentRevoke.status, 200);
  assert.equal(currentRevoke.body.revoked, true);
  assert.equal(f.store.pushDevices.get(device.id)?.tokenCiphertext, "");
});
