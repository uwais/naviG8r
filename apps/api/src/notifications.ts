import { randomUUID } from "node:crypto";
import { effectivePermissions, legacyRoles, principalFor, recordAudit, requirePermission, type Principal } from "./rbac.ts";
import { isActiveEntity } from "./softDelete.ts";
import type { Store } from "./store.ts";
import type { Conversation, ConversationEscalationGrant, ConversationMessage, Notification, Shipment } from "./types.ts";

const MAX_MESSAGE_LENGTH = 4000;
const DEFAULT_REPLY_WINDOW_DAYS = 14;
const DEFAULT_MESSAGES_PER_MINUTE = 20;
const POLICY_VERSION = "support-window-v1";

export class CommunicationError extends Error {
  status: number;
  retryAfterMs?: number;
  constructor(message: string, status = 400, retryAfterMs?: number) { super(message); this.status = status; this.retryAfterMs = retryAfterMs; }
}

type WorkflowSnapshot = {
  shipments: Map<string, { status: string; podAt?: number | null; podAcceptedAt?: number; customerOrgId?: string; carrierId: string }>;
  trips: Map<string, { status: string; startedAt?: number; completedAt?: number; carrierId: string }>;
  payments: Map<string, { status: string; shipmentId: string; updatedAt: number }>;
};

export function workflowSnapshot(store: Store): WorkflowSnapshot {
  return {
    shipments: new Map([...store.shipments].map(([id, s]) => [id, { status: s.status, podAt: s.podAtUtcMs, podAcceptedAt: s.podAcceptedAtUtcMs, customerOrgId: s.customerOrgId, carrierId: s.carrierId }])),
    trips: new Map([...store.anchorTrips].map(([id, t]) => [id, { status: t.status, startedAt: t.startedAtUtcMs, completedAt: t.completedAtUtcMs, carrierId: t.carrierId }])),
    payments: new Map([...store.payments].map(([id, p]) => [id, { status: p.status, shipmentId: p.shipmentId, updatedAt: p.updatedAtUtcMs }])),
  };
}

export function captureWorkflowNotifications(store: Store, previous: WorkflowSnapshot): void {
  const emit = (shipment: Shipment | undefined, eventKey: string, occurredAt: number, sourceTransitionId?: string) => {
    if (!shipment) return;
    getOrCreateConversation(store, shipment);
    createNotifications(store, shipment, sourceTransitionId ?? `${eventKey}:${shipment.id}:${occurredAt}`, eventKey, occurredAt);
  };
  for (const [id, shipment] of store.shipments) {
    const old = previous.shipments.get(id);
    if (!old) emit(shipment, "shipment.booked", shipment.createdAtUtcMs);
    else if (old.status !== "BOOKED" && shipment.status === "BOOKED") emit(shipment, "shipment.carrier_accepted", shipment.acceptedAtUtcMs ?? shipment.updatedAtUtcMs);
    if ((!old?.podAt || old.podAt === 0) && shipment.podAtUtcMs) emit(shipment, "shipment.pod_submitted", shipment.podAtUtcMs);
    if (!old?.podAcceptedAt && shipment.podAcceptedAtUtcMs) emit(shipment, "shipment.pod_accepted", shipment.podAcceptedAtUtcMs);
  }
  for (const [id, trip] of store.anchorTrips) {
    const old = previous.trips.get(id);
    if (!old) continue;
    if (!old.startedAt && trip.startedAtUtcMs) {
      for (const shipment of store.shipments.values()) if (shipment.anchorTripId === id) emit(shipment, "trip.started", trip.startedAtUtcMs);
    }
    if (old.status !== "COMPLETED" && trip.status === "COMPLETED") {
      for (const shipment of store.shipments.values()) if (shipment.anchorTripId === id) emit(shipment, "trip.completed", trip.completedAtUtcMs ?? Date.now());
    }
  }
  for (const [id, payment] of store.payments) {
    const old = previous.payments.get(id);
    if (old && old.status !== payment.status) emit(
      store.shipments.get(payment.shipmentId),
      "payment.status_changed",
      payment.updatedAtUtcMs,
      `payment:${id}:${old.status}->${payment.status}:${payment.updatedAtUtcMs}`,
    );
  }
  Object.assign(previous, workflowSnapshot(store));
}

function getShipment(store: Store, shipmentId: string): Shipment {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment || !isActiveEntity(shipment)) throw new CommunicationError("shipment_not_found", 404);
  return shipment;
}

