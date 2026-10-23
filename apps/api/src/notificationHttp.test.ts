import test from "node:test";
import assert from "node:assert/strict";
import { httpFixture } from "../test/httpFixtures.ts";
import { loadStoreFromDisk, saveStoreToDisk } from "./persistence.ts";
import { createApp } from "./httpServer.ts";

test("shipment messages notify all active shipper and carrier actors, including sender, with idempotent retries", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  assert.equal(booked.status, 201);
  const shipmentId = booked.body.shipment.id as string;
  const path = `/v1/shipments/${shipmentId}/conversation/messages`;
  const payload = { body: "Please confirm the pickup window.", clientRequestId: "req-0001" };

  assert.equal((await f.request(path, "POST", payload)).status, 401);
  const sent = await f.request(path, "POST", payload, f.tokens.shipperA);
  assert.equal(sent.status, 201);
  assert.equal(sent.body.message.sequence, 1);
  const retry = await f.request(path, "POST", payload, f.tokens.shipperA);
  assert.equal(retry.status, 200);
  assert.equal(retry.body.message.id, sent.body.message.id);
  assert.equal(retry.body.created, false);
  assert.equal((await f.request(path, "POST", { ...payload, body: "Changed after retry" }, f.tokens.shipperA)).status, 409);

  const shipperInbox = await f.request("/v1/notifications", "GET", undefined, f.tokens.shipperA);
  assert.equal(shipperInbox.status, 200);
  // The message only: the shipper who booked is not told of their own booking (owner, 21 Oct 2026).
  assert.equal(shipperInbox.body.unreadCount, 1);
  assert.ok(shipperInbox.body.notifications.some((item: { messageId?: string }) => item.messageId === sent.body.message.id));
  const carrierInbox = await f.request("/v1/notifications", "GET", undefined, f.tokens.carrierA);
  assert.equal(carrierInbox.body.unreadCount, 2);
  assert.ok(carrierInbox.body.notifications.some((item: { messageId?: string }) => item.messageId === sent.body.message.id));
  assert.equal((await f.request("/v1/notifications", "GET", undefined, f.tokens.shipperB)).body.unreadCount, 0);

  const carrierThread = await f.request(path, "GET", undefined, f.tokens.carrierA);
  assert.equal(carrierThread.status, 200);
  assert.equal(carrierThread.body.messages.length, 1);
  assert.equal((await f.request(path, "GET", undefined, f.tokens.carrierB)).status, 404);
  assert.equal((await f.request(path, "GET", undefined, f.tokens.ops)).status, 404);
  const messageNotification = carrierInbox.body.notifications.find((item: { messageId?: string }) => item.messageId === sent.body.message.id);
  const marked = await f.request(`/v1/notifications/${messageNotification.id}/read`, "PATCH", {}, f.tokens.carrierA);
  assert.equal(marked.status, 200, JSON.stringify({ marked, messageNotification }));
  assert.equal((await f.request("/v1/notifications", "GET", undefined, f.tokens.carrierA)).body.unreadCount, 1);

  const restored = loadStoreFromDisk(f.dataFilePath!);
  assert.equal(restored.conversationMessages.size, 1);
  assert.equal(restored.notifications.size, 3);
});

test("flat notifications hide inactive shipments and cannot mark them read", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipmentId = booked.body.shipment.id as string;
  // The carrier's notice of the booking: the shipper who booked is not told of their own booking.
  const notification = [...f.store.notifications.values()].find(n =>
    n.shipmentId === shipmentId && n.recipientUserId === f.carrierA.user.id && n.recipientOrgId === f.carrierA.org.id);
  assert.ok(notification);

  f.store.shipments.set(shipmentId, {
    ...f.store.shipments.get(shipmentId)!,
    inactiveAtUtcMs: Date.now(),
    inactiveReason: "test_tombstone",
  });

  const inbox = await f.request("/v1/notifications", "GET", undefined, f.tokens.carrierA);
  assert.equal(inbox.status, 200);
  assert.equal(inbox.body.unreadCount, 0);
  assert.deepEqual(inbox.body.notifications, []);

  const markRead = await f.request(`/v1/notifications/${notification.id}/read`, "PATCH", undefined, f.tokens.carrierA);
  assert.equal(markRead.status, 404);
  assert.equal(f.store.notifications.get(notification.id)?.readAtUtcMs, undefined);
});

