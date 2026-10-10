import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { once } from "node:events";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";

const databaseUrl = process.env.NOTIFICATION_TEST_DATABASE_URL;
const disposableDatabaseUrl = databaseUrl &&
  /^postgres(?:ql)?:\/\/[^/]*127\.0\.0\.1(?::\d+)?\/navig8r_notification_test(?:\?.*)?$/.test(databaseUrl)
  ? databaseUrl
  : undefined;

test("PostgreSQL grouped inbox and conversation timeline preserve pagination and read snapshots", {
  skip: !databaseUrl,
}, async t => {
  assert.ok(disposableDatabaseUrl,
    "NOTIFICATION_TEST_DATABASE_URL must target 127.0.0.1/navig8r_notification_test");
  const previousDatabaseUrl = process.env.DATABASE_URL;
  const previousPersistence = process.env.PERSISTENCE;
  process.env.DATABASE_URL = disposableDatabaseUrl;
  process.env.PERSISTENCE = "FILE";

  const fixture = await httpFixture(t);
  const first = await fixture.book();
  const second = await fixture.book();
  assert.equal(first.status, 201);
  assert.equal(second.status, 201);
  const firstShipmentId = first.body.shipment.id as string;
  const secondShipmentId = second.body.shipment.id as string;

  const database = await import("./persistenceDb.ts");
  const existingStore = await database.loadStoreFromDatabase();
  let notificationSequence = existingStore.notificationSequence;
  for (const [id, notification] of [...fixture.store.notifications.entries()]
      .sort((a, b) => a[1].recipientSequence - b[1].recipientSequence)) {
    fixture.store.notifications.set(id, { ...notification, recipientSequence: ++notificationSequence });
  }
  fixture.store.notificationSequence = notificationSequence;
  await database.saveStoreToDatabase(fixture.store);
  process.env.PERSISTENCE = "DB";
  const app = await (await import("./httpServer.ts")).createApp();
  app.server.listen(0, "127.0.0.1");
  await once(app.server, "listening");
  const address = app.server.address();
  assert.ok(address && typeof address === "object");

  t.after(async () => {
    app.server.closeAllConnections();
    await new Promise<void>(resolve => app.server.close(() => resolve()));
    await database.closeDatabase();
    if (previousDatabaseUrl === undefined) delete process.env.DATABASE_URL;
    else process.env.DATABASE_URL = previousDatabaseUrl;
    if (previousPersistence === undefined) delete process.env.PERSISTENCE;
    else process.env.PERSISTENCE = previousPersistence;
  });

  const request = async (url: string, token = fixture.tokens.shipperA, method = "GET", body?: unknown) => {
    const response = await fetch(`http://127.0.0.1:${address.port}${url}`, {
      method,
      headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }),
    });
    return { status: response.status, body: await response.json() as Record<string, any> };
  };
  const firstPage = await request("/v1/notifications/shipments?limit=1");
  assert.equal(firstPage.status, 200);
  assert.equal(firstPage.body.unreadCount, 2);
  assert.equal(firstPage.body.shipments.length, 1);
  assert.ok(firstPage.body.nextBefore);

  const lateInboxMessage = await request(`/v1/shipments/${firstShipmentId}/conversation/messages`, fixture.tokens.shipperA, "POST", {
    body: "This activity arrived after the inbox snapshot.",
    clientRequestId: "notification-db-late-message",
  });
  assert.equal(lateInboxMessage.status, 201);

  const secondPage = await request(`/v1/notifications/shipments?limit=1&before=${encodeURIComponent(firstPage.body.nextBefore)}`);
  assert.equal(secondPage.status, 200);
  assert.equal(secondPage.body.notificationSequence, firstPage.body.notificationSequence);
  assert.equal(secondPage.body.unreadCount, firstPage.body.unreadCount);
  assert.equal(secondPage.body.shipments.length, 1);
  const pagedShipmentIds = [firstPage.body.shipments[0].shipmentId, secondPage.body.shipments[0].shipmentId];
  assert.deepEqual(new Set(pagedShipmentIds), new Set([firstShipmentId, secondShipmentId]));
  assert.equal(new Set(pagedShipmentIds).size, 2);

  const foreignInbox = await request("/v1/notifications/shipments", fixture.tokens.carrierB);
  assert.equal(foreignInbox.status, 200);
  assert.equal(foreignInbox.body.unreadCount, 0);
  assert.deepEqual(foreignInbox.body.shipments, []);

  // Seed mixed timeline rows directly so timestamp ties and legacy NULL conversation IDs
  // are deterministic in PostgreSQL rather than depending on wall-clock request timing.
  const conversationId = firstShipmentId;
  const conversation = app.store.conversations.get(conversationId);
  assert.ok(conversation);
  const tiedAt = Date.now() + 60_000;
  const eventAtTieId = randomUUID();
  const legacyEventId = randomUUID();
  const messageIds = [randomUUID(), randomUUID()].sort();
  const targetNotifications = [...app.store.notifications.values()]
    .filter(n => n.shipmentId === conversationId && n.recipientUserId === fixture.shipperA.user.id && n.recipientOrgId === fixture.shipperA.org.id);
  let nextNotificationSequence = app.store.notificationSequence;
  for (const notification of [
    {
      id: eventAtTieId,
      eventId: randomUUID(),
      eventKey: "shipment.carrier_accepted",
      createdAtUtcMs: tiedAt,
      conversationId,
      data: { title: "Carrier accepted", body: "The carrier accepted this shipment." },
    },
    {
      id: legacyEventId,
      eventId: randomUUID(),
      eventKey: "shipment.pod_submitted",
      createdAtUtcMs: tiedAt - 500,
      data: { title: "POD submitted", body: "Proof of delivery was submitted." },
    },
  ]) {
    app.store.notifications.set(notification.id, {
      ...notification,
      recipientSequence: ++nextNotificationSequence,
      recipientUserId: fixture.shipperA.user.id,
      recipientOrgId: fixture.shipperA.org.id,
      shipmentId: conversationId,
      readAtUtcMs: undefined,
    });
  }
  app.store.notificationSequence = nextNotificationSequence;
  const messageSequenceBase = [...app.store.conversationMessages.values()]
    .filter(message => message.conversationId === conversationId)
    .reduce((max, message) => Math.max(max, message.sequence), 0);
  for (const [index, id] of messageIds.entries()) {
    app.store.conversationMessages.set(id, {
      id,
      conversationId,
      sequence: messageSequenceBase + index + 1,
      senderUserId: fixture.shipperA.user.id,
      senderOrgId: fixture.shipperA.org.id,
      body: `Tied message ${index + 1}`,
      clientRequestId: `postgres-timeline-${index + 1}`,
      createdAtUtcMs: tiedAt,
    });
  }
  await app.persist();

  const timelinePath = `/v1/shipments/${conversationId}/conversation/timeline`;
  const firstTimelinePage = await request(`${timelinePath}?limit=1`);
  assert.equal(firstTimelinePage.status, 200);
  const readWatermark = firstTimelinePage.body.readWatermark as { notificationSequence: number; messageSequence: number };
  assert.equal(firstTimelinePage.body.items[0].type, "event");
  assert.equal(firstTimelinePage.body.items[0].id, eventAtTieId);
  assert.ok(firstTimelinePage.body.nextBefore);
  const decodeCursor = (cursor: string) => JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
  assert.equal(decodeCursor(firstTimelinePage.body.nextBefore).before.priority, 1);

  const lateMessage = await request(`/v1/shipments/${conversationId}/conversation/messages`, fixture.tokens.shipperA, "POST", {
    body: "After the timeline snapshot",
    clientRequestId: "notification-db-late-timeline-message",
  });
  assert.equal(lateMessage.status, 201);

  const pages = [firstTimelinePage.body.items[0]] as Array<{ id: string; type: string }>;
  let cursor: string | null = firstTimelinePage.body.nextBefore;
  const priorities: number[] = [decodeCursor(cursor!).before.priority];
  while (cursor) {
    const page = await request(`${timelinePath}?limit=1&before=${encodeURIComponent(cursor)}`);
    assert.equal(page.status, 200);
    assert.equal(page.body.readWatermark.notificationSequence, readWatermark.notificationSequence);
    assert.equal(page.body.readWatermark.messageSequence, readWatermark.messageSequence);
    pages.push(...page.body.items as Array<{ id: string; type: string }>);
    cursor = page.body.nextBefore as string | null;
    if (cursor) priorities.push(decodeCursor(cursor).before.priority);
    assert.ok(pages.length <= 10, "timeline cursor traversal should terminate");
  }
  assert.equal(new Set(pages.map(item => item.id)).size, pages.length, "timeline pages must not duplicate items");
  assert.deepEqual(pages.slice(0, 4).map(item => item.id), [
    eventAtTieId,
    messageIds[1],
    messageIds[0],
    legacyEventId,
  ]);
  assert.deepEqual(pages.slice(1, 3).map(item => item.type), ["message", "message"]);
  assert.ok(priorities.includes(1), "pagination should exercise an event-priority cursor");
  assert.ok(priorities.includes(0), "pagination should exercise a message-priority cursor");
  assert.ok(!pages.some(item => item.id === lateMessage.body.message.id), "continuation pages must exclude messages after the captured snapshot");
  assert.ok(pages.some(item => item.id === targetNotifications[0]?.id), "existing workflow event remains in the timeline");

  // The late message must remain outside the earlier read watermark, including after DB reload.
  const readResponse = await request(`/v1/shipments/${conversationId}/conversation/read`, fixture.tokens.shipperA, "POST", { readWatermark });
  assert.equal(readResponse.status, 200);

  const reloadedStore = await database.loadStoreFromDatabase();
  const persistedTimeline = [...reloadedStore.notifications.values()]
    .filter(n => n.shipmentId === conversationId && n.recipientUserId === fixture.shipperA.user.id && n.recipientOrgId === fixture.shipperA.org.id);
  assert.ok(persistedTimeline.find(n => n.id === eventAtTieId)?.readAtUtcMs != null, "events within the acknowledged notification watermark persist as read");
  assert.ok(persistedTimeline.find(n => n.id === legacyEventId)?.readAtUtcMs != null, "legacy events without a conversation ID also persist as read");
  const lateNotification = persistedTimeline.find(n => n.messageId === lateMessage.body.message.id);
  assert.ok(lateNotification);
  assert.equal(lateNotification.readAtUtcMs, undefined, "a notification created after the watermark remains unread");
  assert.equal(reloadedStore.conversationReadStates.get(`${conversationId}:${fixture.shipperA.user.id}:${fixture.shipperA.org.id}`)?.lastReadSequence, readWatermark.messageSequence);
});