function eligibleActor(store: Store, userId: string, orgId: string, kind: "SHIPPER" | "CARRIER"): boolean {
  const user = store.users.get(userId), org = store.organizations.get(orgId);
  const membership = store.memberships.get(`${userId}:${orgId}`);
  if (!isActiveEntity(user) || !isActiveEntity(org) || !isActiveEntity(membership)) return false;
  const roles = (store.membershipRoles.get(`${userId}:${orgId}`) ?? legacyRoles(membership!, org!));
  return roles.includes(kind) && effectivePermissions(roles, membership!.role).includes("notification.read");
}

function requireShipmentActor(store: Store, shipment: Shipment, action: "conversation.read" | "conversation.send"): Principal {
  const principal = principalFor(store);
  if (principal.roles.includes("OPS")) {
    const requiredPermission = action === "conversation.read" ? "conversation.support_read" : "conversation.support_send";
    if (!principal.permissions.includes(requiredPermission)) throw new CommunicationError("not_found", 404);
    const grant = [...store.conversationEscalationGrants.values()].find(g => g.conversationId === shipment.id && g.granteeUserId === principal.userId && g.approvedAtUtcMs != null && g.revokedAtUtcMs == null && g.expiresAtUtcMs > Date.now() && (action === "conversation.read" ? g.canRead : g.canSend));
    if (!grant) throw new CommunicationError("not_found", 404);
    recordAudit(store, action === "conversation.read" ? "CONVERSATION_SUPPORT_READ" : "CONVERSATION_SUPPORT_SEND", "conversation", shipment.id);
    return principal;
  }
  if (!principal.permissions.includes(action) || !(principal.roles.includes("SHIPPER") || principal.roles.includes("CARRIER"))) throw new CommunicationError("forbidden", 403);
  const orgId = principal.organizationId;
  const belongs = principal.roles.includes("SHIPPER") ? shipment.customerOrgId === orgId : shipment.carrierId === orgId;
  if (!belongs) throw new CommunicationError("not_found", 404);
  return principal;
}

function getOrCreateConversation(store: Store, shipment: Shipment): Conversation {
  const current = store.conversations.get(shipment.id);
  if (current) return current;
  const now = Date.now();
  const terminal = shipment.status === "DELIVERED" || shipment.status === "FAILED_CARRIER_REFUNDED";
  const conversation: Conversation = {
    id: shipment.id, shipmentId: shipment.id, createdAtUtcMs: now, updatedAtUtcMs: now,
    ...(terminal ? { replyUntilUtcMs: now, replyPolicyVersion: "legacy-terminal-read-only" } : {}),
  };
  store.conversations.set(conversation.id, conversation);
  return conversation;
}

export function captureTerminalConversationWindows(store: Store, now = Date.now()): void {
  for (const [id, conversation] of store.conversations) {
    if (conversation.terminalAtUtcMs != null || conversation.replyPolicyVersion === "legacy-terminal-read-only") continue;
    const shipment = store.shipments.get(conversation.shipmentId);
    if (!shipment || !["DELIVERED", "FAILED_CARRIER_REFUNDED"].includes(shipment.status)) continue;
    const configuredDays = Number(process.env.CONVERSATION_REPLY_WINDOW_DAYS ?? DEFAULT_REPLY_WINDOW_DAYS);
    const replyWindowDays = Number.isFinite(configuredDays) && configuredDays >= 0 ? configuredDays : DEFAULT_REPLY_WINDOW_DAYS;
    store.conversations.set(id, {
      ...conversation, updatedAtUtcMs: now, terminalAtUtcMs: now,
      replyUntilUtcMs: now + replyWindowDays * 24 * 60 * 60 * 1000,
      replyPolicyVersion: POLICY_VERSION,
    });
  }
}

function notificationRecipients(store: Store, shipment: Shipment): Array<{ userId: string; orgId: string; role: "SHIPPER" | "CARRIER" }> {
  const recipients: Array<{ userId: string; orgId: string; role: "SHIPPER" | "CARRIER" }> = [];
  const orgs: Array<[string | undefined, "SHIPPER" | "CARRIER"]> = [[shipment.customerOrgId, "SHIPPER"], [shipment.carrierId, "CARRIER"]];
  for (const [orgId, role] of orgs) {
    if (!orgId) continue;
    for (const membership of store.memberships.values()) {
      if (membership.orgId === orgId && eligibleActor(store, membership.userId, orgId, role)) recipients.push({ userId: membership.userId, orgId, role });
    }
  }
  return recipients;
}