test("grouped inbox and conversation timeline keep workflow events beside messages with stable tie order and read watermarks", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipmentId = booked.body.shipment.id as string;
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  const timelinePath = `/v1/shipments/${shipmentId}/conversation/timeline`;
  await f.request(messagesPath, "POST", { body: "First reply", clientRequestId: "timeline-1" }, f.tokens.shipperA);

  const inbox = await f.request("/v1/notifications/shipments", "GET", undefined, f.tokens.shipperA);
  assert.equal(inbox.status, 200);
  assert.equal(inbox.body.shipments.length, 1);
  assert.equal(inbox.body.shipments[0].shipmentId, shipmentId);
  assert.equal(typeof inbox.body.shipments[0].shipmentReference, "string");
  assert.ok(inbox.body.shipments[0].unreadCount >= 1);

  // Create a workflow event at the same timestamp as a message; message sorts first.
  const message = [...f.store.conversationMessages.values()][0]!;
  const customerOrgId = f.store.shipments.get(shipmentId)!.customerOrgId;
  const event = [...f.store.notifications.values()].find(n => n.recipientOrgId === customerOrgId && n.messageId === message.id)!;
  for (const [id, row] of f.store.notifications) if (row.recipientUserId === event.recipientUserId && row.recipientOrgId === event.recipientOrgId && row.shipmentId === shipmentId) f.store.notifications.delete(id);
  f.store.notifications.set(event.id, { ...event, eventKey: "shipment.booked", messageId: undefined, conversationId: shipmentId, createdAtUtcMs: message.createdAtUtcMs, data: { title: "Load booked", body: "Carrier assigned." } });
  const tied = await f.request(timelinePath, "GET", undefined, f.tokens.shipperA);
  assert.equal(tied.status, 200);
  const tiedItems = tied.body.items as Array<{ type: string; id: string }>;
  const messageIndex = tiedItems.findIndex(item => item.type === "message");
  const eventIndex = tiedItems.findIndex(item => item.id === event.id);
  assert.ok(messageIndex >= 0 && eventIndex >= 0);
  assert.ok(messageIndex < eventIndex, "message should precede workflow event on exact timestamps");

  const first = await f.request(`${timelinePath}?limit=1`, "GET", undefined, f.tokens.shipperA);
  assert.equal(first.body.items.length, 1);
  assert.ok(first.body.nextBefore);
  assert.equal(first.body.items[0].type, "event");
  const older = await f.request(`${timelinePath}?limit=1&before=${encodeURIComponent(first.body.nextBefore)}`, "GET", undefined, f.tokens.shipperA);
  assert.equal(older.body.items.length, 1);
  assert.equal(older.body.items[0].type, "message", "the message is the older item at an exact timestamp tie");
  assert.equal((await f.request(timelinePath, "GET", undefined, f.tokens.shipperB)).status, 404);
  assert.equal((await f.request(`${timelinePath}?before=${encodeURIComponent(first.body.nextBefore)}`, "GET", undefined, f.tokens.carrierA)).status, 400, "a cursor cannot be reused by another recipient scope");

  const beforeNewMessage = tied.body.readWatermark;
  await f.request(messagesPath, "POST", { body: "Arrived after the view", clientRequestId: "timeline-2" }, f.tokens.carrierA);
  const acknowledged = await f.request(`/v1/shipments/${shipmentId}/conversation/read`, "POST", { readWatermark: beforeNewMessage }, f.tokens.shipperA);
  assert.equal(acknowledged.status, 200);
  const freshInbox = await f.request("/v1/notifications/shipments", "GET", undefined, f.tokens.shipperA);
  assert.ok(freshInbox.body.shipments[0].unreadCount >= 1, "new message notification remains unread after acknowledging the prior snapshot");
});