function createNotifications(store: Store, shipment: Shipment, eventId: string, eventKey: string, createdAtUtcMs: number, messageId?: string): void {
  const conversationId = shipment.id;
  for (const recipient of notificationRecipients(store, shipment)) {
    const duplicate = [...store.notifications.values()].some(n => n.eventId === eventId && n.recipientUserId === recipient.userId && n.recipientOrgId === recipient.orgId);
    if (duplicate) continue;
    const notification: Notification = {
      id: randomUUID(), recipientSequence: ++store.notificationSequence,
      eventId, eventKey, recipientUserId: recipient.userId, recipientOrgId: recipient.orgId,
      shipmentId: shipment.id, conversationId, ...(messageId ? { messageId } : {}), createdAtUtcMs,
      data: { shipmentId: shipment.id, audience: recipient.role, title: notificationTitle(eventKey, recipient.role), body: notificationBody(eventKey, recipient.role) },
    };
    store.notifications.set(notification.id, notification);
  }
}

function notificationTitle(eventKey: string, role: "SHIPPER" | "CARRIER"): string {
  const titles: Record<string, [string, string]> = {
    "shipment.booked": ["Load booked", "New shipper load"],
    "shipment.carrier_accepted": ["Carrier accepted", "Load accepted"],
    "trip.started": ["Trip started", "Trip started"],
    "trip.completed": ["Trip completed", "Trip completed"],
    "shipment.pod_submitted": ["Proof of delivery submitted", "Proof of delivery submitted"],
    "shipment.pod_accepted": ["Proof of delivery accepted", "Proof of delivery accepted"],
    "payment.status_changed": ["Payment status updated", "Payment status updated"],
    "conversation.message": ["New shipment message", "New shipment message"],
  };
  const values = titles[eventKey] ?? ["Shipment update", "Shipment update"];
  return values[role === "SHIPPER" ? 0 : 1];
}

function notificationBody(eventKey: string, role: "SHIPPER" | "CARRIER"): string {
  const bodies: Record<string, [string, string]> = {
    "shipment.booked": ["A load was booked for your organization.", "A shipper booked a load with your organization."],
    "shipment.carrier_accepted": ["The carrier accepted your load.", "Your organization accepted a load."],
    "trip.started": ["The carrier started the trip.", "A trip for this load has started."],
    "trip.completed": ["The trip for your load is complete.", "The trip for this load is complete."],
    "shipment.pod_submitted": ["The carrier submitted proof of delivery.", "Proof of delivery was submitted."],
    "shipment.pod_accepted": ["Proof of delivery was accepted.", "The shipper accepted proof of delivery."],
    "payment.status_changed": ["A payment status for this load changed.", "A payment status for this load changed."],
    "conversation.message": ["A participant added a message to the shipment conversation.", "A participant added a message to the shipment conversation."],
  };
  const values = bodies[eventKey] ?? ["There is an update for this shipment.", "There is an update for this shipment."];
  return values[role === "SHIPPER" ? 0 : 1];
}

export function listNotifications(store: Store, limit = 30, before?: string) {
  const principal = principalFor(store);
  requirePermission(store, "notification.read");
  const pageSize = Math.max(1, Math.min(100, Number.isFinite(limit) ? Math.trunc(limit) : 30));
  const all = [...store.notifications.values()].filter(n => n.recipientUserId === principal.userId && n.recipientOrgId === principal.organizationId)
    .filter(n => {
      const shipment = store.shipments.get(n.shipmentId);
      if (!shipment || !isActiveEntity(shipment)) return false;
      try { requireShipmentActor(store, shipment, "conversation.read"); return true; } catch { return false; }
    }).sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs || b.id.localeCompare(a.id));
  const filtered = before ? all.filter(n => `${n.createdAtUtcMs}:${n.id}` < before) : all;
  const items = filtered.slice(0, pageSize);
  const cursor = filtered.length > pageSize && items.length ? `${items[items.length - 1]!.createdAtUtcMs}:${items[items.length - 1]!.id}` : null;
  return { notifications: items, nextCursor: cursor, unreadCount: all.filter(n => n.readAtUtcMs == null).length };
}

type TimelineItem =
  | { type: "message"; id: string; createdAtUtcMs: number; sequence: number; senderUserId: string; senderOrgId: string; body: string }
  | { type: "event"; id: string; createdAtUtcMs: number; recipientSequence: number; eventKey: string; title: string; body: string; readAtUtcMs?: number };
type TimelineKey = { createdAtUtcMs: number; priority: number; id: string };
type TimelineCursor = {
  v: 1; userId: string; orgId: string; shipmentId: string; limit: number;
  notificationSequence: number; messageSequence: number; before: TimelineKey;
};
export type TimelinePageRequest = {
  conversationId: string; shipmentId: string; userId: string; orgId: string; limit: number;
  notificationSequence?: number; messageSequence?: number; before?: TimelineKey;
};
export type TimelinePageSource = {
  messages: ConversationMessage[]; notifications: Notification[];
  notificationSequence: number; messageSequence: number;
};
export type TimelinePageReader = (request: TimelinePageRequest) => Promise<TimelinePageSource>;

export type GroupedInboxPageRequest = {
  userId: string;
  orgId: string;
  isShipper: boolean;
  isCarrier: boolean;
  limit: number;
  notificationSequence?: number;
  before?: { latestAt: number; shipmentId: string };
};
export type GroupedInboxPageSource = {
  notificationSequence: number;
  unreadCount: number;
  groups: Array<{ shipmentId: string; latestAtUtcMs: number; unreadCount: number; shipmentReference: string }>;
};
export type GroupedInboxPageReader = (request: GroupedInboxPageRequest) => Promise<GroupedInboxPageSource>;

function compareIdBytes(a: string, b: string): number {
  return Buffer.compare(Buffer.from(a, "utf8"), Buffer.from(b, "utf8"));
}

function timelinePriority(item: TimelineItem): number { return item.type === "message" ? 0 : 1; }
function compareTimelineKeys(a: TimelineKey, b: TimelineKey): number {
  return a.createdAtUtcMs - b.createdAtUtcMs || a.priority - b.priority || compareIdBytes(a.id, b.id);
}
function keyForTimelineItem(item: TimelineItem): TimelineKey {
  return { createdAtUtcMs: item.createdAtUtcMs, priority: timelinePriority(item), id: item.id };
}
function encodeOpaque(value: object): string { return Buffer.from(JSON.stringify(value)).toString("base64url"); }
function decodeTimelineCursor(raw: string, expected: Omit<TimelineCursor, "before" | "notificationSequence" | "messageSequence">): TimelineCursor {
  try {
    const parsed = JSON.parse(Buffer.from(raw, "base64url").toString("utf8")) as TimelineCursor;
    if (parsed.v !== 1 || parsed.userId !== expected.userId || parsed.orgId !== expected.orgId || parsed.shipmentId !== expected.shipmentId || parsed.limit !== expected.limit || !Number.isSafeInteger(parsed.notificationSequence) || parsed.notificationSequence < 0 || !Number.isSafeInteger(parsed.messageSequence) || parsed.messageSequence < 0 || !Number.isSafeInteger(parsed.before?.createdAtUtcMs) || parsed.before.createdAtUtcMs < 0 || ![0, 1].includes(parsed.before?.priority) || typeof parsed.before?.id !== "string" || !/^[0-9a-f-]{36}$/i.test(parsed.before.id)) throw new Error();
    return parsed;
  } catch { throw new CommunicationError("invalid_timeline_cursor", 400); }
}

function canPrincipalSend(store: Store, shipment: Shipment, conversation: Conversation, principal: Principal): boolean {
  if (conversation.replyUntilUtcMs != null && Date.now() >= conversation.replyUntilUtcMs) return false;
  if (principal.roles.includes("OPS")) {
    return principal.permissions.includes("conversation.support_send") && [...store.conversationEscalationGrants.values()].some(g => g.conversationId === shipment.id && g.granteeUserId === principal.userId && g.approvedAtUtcMs != null && g.revokedAtUtcMs == null && g.expiresAtUtcMs > Date.now() && g.canSend);
  }
  return (principal.roles.includes("SHIPPER") || principal.roles.includes("CARRIER")) && principal.permissions.includes("conversation.send");
}