test("failed message and read persistence roll back all in-memory communication changes", async t => {
  let failNextPersistence = false;
  const f = await httpFixture(t, {
    beforeCommunicationPersist: () => {
      if (failNextPersistence) {
        failNextPersistence = false;
        throw new Error("injected communication persistence failure");
      }
    },
  });
  const booked = await f.book();
  const shipmentId = booked.body.shipment.id as string;
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  const messageCountBefore = f.store.conversationMessages.size;
  const notificationIdsBefore = new Set(f.store.notifications.keys());
  const notificationSequenceBefore = f.store.notificationSequence;

  failNextPersistence = true;
  const failedMessage = await f.request(messagesPath, "POST", {
    body: "This message must not remain in memory.",
    clientRequestId: "failed-message-persist",
  }, f.tokens.shipperA);
  assert.equal(failedMessage.status, 500);
  assert.equal(f.store.conversationMessages.size, messageCountBefore);
  assert.deepEqual(new Set(f.store.notifications.keys()), notificationIdsBefore);
  assert.equal(f.store.notificationSequence, notificationSequenceBefore);

  // A later unrelated successful save must not commit the failed message.
  await f.persist();
  assert.equal(f.store.conversationMessages.size, messageCountBefore);
  assert.deepEqual(new Set(f.store.notifications.keys()), notificationIdsBefore);

  const timeline = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA);
  assert.equal(timeline.status, 200);
  const unreadBefore = [...f.store.notifications.values()]
    .filter(n => n.recipientUserId === f.shipperA.user.id && n.shipmentId === shipmentId && n.readAtUtcMs == null).length;
  const readStatesBefore = new Map(f.store.conversationReadStates);

  failNextPersistence = true;
  const failedRead = await f.request(`/v1/shipments/${shipmentId}/conversation/read`, "POST", {
    readWatermark: timeline.body.readWatermark,
  }, f.tokens.shipperA);
  assert.equal(failedRead.status, 500);
  assert.deepEqual(new Map(f.store.conversationReadStates), readStatesBefore);
  assert.equal([...f.store.notifications.values()]
    .filter(n => n.recipientUserId === f.shipperA.user.id && n.shipmentId === shipmentId && n.readAtUtcMs == null).length, unreadBefore);

  await f.persist();
  assert.deepEqual(new Map(f.store.conversationReadStates), readStatesBefore);
  assert.equal([...f.store.notifications.values()]
    .filter(n => n.recipientUserId === f.shipperA.user.id && n.shipmentId === shipmentId && n.readAtUtcMs == null).length, unreadBefore);
});

test("a committed message remains idempotently retryable after the reply window closes", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipmentId = booked.body.shipment.id as string;
  const path = `/v1/shipments/${shipmentId}/conversation/messages`;
  const payload = { body: "Accepted before cutoff", clientRequestId: "cutoff-retry" };
  const sent = await f.request(path, "POST", payload, f.tokens.shipperA);
  assert.equal(sent.status, 201);
  const conversation = f.store.conversations.get(shipmentId)!;
  f.store.conversations.set(shipmentId, { ...conversation, replyUntilUtcMs: Date.now() - 1 });
  const retry = await f.request(path, "POST", payload, f.tokens.shipperA);
  assert.equal(retry.status, 200);
  assert.equal(retry.body.message.id, sent.body.message.id);
  assert.equal((await f.request(path, "POST", { body: "New after cutoff", clientRequestId: "after-cutoff" }, f.tokens.shipperA)).status, 409);
});

test("OPS conversation visibility requires a three-party approved escalation and is audited", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipmentId = booked.body.shipment.id as string;
  const url = `/v1/shipments/${shipmentId}/conversation/messages`;
  assert.equal((await f.request(url, "POST", { body: "Private thread content", clientRequestId: "msg-1" }, f.tokens.shipperA)).status, 201);
  const request = await f.request(`/v1/shipments/${shipmentId}/conversation/escalations`, "POST", {
    granteeUserId: f.ops.userId, reason: "Carrier requested help with booking", canRead: true, canSend: false,
    expiresAtUtcMs: Date.now() + 60_000,
  }, f.tokens.shipperA);
  assert.equal(request.status, 201);
  const grantId = request.body.grant.id as string;
  assert.equal((await f.request(`/v1/conversation-escalations/${grantId}/approve`, "POST", {}, f.tokens.ops)).status, 403);
  assert.equal((await f.request(url, "GET", undefined, f.tokens.ops)).status, 404);
  const timelineUrl = `/v1/shipments/${shipmentId}/conversation/timeline`;
  assert.equal((await f.request(timelineUrl, "GET", undefined, f.tokens.ops)).status, 404);
  assert.equal((await f.request(`/v1/conversation-escalations/${grantId}/approve`, "POST", {}, f.tokens.admin)).status, 200);
  const readOnlyMessages = await f.request(url, "GET", undefined, f.tokens.ops);
  assert.equal(readOnlyMessages.status, 200);
  assert.equal(readOnlyMessages.body.canSend, false, "the legacy endpoint reflects the approved read-only grant");
  const opsTimeline = await f.request(timelineUrl, "GET", undefined, f.tokens.ops);
  assert.equal(opsTimeline.status, 200);
  assert.equal(opsTimeline.body.canSend, false);
  assert.equal((await f.request(url, "POST", { body: "Not permitted", clientRequestId: "ops-read-only" }, f.tokens.ops)).status, 404);
  assert.equal(opsTimeline.body.items.some((item: { type: string }) => item.type === "event"), false);
  assert.ok([...f.store.auditEvents.values()].some(e => e.action === "CONVERSATION_SUPPORT_READ"));
  assert.equal(JSON.stringify([...f.store.auditEvents.values()]).includes("Private thread content"), false);
  assert.equal((await f.request(`/v1/conversation-escalations/${grantId}/revoke`, "POST", {}, f.tokens.shipperA)).status, 200);
  assert.equal((await f.request(url, "GET", undefined, f.tokens.ops)).status, 404);
  assert.ok([...f.store.auditEvents.values()].some(e => e.action === "CONVERSATION_ESCALATION_REVOKED"));
});