export async function listConversationTimeline(store: Store, shipmentId: string, limit = 50, before?: string, readPage?: TimelinePageReader) {
  const shipment = getShipment(store, shipmentId);
  const principal = requireShipmentActor(store, shipment, "conversation.read");
  const conversation = getOrCreateConversation(store, shipment);
  const pageSize = Math.max(1, Math.min(100, Number.isFinite(limit) ? Math.trunc(limit) : 50));
  const cursorScope = { v: 1 as const, userId: principal.userId, orgId: principal.organizationId, shipmentId, limit: pageSize };
  const decoded = before ? decodeTimelineCursor(before, cursorScope) : undefined;
  const snapshot = readPage
    ? await readPage({ conversationId: conversation.id, shipmentId, userId: principal.userId, orgId: principal.organizationId, limit: pageSize, ...(decoded ? { notificationSequence: decoded.notificationSequence, messageSequence: decoded.messageSequence, before: decoded.before } : {}) })
    : {
      notificationSequence: decoded?.notificationSequence ?? store.notificationSequence,
      messageSequence: decoded?.messageSequence ?? [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id).reduce((max, m) => Math.max(max, m.sequence), 0),
      messages: [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id),
      notifications: [...store.notifications.values()].filter(n => n.conversationId === conversation.id || (n.conversationId == null && n.shipmentId === shipmentId)),
    };
  const notificationSequence = decoded?.notificationSequence ?? snapshot.notificationSequence;
  const messageSequence = decoded?.messageSequence ?? snapshot.messageSequence;
  const messages: TimelineItem[] = snapshot.messages
    .filter(m => m.conversationId === conversation.id && m.sequence <= messageSequence)
    .map(m => ({ type: "message", id: m.id, createdAtUtcMs: m.createdAtUtcMs, sequence: m.sequence, senderUserId: m.senderUserId, senderOrgId: m.senderOrgId, body: m.body }));
  const events: TimelineItem[] = principal.roles.includes("OPS") ? [] : snapshot.notifications
    .filter(n => n.recipientUserId === principal.userId && n.recipientOrgId === principal.organizationId && n.shipmentId === shipmentId && (n.conversationId === conversation.id || n.conversationId == null) && n.recipientSequence <= notificationSequence && n.eventKey !== "conversation.message")
    .map(n => ({ type: "event", id: n.id, createdAtUtcMs: n.createdAtUtcMs, recipientSequence: n.recipientSequence, eventKey: n.eventKey, title: String(n.data?.title ?? "Shipment update"), body: String(n.data?.body ?? "There is an update for this shipment."), ...(n.readAtUtcMs == null ? {} : { readAtUtcMs: n.readAtUtcMs }) }));
  const all = [...messages, ...events];
  const eligible = decoded ? all.filter(item => compareTimelineKeys(keyForTimelineItem(item), decoded.before) < 0) : all;
  eligible.sort((a, b) => compareTimelineKeys(keyForTimelineItem(b), keyForTimelineItem(a)));
  const selectedDescending = eligible.slice(0, pageSize + 1);
  const hasMore = selectedDescending.length > pageSize;
  const items = selectedDescending.slice(0, pageSize).reverse();
  const oldest = items[0];
  const nextBefore = hasMore && oldest ? encodeOpaque({ ...cursorScope, notificationSequence, messageSequence, before: keyForTimelineItem(oldest) }) : null;
  return {
    conversation, items, nextBefore,
    readWatermark: { notificationSequence, messageSequence },
    canSend: canPrincipalSend(store, shipment, conversation, principal),
  };
}

export async function listGroupedNotifications(store: Store, limit = 30, before?: string, readPage?: GroupedInboxPageReader) {
  const principal = principalFor(store);
  requirePermission(store, "notification.read");
  if (!(principal.roles.includes("SHIPPER") || principal.roles.includes("CARRIER"))) throw new CommunicationError("forbidden", 403);
  const pageSize = Math.max(1, Math.min(100, Number.isFinite(limit) ? Math.trunc(limit) : 30));
  const cursorScope = { v: 1 as const, userId: principal.userId, orgId: principal.organizationId, limit: pageSize };
  let notificationSequence = store.notificationSequence;
  let cursor: { latestAt: number; shipmentId: string } | undefined;
  if (before) {
    try {
      const parsed = JSON.parse(Buffer.from(before, "base64url").toString("utf8")) as typeof cursorScope & { notificationSequence: number; latestAt: number; shipmentId: string };
      if (parsed.v !== 1 || parsed.userId !== cursorScope.userId || parsed.orgId !== cursorScope.orgId || parsed.limit !== pageSize || !Number.isSafeInteger(parsed.notificationSequence) || !Number.isSafeInteger(parsed.latestAt) || typeof parsed.shipmentId !== "string") throw new Error();
      notificationSequence = parsed.notificationSequence;
      cursor = { latestAt: parsed.latestAt, shipmentId: parsed.shipmentId };
    } catch { throw new CommunicationError("invalid_notification_cursor", 400); }
  }
  if (readPage) {
    const page = await readPage({
      userId: principal.userId,
      orgId: principal.organizationId,
      isShipper: principal.roles.includes("SHIPPER"),
      isCarrier: principal.roles.includes("CARRIER"),
      limit: pageSize,
      ...(before ? { notificationSequence, before: cursor } : {}),
    });
    const hasMore = page.groups.length > pageSize;
    const shipments = page.groups.slice(0, pageSize);
    const last = shipments.at(-1);
    const nextBefore = hasMore && last
      ? encodeOpaque({ ...cursorScope, notificationSequence: page.notificationSequence, latestAt: last.latestAtUtcMs, shipmentId: last.shipmentId })
      : null;
    return { shipments, nextBefore, unreadCount: page.unreadCount, notificationSequence: page.notificationSequence };
  }
  const groups = new Map<string, { shipmentId: string; latestAtUtcMs: number; unreadCount: number }>();
  for (const n of store.notifications.values()) {
    if (n.recipientUserId !== principal.userId || n.recipientOrgId !== principal.organizationId || n.recipientSequence > notificationSequence) continue;
    const shipment = store.shipments.get(n.shipmentId);
    if (!shipment || !isActiveEntity(shipment)) continue;
    const belongs = (principal.roles.includes("SHIPPER") && shipment.customerOrgId === principal.organizationId) || (principal.roles.includes("CARRIER") && shipment.carrierId === principal.organizationId);
    if (!belongs) continue;
    const group = groups.get(n.shipmentId) ?? { shipmentId: n.shipmentId, latestAtUtcMs: n.createdAtUtcMs, unreadCount: 0 };
    group.latestAtUtcMs = Math.max(group.latestAtUtcMs, n.createdAtUtcMs);
    if (n.readAtUtcMs == null) group.unreadCount++;
    groups.set(n.shipmentId, group);
  }
  const ordered = [...groups.values()].sort((a, b) => b.latestAtUtcMs - a.latestAtUtcMs || compareIdBytes(b.shipmentId, a.shipmentId));
  const afterCursor = cursor ? ordered.filter(g => g.latestAtUtcMs < cursor!.latestAt || (g.latestAtUtcMs === cursor!.latestAt && compareIdBytes(g.shipmentId, cursor!.shipmentId) < 0)) : ordered;
  const selected = afterCursor.slice(0, pageSize + 1);
  const hasMore = selected.length > pageSize;
  const shipments = selected.slice(0, pageSize).map(group => {
    const shipment = store.shipments.get(group.shipmentId)!;
    return { ...group, shipmentReference: shipment.externalLoadId ?? group.shipmentId.slice(0, 8).toUpperCase() };
  });
  const last = shipments.at(-1);
  const nextBefore = hasMore && last ? encodeOpaque({ ...cursorScope, notificationSequence, latestAt: last.latestAtUtcMs, shipmentId: last.shipmentId }) : null;
  return { shipments, nextBefore, unreadCount: ordered.reduce((n, g) => n + g.unreadCount, 0), notificationSequence };
}

export function markConversationRead(store: Store, shipmentId: string, watermark: { notificationSequence: number; messageSequence: number }) {
  const shipment = getShipment(store, shipmentId);
  const principal = requireShipmentActor(store, shipment, "conversation.read");
  if (!Number.isSafeInteger(watermark?.notificationSequence) || !Number.isSafeInteger(watermark?.messageSequence) || watermark.notificationSequence < 0 || watermark.messageSequence < 0) throw new CommunicationError("invalid_read_watermark", 400);
  const now = Date.now();
  const maxMessageSequence = [...store.conversationMessages.values()].filter(m => m.conversationId === shipmentId).reduce((max, m) => Math.max(max, m.sequence), 0);
  if (watermark.notificationSequence > store.notificationSequence || watermark.messageSequence > maxMessageSequence) throw new CommunicationError("invalid_read_watermark", 400);
  for (const [id, n] of store.notifications) {
    if (n.recipientUserId === principal.userId && n.recipientOrgId === principal.organizationId && n.shipmentId === shipmentId && n.recipientSequence <= watermark.notificationSequence && n.readAtUtcMs == null) store.notifications.set(id, { ...n, readAtUtcMs: now });
  }
  const key = `${shipmentId}:${principal.userId}:${principal.organizationId}`;
  const current = store.conversationReadStates.get(key);
  const through = Math.min(watermark.messageSequence, maxMessageSequence);
  store.conversationReadStates.set(key, { conversationId: shipmentId, userId: principal.userId, orgId: principal.organizationId, lastReadSequence: Math.max(current?.lastReadSequence ?? 0, through), updatedAtUtcMs: now });
  return { lastReadSequence: store.conversationReadStates.get(key)!.lastReadSequence };
}