test("conversation sends are throttled per sender and resource", async t => {
  const previous = process.env.CONVERSATION_SENDS_PER_MINUTE;
  process.env.CONVERSATION_SENDS_PER_MINUTE = "2";
  t.after(() => { if (previous === undefined) delete process.env.CONVERSATION_SENDS_PER_MINUTE; else process.env.CONVERSATION_SENDS_PER_MINUTE = previous; });
  const f = await httpFixture(t);
  const booked = await f.book();
  const path = `/v1/shipments/${booked.body.shipment.id}/conversation/messages`;
  for (let i = 1; i <= 2; i++) assert.equal((await f.request(path, "POST", { body: `Message ${i}`, clientRequestId: `rate-${i}` }, f.tokens.shipperA)).status, 201);
  const limited = await f.request(path, "POST", { body: "Message 3", clientRequestId: "rate-3" }, f.tokens.shipperA);
  assert.equal(limited.status, 429);
  assert.equal(limited.body.error, "conversation_rate_limited");
});

test("terminal legacy shipments are read-only and invalid messages are rejected", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipment = f.store.shipments.get(booked.body.shipment.id)!;
  f.store.shipments.set(shipment.id, { ...shipment, status: "DELIVERED" });
  f.store.conversations.delete(shipment.id);
  const path = `/v1/shipments/${shipment.id}/conversation/messages`;
  assert.equal((await f.request(path, "POST", { body: "too late", clientRequestId: "late" }, f.tokens.shipperA)).status, 409);
  const result = await f.request(path, "GET", undefined, f.tokens.shipperA);
  assert.equal(result.status, 200, JSON.stringify(result.body));
  assert.equal(result.body.canSend, false);
  assert.equal(result.body.conversation.terminalAtUtcMs, undefined);
  const legacy = f.store.conversations.get(shipment.id)!;
  assert.equal(legacy.replyPolicyVersion, "legacy-terminal-read-only");
  assert.ok(legacy.replyUntilUtcMs! <= Date.now());
  assert.equal((await f.request(path, "POST", { body: "still closed", clientRequestId: "legacy-again" }, f.tokens.shipperA)).status, 409);
  assert.equal(f.store.conversations.get(shipment.id)?.replyUntilUtcMs, legacy.replyUntilUtcMs);
});

test("first terminal transition persists an immutable configurable conversation deadline", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipment = f.store.shipments.get(booked.body.shipment.id)!;
  const conversation = f.store.conversations.get(shipment.id)!;
  f.store.shipments.set(shipment.id, { ...shipment, status: "DELIVERED" });
  await f.persist();
  const closed = f.store.conversations.get(shipment.id)!;
  assert.ok(closed.terminalAtUtcMs! >= conversation.createdAtUtcMs);
  assert.equal(closed.replyUntilUtcMs! - closed.terminalAtUtcMs!, 14 * 24 * 60 * 60 * 1000);
  const deadline = closed.replyUntilUtcMs;
  await f.persist();
  assert.equal(f.store.conversations.get(shipment.id)?.replyUntilUtcMs, deadline);
});

test("workflow event catalog fanout covers acceptance, trip, POD, and payment changes", async t => {
  const f = await httpFixture(t);
  const booked = await f.book();
  const shipment = f.store.shipments.get(booked.body.shipment.id)!;
  const at = Date.now();
  f.store.shipments.set(shipment.id, { ...shipment, status: "BOOKED", acceptedAtUtcMs: at, podAtUtcMs: at, podAcceptedAtUtcMs: at });
  f.store.anchorTrips.set(f.trip.id, { ...f.trip, status: "IN_PROGRESS", startedAtUtcMs: at });
  const payment = f.store.payments.get(shipment.paymentId)!;
  f.store.payments.set(payment.id, { ...payment, status: "AUTHORIZED", updatedAtUtcMs: at });
  await f.persist();
  const events = [...f.store.notifications.values()].map(n => n.eventKey);
  for (const event of ["shipment.carrier_accepted", "shipment.pod_submitted", "shipment.pod_accepted", "trip.started", "payment.status_changed"]) assert.ok(events.includes(event), event);
  assert.equal([...f.store.notifications.values()].filter(n => n.eventKey === "trip.started").length, 2);
});