export function markNotificationRead(store: Store, notificationId: string): Notification {
  const principal = principalFor(store);
  requirePermission(store, "notification.read");
  const notification = store.notifications.get(notificationId);
  if (!notification || notification.recipientUserId !== principal.userId || notification.recipientOrgId !== principal.organizationId) throw new CommunicationError("not_found", 404);
  const shipment = store.shipments.get(notification.shipmentId);
  if (!shipment || !isActiveEntity(shipment)) throw new CommunicationError("not_found", 404);
  requireShipmentActor(store, shipment, "conversation.read");
  const updated = { ...notification, readAtUtcMs: notification.readAtUtcMs ?? Date.now() };
  store.notifications.set(updated.id, updated);
  return updated;
}

export function listConversationMessages(store: Store, shipmentId: string, limit = 50, beforeSequence?: number) {
  const shipment = getShipment(store, shipmentId);
  const principal = requireShipmentActor(store, shipment, "conversation.read");
  const conversation = getOrCreateConversation(store, shipment);
  const pageSize = Math.max(1, Math.min(100, Number.isFinite(limit) ? Math.trunc(limit) : 50));
  const all = [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id).sort((a, b) => a.sequence - b.sequence);
  const filtered = beforeSequence == null ? all : all.filter(m => m.sequence < beforeSequence);
  const page = filtered.slice(-pageSize);
  const last = all.at(-1)?.sequence ?? 0;
  store.conversationReadStates.set(`${conversation.id}:${principal.userId}:${principal.organizationId}`, {
    conversationId: conversation.id, userId: principal.userId, orgId: principal.organizationId,
    lastReadSequence: Math.max(store.conversationReadStates.get(`${conversation.id}:${principal.userId}:${principal.organizationId}`)?.lastReadSequence ?? 0, last), updatedAtUtcMs: Date.now(),
  });
  return { conversation, messages: page, nextBeforeSequence: filtered.length > pageSize ? page[0]?.sequence ?? null : null, canSend: canPrincipalSend(store, shipment, conversation, principal) };
}