// Owner, 22 Oct 2026: "lock once the shipper accepts delivery". The shipment stays PENDING_RELEASE until NaviG8r
// releases payment, so acceptance itself closes replies, with no support window.
test("accepting proof of delivery makes the conversation read-only at once, for both sides", async t => {
  const previous = process.env.CONVERSATION_REPLY_WINDOW_DAYS;
  process.env.CONVERSATION_REPLY_WINDOW_DAYS = "30";
  t.after(() => { if (previous === undefined) delete process.env.CONVERSATION_REPLY_WINDOW_DAYS; else process.env.CONVERSATION_REPLY_WINDOW_DAYS = previous; });
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  const timelinePath = `/v1/shipments/${shipmentId}/conversation/timeline`;
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "PENDING_RELEASE", podAtUtcMs: Date.now() });
  await f.persist();
  assert.equal((await f.request(messagesPath, "POST", { body: "Delivered at the gate.", clientRequestId: "before-accept" }, f.tokens.carrierA)).status, 201, "replies are open while proof waits");
  assert.equal((await f.request(timelinePath, "GET", undefined, f.tokens.shipperA)).body.canSend, true);

  assert.equal((await f.request(`/shipments/${shipmentId}/accept-pod`, "POST", {}, f.tokens.shipperA)).status, 200);
  assert.equal(f.store.shipments.get(shipmentId)?.status, "PENDING_RELEASE");
  const locked = f.store.conversations.get(shipmentId)!;
  assert.equal(locked.replyPolicyVersion, "delivery-accepted-v1");
  assert.equal(locked.replyUntilUtcMs, f.store.shipments.get(shipmentId)!.podAcceptedAtUtcMs, "no window after acceptance, whatever CONVERSATION_REPLY_WINDOW_DAYS says");
  for (const token of [f.tokens.shipperA, f.tokens.carrierA]) {
    const timeline = await f.request(timelinePath, "GET", undefined, token);
    assert.equal(timeline.status, 200);
    assert.equal(timeline.body.canSend, false);
    assert.equal(timeline.body.items.some((item: { body: string }) => item.body === "Delivered at the gate."), true, "history stays readable");
    const late = await f.request(messagesPath, "POST", { body: "One more thing", clientRequestId: `after-accept-${token.slice(-6)}` }, token);
    assert.equal(late.status, 409);
    assert.equal(late.body.error, "conversation_read_only");
  }

  // Release after acceptance does not reopen it with a support window.
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "DELIVERED" });
  await f.persist();
  assert.equal(f.store.conversations.get(shipmentId)?.replyUntilUtcMs, locked.replyUntilUtcMs);
});

test("a conversation first opened after acceptance is read-only too", async t => {
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  const acceptedAt = Date.now() - 500;
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "PENDING_RELEASE", podAtUtcMs: Date.now() - 1000, podAcceptedAtUtcMs: acceptedAt });
  f.store.conversations.delete(shipmentId);
  const timeline = await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA);
  assert.equal(timeline.status, 200);
  assert.equal(timeline.body.canSend, false);
  assert.deepEqual(
    [timeline.body.conversation.replyPolicyVersion, timeline.body.conversation.replyUntilUtcMs, timeline.body.conversation.terminalAtUtcMs],
    ["delivery-accepted-v1", acceptedAt, acceptedAt],
    "it carries the acceptance, so the app can say when messages closed",
  );
});

test("after acceptance NaviG8r support with an approved grant can still reply; the shipper and carrier cannot", async t => {
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  const messagesPath = `/v1/shipments/${shipmentId}/conversation/messages`;
  const timelinePath = `/v1/shipments/${shipmentId}/conversation/timeline`;
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "PENDING_RELEASE", podAtUtcMs: Date.now() - 1000 });
  await f.persist();
  assert.equal((await f.request(`/shipments/${shipmentId}/accept-pod`, "POST", {}, f.tokens.shipperA)).status, 200);
  assert.equal(f.store.conversations.get(shipmentId)!.replyPolicyVersion, "delivery-accepted-v1");

  // The shipper reports damage found after accepting, and asks NaviG8r to step in.
  const request = await f.request(`/v1/shipments/${shipmentId}/conversation/escalations`, "POST", {
    granteeUserId: f.ops.userId, reason: "Damage found after accepting delivery", canRead: true, canSend: true, expiresAtUtcMs: Date.now() + 60_000,
  }, f.tokens.shipperA);
  assert.equal(request.status, 201);
  const opsBeforeApproval = await f.request(messagesPath, "POST", { body: "Too early", clientRequestId: "ops-early" }, f.tokens.ops);
  assert.equal(opsBeforeApproval.status, 404, "no grant, no reply");
  assert.equal((await f.request(`/v1/conversation-escalations/${request.body.grant.id}/approve`, "POST", {}, f.tokens.admin)).status, 200);

  assert.equal((await f.request(timelinePath, "GET", undefined, f.tokens.ops)).body.canSend, true);
  assert.equal((await f.request(messagesPath, "POST", { body: "We are looking into the damage.", clientRequestId: "ops-after-accept" }, f.tokens.ops)).status, 201);
  for (const token of [f.tokens.shipperA, f.tokens.carrierA]) {
    assert.equal((await f.request(timelinePath, "GET", undefined, token)).body.canSend, false);
    const late = await f.request(messagesPath, "POST", { body: "Reply", clientRequestId: `late-${token.slice(-6)}` }, token);
    assert.deepEqual([late.status, late.body.error], [409, "conversation_read_only"]);
  }
});

test("a chat recorded before the acceptance rule is locked at server start", async t => {
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  const acceptedAt = Date.now() - 60_000;
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "DELIVERED", podAtUtcMs: acceptedAt - 1000, podAcceptedAtUtcMs: acceptedAt });
  // As an older server saved it: released, with a 14-day support window running past the acceptance.
  f.store.conversations.set(shipmentId, { ...f.store.conversations.get(shipmentId)!, terminalAtUtcMs: acceptedAt + 1000, replyUntilUtcMs: acceptedAt + 14 * 24 * 60 * 60 * 1000, replyPolicyVersion: "support-window-v1" });
  saveStoreToDisk(f.dataFilePath!, f.store);

  const restarted = await createApp({ dataFilePath: f.dataFilePath! });
  const locked = restarted.store.conversations.get(shipmentId)!;
  assert.deepEqual([locked.replyPolicyVersion, locked.replyUntilUtcMs, locked.terminalAtUtcMs], ["delivery-accepted-v1", acceptedAt, acceptedAt]);
});

test("a chat that closed before the shipper accepted keeps its own closing time", async t => {
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  const closedAt = Date.now() - 60_000;
  f.store.conversations.set(shipmentId, { ...f.store.conversations.get(shipmentId)!, terminalAtUtcMs: closedAt - 1000, replyUntilUtcMs: closedAt, replyPolicyVersion: "support-window-v1" });
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "DELIVERED", podAtUtcMs: closedAt - 2000, podAcceptedAtUtcMs: closedAt + 1000 });
  await f.persist();
  assert.equal(f.store.conversations.get(shipmentId)!.replyUntilUtcMs, closedAt);
  assert.equal(f.store.conversations.get(shipmentId)!.replyPolicyVersion, "support-window-v1");
});

test("a shipment released without acceptance keeps the configured support window", async t => {
  const previous = process.env.CONVERSATION_REPLY_WINDOW_DAYS;
  process.env.CONVERSATION_REPLY_WINDOW_DAYS = "3";
  t.after(() => { if (previous === undefined) delete process.env.CONVERSATION_REPLY_WINDOW_DAYS; else process.env.CONVERSATION_REPLY_WINDOW_DAYS = previous; });
  const f = await httpFixture(t);
  const shipmentId = (await f.book()).body.shipment.id as string;
  f.store.shipments.set(shipmentId, { ...f.store.shipments.get(shipmentId)!, status: "DELIVERED", podAtUtcMs: Date.now() });
  await f.persist();
  const closed = f.store.conversations.get(shipmentId)!;
  assert.equal(closed.replyPolicyVersion, "support-window-v1");
  assert.equal(closed.replyUntilUtcMs! - closed.terminalAtUtcMs!, 3 * 24 * 60 * 60 * 1000);
  assert.equal((await f.request(`/v1/shipments/${shipmentId}/conversation/timeline`, "GET", undefined, f.tokens.shipperA)).body.canSend, true);
});