export function sendConversationMessage(store: Store, shipmentId: string, input: { body: string; clientRequestId: string }): { message: ConversationMessage; created: boolean } {
  const shipment = getShipment(store, shipmentId);
  const principal = requireShipmentActor(store, shipment, "conversation.send");
  const conversation = getOrCreateConversation(store, shipment);
  const body = typeof input.body === "string" ? input.body.trim() : "";
  const requestId = typeof input.clientRequestId === "string" ? input.clientRequestId.trim() : "";
  if (!body || body.length > MAX_MESSAGE_LENGTH || /[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(body)) throw new CommunicationError("invalid_message", 400);
  if (!requestId || requestId.length > 128) throw new CommunicationError("invalid_client_request_id", 400);
  const existing = [...store.conversationMessages.values()].find(m => m.conversationId === conversation.id && m.senderUserId === principal.userId && m.senderOrgId === principal.organizationId && m.clientRequestId === requestId);
  if (existing) {
    if (existing.body !== body) throw new CommunicationError("idempotency_conflict", 409);
    return { message: existing, created: false };
  }
  if (conversation.replyUntilUtcMs != null && Date.now() >= conversation.replyUntilUtcMs) throw new CommunicationError("conversation_read_only", 409);
  const recent = [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id && m.senderUserId === principal.userId && m.createdAtUtcMs > Date.now() - 60_000);
  const configuredLimit = Number(process.env.CONVERSATION_SENDS_PER_MINUTE ?? DEFAULT_MESSAGES_PER_MINUTE);
  const limit = Number.isFinite(configuredLimit) && configuredLimit > 0 ? Math.min(120, Math.trunc(configuredLimit)) : DEFAULT_MESSAGES_PER_MINUTE;
  if (recent.length >= limit) throw new CommunicationError("conversation_rate_limited", 429, Math.max(1000, recent[0]!.createdAtUtcMs + 60_000 - Date.now()));
  const now = Date.now();
  const sequence = Math.max(0, ...[...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id).map(m => m.sequence)) + 1;
  const message: ConversationMessage = { id: randomUUID(), conversationId: conversation.id, sequence, senderUserId: principal.userId, senderOrgId: principal.organizationId, body, clientRequestId: requestId, createdAtUtcMs: now };
  store.conversationMessages.set(message.id, message);
  store.conversations.set(conversation.id, { ...conversation, updatedAtUtcMs: now });
  createNotifications(store, shipment, message.id, "conversation.message", now, message.id);
  return { message, created: true };
}

export function requestConversationEscalation(store: Store, shipmentId: string, input: { granteeUserId: string; reason: string; canRead: boolean; canSend: boolean; expiresAtUtcMs: number }): ConversationEscalationGrant {
  const shipment = getShipment(store, shipmentId);
  const requester = requireShipmentActor(store, shipment, "conversation.read");
  if (!requester.permissions.includes("conversation.escalation_request")) throw new CommunicationError("forbidden", 403);
  const target = store.users.get(input.granteeUserId);
  if (!isActiveEntity(target) || input.reason.trim().length < 8 || input.reason.length > 500 || (!input.canRead && !input.canSend) || !Number.isFinite(input.expiresAtUtcMs) || input.expiresAtUtcMs <= Date.now() || input.expiresAtUtcMs > Date.now() + 7 * 24 * 60 * 60 * 1000) throw new CommunicationError("invalid_escalation", 400);
  const opsMembership = [...store.memberships.values()].find(m => m.userId === input.granteeUserId && isActiveEntity(m) && store.organizations.get(m.orgId)?.kind === "PLATFORM" && (store.membershipRoles.get(`${m.userId}:${m.orgId}`) ?? legacyRoles(m, store.organizations.get(m.orgId)!)).includes("OPS"));
  if (!opsMembership || input.granteeUserId === requester.userId) throw new CommunicationError("invalid_escalation_grantee", 400);
  const grant: ConversationEscalationGrant = { id: randomUUID(), conversationId: shipment.id, requesterUserId: requester.userId, granteeUserId: input.granteeUserId, reason: input.reason.trim(), canRead: input.canRead, canSend: input.canSend, createdAtUtcMs: Date.now(), expiresAtUtcMs: input.expiresAtUtcMs };
  store.conversationEscalationGrants.set(grant.id, grant);
  recordAudit(store, "CONVERSATION_ESCALATION_REQUESTED", "conversation", shipment.id, undefined, grant.id);
  return grant;
}

export function decideConversationEscalation(store: Store, grantId: string, approve: boolean): ConversationEscalationGrant {
  const principal = requirePermission(store, "conversation.escalation_approve");
  const grant = store.conversationEscalationGrants.get(grantId);
  if (!grant || grant.approvedAtUtcMs != null || grant.revokedAtUtcMs != null || grant.expiresAtUtcMs <= Date.now()) throw new CommunicationError("not_found", 404);
  if (principal.userId === grant.requesterUserId || principal.userId === grant.granteeUserId) throw new CommunicationError("approval_separation_required", 403);
  const updated = approve ? { ...grant, approverUserId: principal.userId, approvedAtUtcMs: Date.now() } : { ...grant, approverUserId: principal.userId, revokedAtUtcMs: Date.now() };
  store.conversationEscalationGrants.set(grant.id, updated);
  recordAudit(store, approve ? "CONVERSATION_ESCALATION_APPROVED" : "CONVERSATION_ESCALATION_DENIED", "conversation", grant.conversationId, undefined, grant.id);
  return updated;
}

export function revokeConversationEscalation(store: Store, grantId: string): ConversationEscalationGrant {
  const principal = principalFor(store);
  const grant = store.conversationEscalationGrants.get(grantId);
  if (!grant || grant.revokedAtUtcMs != null) throw new CommunicationError("not_found", 404);
  if (principal.userId === grant.requesterUserId) {
    if (!principal.permissions.includes("conversation.escalation_request")) throw new CommunicationError("forbidden", 403);
  } else if (principal.userId === grant.approverUserId) {
    if (!principal.permissions.includes("conversation.escalation_approve")) throw new CommunicationError("forbidden", 403);
  } else if (principal.userId === grant.granteeUserId) {
    if (!principal.roles.includes("OPS") || !principal.permissions.includes("conversation.support_read")) throw new CommunicationError("forbidden", 403);
  } else throw new CommunicationError("not_found", 404);
  const updated = { ...grant, revokedAtUtcMs: Date.now() };
  store.conversationEscalationGrants.set(grant.id, updated);
  recordAudit(store, "CONVERSATION_ESCALATION_REVOKED", "conversation", grant.conversationId, grant.id);
  return updated;
}
