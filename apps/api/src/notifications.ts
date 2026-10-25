/**
 * What the people on a shipment are told and say to each other: notifications, their words, and the shipment
 * conversation, plus the one notice with no shipment, a driver's new trip, which shares the inbox and its checks.
 * Over 500 lines and still one file because these share one timeline and one read watermark, and a message creates
 * its notification here; split, each half would need the other's private helpers to work.
 */
import { randomUUID } from "node:crypto";
import { authorizationContext, effectivePermissions, legacyRoles, principalFor, recordAudit, requirePermission, type Principal } from "./rbac.ts";
import { isActiveEntity } from "./softDelete.ts";
import { assignedDriverMaySee } from "./tripAssignmentRules.ts";
import { BOOKING_EXPIRED_MONEY_SENTENCE, BOOKING_EXPIRED_SENTENCE } from "./config.ts";
import type { Store } from "./store.ts";
import type { EwayBillStartBlockReason } from "./ewayBillStartGate.ts";
import { enqueuePushIntentForNotification } from "./features/push/push.ts";
import type { AnchorTrip, Conversation, ConversationEscalationGrant, ConversationMessage, Notification, Shipment } from "./types.ts";

const MAX_MESSAGE_LENGTH = 4000;
const DEFAULT_REPLY_WINDOW_DAYS = 14;
const DEFAULT_MESSAGES_PER_MINUTE = 20;
const POLICY_VERSION = "support-window-v1";
// Owner, 22 Oct 2026: "lock once the shipper accepts delivery". Replies close at acceptance, with no support window.
const ACCEPTED_POLICY_VERSION = "delivery-accepted-v1";

export class CommunicationError extends Error {
  status: number;
  retryAfterMs?: number;
  constructor(message: string, status = 400, retryAfterMs?: number) { super(message); this.status = status; this.retryAfterMs = retryAfterMs; }
}

type WorkflowSnapshot = {
  shipments: Map<string, { status: string; podAt?: number | null; podAcceptedAt?: number; customerOrgId?: string; carrierId: string }>;
  trips: Map<string, { status: string; startedAt?: number; completedAt?: number; carrierId: string; assignedDriverUserId?: string }>;
  payments: Map<string, { status: string; shipmentId: string; updatedAt: number }>;
};

export function workflowSnapshot(store: Store): WorkflowSnapshot {
  return {
    shipments: new Map([...store.shipments].map(([id, s]) => [id, { status: s.status, podAt: s.podAtUtcMs, podAcceptedAt: s.podAcceptedAtUtcMs, customerOrgId: s.customerOrgId, carrierId: s.carrierId }])),
    trips: new Map([...store.anchorTrips].map(([id, t]) => [id, { status: t.status, startedAt: t.startedAtUtcMs, completedAt: t.completedAtUtcMs, carrierId: t.carrierId, assignedDriverUserId: t.assignedDriverUserId }])),
    payments: new Map([...store.payments].map(([id, p]) => [id, { status: p.status, shipmentId: p.shipmentId, updatedAt: p.updatedAtUtcMs }])),
  };
}

export function captureWorkflowNotifications(store: Store, previous: WorkflowSnapshot): void {
  // Owner, 21 Oct 2026: "No need for their own action". The person whose request made these changes is not
  // told about them. A webhook, the payment provider or a timer has no person behind it, so all may hear.
  const actorUserId = authorizationContext.getStore()?.principal?.userId;
  const emit = (shipment: Shipment | undefined, eventKey: string, occurredAt: number, sourceTransitionId?: string, shipperBody?: string) => {
    if (!shipment) return;
    getOrCreateConversation(store, shipment);
    createNotifications(store, shipment, sourceTransitionId ?? `${eventKey}:${shipment.id}:${occurredAt}`, eventKey, occurredAt, undefined, actorUserId, shipperBody);
  };
  for (const [id, shipment] of store.shipments) {
    const old = previous.shipments.get(id);
    if (!old) emit(shipment, "shipment.booked", shipment.createdAtUtcMs);
    else if (old.status !== "BOOKED" && shipment.status === "BOOKED") emit(shipment, "shipment.carrier_accepted", shipment.acceptedAtUtcMs ?? shipment.updatedAtUtcMs);
    else if (old.status !== "FAILED_CARRIER_REFUNDED" && shipment.status === "FAILED_CARRIER_REFUNDED") {
      if (shipment.leftBehindAtUtcMs != null) tellShipperTheTripLeft(store, shipment);
      else if (shipment.expiredUnpaidAtUtcMs != null) notifyShipper(store, shipment, BOOKING_EXPIRED_EVENT, "This booking expired", bookingExpiredBody(store, shipment));
      else emit(shipment, "shipment.cancelled", shipment.updatedAtUtcMs, undefined, cancelledShipperBody(store, shipment, previous.payments.get(shipment.paymentId)?.status));
    }
    if ((!old?.podAt || old.podAt === 0) && shipment.podAtUtcMs) emit(shipment, "shipment.pod_submitted", shipment.podAtUtcMs);
    if (!old?.podAcceptedAt && shipment.podAcceptedAtUtcMs) emit(shipment, "shipment.pod_accepted", shipment.podAcceptedAtUtcMs);
  }
  for (const [id, trip] of store.anchorTrips) {
    const old = previous.trips.get(id);
    if (trip.assignedDriverUserId && trip.assignedDriverUserId !== old?.assignedDriverUserId) createTripAssignedNotice(store, trip, actorUserId);
    if (!old) continue;
    // A cancelled shipment, or one the trip left without, is not on the trip, so its people hear nothing of it.
    const onTrip = (shipment: Shipment) => shipment.anchorTripId === id && shipment.status !== "FAILED_CARRIER_REFUNDED";
    if (!old.startedAt && trip.startedAtUtcMs) {
      for (const shipment of store.shipments.values()) if (onTrip(shipment)) emit(shipment, "trip.started", trip.startedAtUtcMs);
    }
    if (old.status !== "COMPLETED" && trip.status === "COMPLETED") {
      for (const shipment of store.shipments.values()) if (onTrip(shipment)) emit(shipment, "trip.completed", trip.completedAtUtcMs ?? Date.now());
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
  if (!belongs || !assignedDriverMaySee(store, principal, shipment)) throw new CommunicationError("not_found", 404);
  return principal;
}

function getOrCreateConversation(store: Store, shipment: Shipment): Conversation {
  const current = store.conversations.get(shipment.id);
  if (current) return current;
  const now = Date.now();
  const acceptedAt = shipment.podAcceptedAtUtcMs;
  const terminal = shipment.status === "DELIVERED" || shipment.status === "FAILED_CARRIER_REFUNDED";
  const conversation: Conversation = {
    id: shipment.id, shipmentId: shipment.id, createdAtUtcMs: now, updatedAtUtcMs: now,
    ...(acceptedAt != null ? { terminalAtUtcMs: acceptedAt, replyUntilUtcMs: acceptedAt, replyPolicyVersion: ACCEPTED_POLICY_VERSION }
      : terminal ? { replyUntilUtcMs: now, replyPolicyVersion: "legacy-terminal-read-only" } : {}),
  };
  store.conversations.set(conversation.id, conversation);
  return conversation;
}

/** Runs at server start and before every save, so chats recorded before the acceptance rule are locked too. */
export function captureTerminalConversationWindows(store: Store, now = Date.now()): void {
  for (const [id, conversation] of store.conversations) {
    const shipment = store.shipments.get(conversation.shipmentId);
    if (!shipment) continue;
    // Accepted delivery locks at once, whatever the status (it stays PENDING_RELEASE until NaviG8r releases payment).
    // An older chat whose recorded window runs past the acceptance (a support window, or a read-only chat first
    // opened after it) is moved to the acceptance time as well.
    const acceptedAt = shipment.podAcceptedAtUtcMs;
    if (acceptedAt != null) {
      const lockedByAcceptance = conversation.replyPolicyVersion === ACCEPTED_POLICY_VERSION;
      const closedBeforeAcceptance = conversation.replyUntilUtcMs != null && conversation.replyUntilUtcMs <= acceptedAt;
      if (!lockedByAcceptance && !closedBeforeAcceptance) {
        store.conversations.set(id, { ...conversation, updatedAtUtcMs: now, terminalAtUtcMs: acceptedAt, replyUntilUtcMs: acceptedAt, replyPolicyVersion: ACCEPTED_POLICY_VERSION });
      }
      continue;
    }
    if (conversation.terminalAtUtcMs != null || conversation.replyPolicyVersion === "legacy-terminal-read-only") continue;
    // Released or cancelled without the shipper accepting: the support window below still applies.
    if (!["DELIVERED", "FAILED_CARRIER_REFUNDED"].includes(shipment.status)) continue;
    const configuredDays = Number(process.env.CONVERSATION_REPLY_WINDOW_DAYS ?? DEFAULT_REPLY_WINDOW_DAYS);
    const replyWindowDays = Number.isFinite(configuredDays) && configuredDays >= 0 ? configuredDays : DEFAULT_REPLY_WINDOW_DAYS;
    store.conversations.set(id, {
      ...conversation, updatedAtUtcMs: now, terminalAtUtcMs: now,
      replyUntilUtcMs: now + replyWindowDays * 24 * 60 * 60 * 1000,
      replyPolicyVersion: POLICY_VERSION,
    });
  }
}

function notificationRecipients(store: Store, shipment: Shipment, eventKey: string, actorUserId?: string): Array<{ userId: string; orgId: string; role: "SHIPPER" | "CARRIER" }> {
  const recipients: Array<{ userId: string; orgId: string; role: "SHIPPER" | "CARRIER" }> = [];
  const orgs: Array<[string | undefined, "SHIPPER" | "CARRIER"]> = [[shipment.customerOrgId, "SHIPPER"], [shipment.carrierId, "CARRIER"]];
  for (const [orgId, role] of orgs) {
    if (!orgId) continue;
    for (const membership of store.memberships.values()) {
      // A driver hears only about shipments on their own trip, push included; see mustNotHearPaymentEvent.
      const mayHear = assignedDriverMaySee(store, { internal: false, subrole: membership.role, userId: membership.userId }, shipment) && !mustNotHearPaymentEvent(membership.role, eventKey);
      if (membership.orgId === orgId && membership.userId !== actorUserId && mayHear && eligibleActor(store, membership.userId, orgId, role)) recipients.push({ userId: membership.userId, orgId, role });
    }
  }
  return recipients;
}

/**
 * What a shipper reads when Finance cancels their shipment because the carrier cannot carry it. Which money words
 * apply comes from the payment before the cancel: an unpaid booking's payment is also marked REFUNDED. A held
 * payment may already have left the shipper's bank (UPI, netbanking), so it is never called untaken.
 */
function cancelledShipperBody(store: Store, shipment: Shipment, paymentStatusBefore: string | undefined): string {
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  const load = trip?.originCity && trip?.destCity ? `your load from ${trip.originCity} to ${trip.destCity}` : "your load";
  const status = store.payments.get(shipment.paymentId)?.status;
  const money = status === "HOLD_RELEASED"
    ? " NaviG8r never collected this payment. Razorpay returns it within 3 days of when you paid; your bank may take 5-7 working days after that."
    : paymentStatusBefore === "CAPTURED" ? " Your refund has started."
      : paymentStatusBefore === "CREATED" || paymentStatusBefore === "FAILED" ? " Nothing was charged." : "";
  return `The carrier cannot carry ${load}, so it was cancelled.${money}`;
}

export const SHIPMENT_LEFT_BEHIND_EVENT = "shipment.left_behind";

/**
 * The trip started while this booking's checkout was not done, so it was closed (services.ts). Only the shipper is
 * told: the carrier started the trip. A capture Razorpay had already reported is money taken, which Finance refunds.
 */
function tellShipperTheTripLeft(store: Store, shipment: Shipment): void {
  const collected = store.payments.get(shipment.paymentId)?.status === "CAPTURED_AFTER_CANCEL";
  const body = collected
    ? "NaviG8r is refunding your payment. Your bank may take 5-7 working days."
    : "If your bank shows a payment, it comes back within 3 days. Book another trip when you are ready.";
  notifyShipper(store, shipment, SHIPMENT_LEFT_BEHIND_EVENT, "This trip left without your shipment", body);
}

/** A booking not paid for in time was closed (services.ts). Only the shipper is told: the carrier could not accept it. */
export const BOOKING_EXPIRED_EVENT = "shipment.booking_expired";

/** Once Razorpay has an order, the shipper may have paid in checkout without the payment reaching NaviG8r. */
function bookingExpiredBody(store: Store, shipment: Shipment): string {
  const payment = store.payments.get(shipment.paymentId);
  const mayBeHeld = payment?.provider === "RAZORPAY" && payment.razorpayOrderId != null;
  return mayBeHeld ? `${BOOKING_EXPIRED_SENTENCE} ${BOOKING_EXPIRED_MONEY_SENTENCE}` : BOOKING_EXPIRED_SENTENCE;
}

function createNotifications(store: Store, shipment: Shipment, eventId: string, eventKey: string, createdAtUtcMs: number, messageId?: string, actorUserId?: string, shipperBody?: string): void {
  const conversationId = shipment.id;
  for (const recipient of notificationRecipients(store, shipment, eventKey, actorUserId)) {
    const duplicate = [...store.notifications.values()].some(n => n.eventId === eventId && n.recipientUserId === recipient.userId && n.recipientOrgId === recipient.orgId);
    if (duplicate) continue;
    const notification: Notification = {
      id: randomUUID(), recipientSequence: ++store.notificationSequence,
      eventId, eventKey, recipientUserId: recipient.userId, recipientOrgId: recipient.orgId,
      shipmentId: shipment.id, conversationId, ...(messageId ? { messageId } : {}), createdAtUtcMs,
      data: { shipmentId: shipment.id, audience: recipient.role, title: notificationTitle(eventKey, recipient.role), body: (recipient.role === "SHIPPER" ? shipperBody : undefined) ?? notificationBody(eventKey, recipient.role) },
    };
    store.notifications.set(notification.id, notification);
    enqueuePushIntentForNotification(store, notification);
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
    "shipment.cancelled": ["Shipment cancelled", "Shipment cancelled"],
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
    // The shipper's words, with the route and the money, are written per shipment in cancelledShipperBody.
    "shipment.cancelled": ["This shipment was cancelled.", "NaviG8r cancelled this shipment on your trip."],
    "conversation.message": ["A participant added a message to the shipment conversation.", "A participant added a message to the shipment conversation."],
  };
  const values = bodies[eventKey] ?? ["There is an update for this shipment.", "There is an update for this shipment."];
  return values[role === "SHIPPER" ? 0 : 1];
}

export const PAYMENT_EVENT_PREFIX = "payment.";

// Payment notices reach neither a carrier's drivers (15 Oct 2026) nor its dispatchers (owner, 21 Oct 2026).
// The one rule for which notices are written and, since rows written before it are still stored, which
// are shown. The database readers apply it in SQL, through hidePaymentNotices.
export function mustNotHearPaymentEvent(memberRole: string, eventKey: string): boolean {
  return (memberRole === "DRIVER" || memberRole === "DISPATCHER") && eventKey.startsWith(PAYMENT_EVENT_PREFIX);
}

export const TRIP_ASSIGNED_EVENT = "trip.assigned";

// "22 Oct" in India time, as the app writes a short date.
const SHORT_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
function dayInIndiaWords(utcMs: number): string {
  const india = new Date(utcMs + 5.5 * 60 * 60 * 1000);
  return `${india.getUTCDate()} ${SHORT_MONTHS[india.getUTCMonth()]}`;
}

// Owner, 21 Oct 2026: a driver hears that a trip is theirs, booked on or not, so this is the one notice with no
// shipment (its shipmentId is "": the database column cannot be empty). Only the driver named hears it: never
// the shipper, never the rest of the carrier. Its words name the route and the day, never an amount.
function createTripAssignedNotice(store: Store, trip: AnchorTrip, actorUserId?: string): void {
  const driverUserId = trip.assignedDriverUserId;
  if (!driverUserId || driverUserId === actorUserId || !eligibleActor(store, driverUserId, trip.carrierId, "CARRIER")) return;
  // Given back after a time with another driver (A, B, then A): the first notice shows again, so no second one.
  const alreadyTold = [...store.notifications.values()].some((n) => n.eventKey === TRIP_ASSIGNED_EVENT && n.tripId === trip.id && n.recipientUserId === driverUserId);
  if (alreadyTold) return;
  const leavesUtcMs = Date.parse(trip.windowStart);
  const body = `You have a new trip: ${trip.originCity} to ${trip.destCity}${Number.isNaN(leavesUtcMs) ? "" : `, leaves ${dayInIndiaWords(leavesUtcMs)}`}.`;
  const now = Date.now();
  const notification: Notification = {
    id: randomUUID(), recipientSequence: ++store.notificationSequence,
    eventId: `${TRIP_ASSIGNED_EVENT}:${trip.id}:${driverUserId}:${now}`, eventKey: TRIP_ASSIGNED_EVENT,
    recipientUserId: driverUserId, recipientOrgId: trip.carrierId, shipmentId: "", tripId: trip.id, createdAtUtcMs: now,
    data: { tripId: trip.id, audience: "CARRIER", title: "New trip", body },
  };
  store.notifications.set(notification.id, notification);
  enqueuePushIntentForNotification(store, notification);
}

export const EWAY_BILL_HOLDS_START_EVENT = "eway_bill.blocking_start";
export const EWAY_BILL_TRUCK_CHANGED_EVENT = "eway_bill.truck_changed";

// Shipper words for each reason the start gate gives (ewayBillStartGate.ts).
const HOLDS_START_SHIPPER_BODY: Record<EwayBillStartBlockReason, string> = {
  no_bill: "Add the e-way bill for this shipment, or say none is needed.",
  truck_missing: "Add the truck on the portal, then here.",
  truck_differs: "The truck on your e-way bill is not the truck on this trip. Check the truck on the portal, then here.",
  expired: "The valid-until time you entered has passed. Check the bill on the portal, then enter the new time here.",
  problem: "NaviG8r found a problem with your e-way bill. Check the details here and on the portal.",
};

/** One notice to each shipper login on the shipment that may read notices, and how many were sent. Never the carrier: it is the one acting. */
function notifyShipper(store: Store, shipment: Shipment, eventKey: string, title: string, body: string, extraData: Record<string, string> = {}): number {
  const now = Date.now();
  getOrCreateConversation(store, shipment);
  let sent = 0;
  for (const recipient of notificationRecipients(store, shipment, eventKey)) {
    if (recipient.role !== "SHIPPER") continue;
    const notification: Notification = {
      id: randomUUID(), recipientSequence: ++store.notificationSequence,
      eventId: `${eventKey}:${shipment.id}:${recipient.userId}:${now}`, eventKey,
      recipientUserId: recipient.userId, recipientOrgId: recipient.orgId,
      shipmentId: shipment.id, conversationId: shipment.id, createdAtUtcMs: now,
      data: { ...extraData, shipmentId: shipment.id, audience: "SHIPPER", title, body },
    };
    store.notifications.set(notification.id, notification);
    enqueuePushIntentForNotification(store, notification);
    sent++;
  }
  return sent;
}

/** Marks every unread notice of this kind on the shipment read, so a shipper is never left with one that is out of date. */
export function markShipmentNoticesRead(store: Store, shipmentId: string, eventKey: string): void {
  const now = Date.now();
  for (const notice of store.notifications.values()) {
    if (notice.eventKey === eventKey && notice.shipmentId === shipmentId && notice.readAtUtcMs == null) {
      store.notifications.set(notice.id, { ...notice, readAtUtcMs: now });
    }
  }
}

// The office's reminders and truck notices reach a shipper at most once in this time per shipment (owner, 23 Oct 2026).
const SHIPPER_NOTICE_GAP_MS = 6 * 60 * 60 * 1000;

function sentInTheLastGap(store: Store, shipmentId: string, eventKey: string, reason?: string): boolean {
  const since = Date.now() - SHIPPER_NOTICE_GAP_MS;
  return [...store.notifications.values()].some((n) =>
    n.eventKey === eventKey && n.shipmentId === shipmentId && n.createdAtUtcMs > since && (reason === undefined || n.data?.reason === reason));
}

/** already_reminded: one for this reason is unread, or was sent in the last 6 hours. no_recipient: no shipper login may read notices. */
export type ReminderAnswer = { sent: true } | { sent: false; why: "already_reminded" | "no_recipient" };

/**
 * The carrier office's Remind button (owner, 23 Oct 2026): tells the shipper why their bill holds the trip. Nothing
 * is sent while a reminder for the same reason is unread, or within 6 hours of one, read or not. An unread one for
 * another reason is out of date, so it is marked read and the new one sent.
 */
export function remindShipperBillHoldsStart(store: Store, shipment: Shipment, reason: EwayBillStartBlockReason): ReminderAnswer {
  const alreadyWaiting = [...store.notifications.values()].some((n) =>
    n.eventKey === EWAY_BILL_HOLDS_START_EVENT && n.shipmentId === shipment.id && n.readAtUtcMs == null && n.data?.reason === reason);
  if (alreadyWaiting || sentInTheLastGap(store, shipment.id, EWAY_BILL_HOLDS_START_EVENT, reason)) return { sent: false, why: "already_reminded" };
  markShipmentNoticesRead(store, shipment.id, EWAY_BILL_HOLDS_START_EVENT);
  const sent = notifyShipper(store, shipment, EWAY_BILL_HOLDS_START_EVENT, "The trip is waiting for your e-way bill", HOLDS_START_SHIPPER_BODY[reason], { reason });
  return sent > 0 ? { sent: true } : { sent: false, why: "no_recipient" };
}

/**
 * The office changed the trip's truck, and this shipment's bill names a different one. Replaces any earlier unread
 * notice of this kind, but only once in 6 hours: within them nothing changes, since the shipment screen always
 * shows the trip's latest truck. [carrierName] is undefined when the carrier has no name: a shipper never sees its id.
 */
export function notifyShipperTruckChanged(store: Store, shipment: Shipment, carrierName: string | undefined, truckNumber: string, truckOnBill: string): void {
  if (sentInTheLastGap(store, shipment.id, EWAY_BILL_TRUCK_CHANGED_EVENT)) return;
  markShipmentNoticesRead(store, shipment.id, EWAY_BILL_TRUCK_CHANGED_EVENT);
  const body = `${carrierName ?? "Your carrier"} set the truck on this trip to ${truckNumber}. Your e-way bill has ${truckOnBill}. `
    + `Ask ${carrierName ?? "your carrier"} which is right. If the bill is wrong, fix it on the portal, then here.`;
  notifyShipper(store, shipment, EWAY_BILL_TRUCK_CHANGED_EVENT, "The truck on your trip is different from your e-way bill", body);
}

/** A trip notice is shown, opened or pushed only while its trip is still the recipient's to drive. */
export function tripNoticeStillTheirs(store: Store, notification: Notification): boolean {
  const trip = notification.tripId ? store.anchorTrips.get(notification.tripId) : undefined;
  return trip != null && isActiveEntity(trip) && trip.carrierId === notification.recipientOrgId
    && trip.assignedDriverUserId === notification.recipientUserId
    && eligibleActor(store, notification.recipientUserId, notification.recipientOrgId, "CARRIER");
}

export function listNotifications(store: Store, limit = 30, before?: string) {
  const principal = principalFor(store);
  requirePermission(store, "notification.read");
  const pageSize = Math.max(1, Math.min(100, Number.isFinite(limit) ? Math.trunc(limit) : 30));
  const all = [...store.notifications.values()].filter(n => n.recipientUserId === principal.userId && n.recipientOrgId === principal.organizationId && !mustNotHearPaymentEvent(principal.subrole, n.eventKey))
    .filter(n => {
      if (n.tripId) return tripNoticeStillTheirs(store, n);
      const shipment = store.shipments.get(n.shipmentId);
      if (!shipment || !isActiveEntity(shipment)) return false;
      try { requireShipmentActor(store, shipment, "conversation.read"); return true; } catch { return false; }
    }).sort((a, b) => b.createdAtUtcMs - a.createdAtUtcMs || b.id.localeCompare(a.id));
  const filtered = before ? all.filter(n => `${n.createdAtUtcMs}:${n.id}` < before) : all;
  const items = filtered.slice(0, pageSize);
  const cursor = filtered.length > pageSize && items.length ? `${items[items.length - 1]!.createdAtUtcMs}:${items[items.length - 1]!.id}` : null;
  return { notifications: items, nextCursor: cursor, unreadCount: all.filter(n => n.readAtUtcMs == null).length };
}

export function resolveNotificationOpenRoute(store: Store, notificationId: string, userId: string): {
  organizationId: string;
  shipmentId: string;
  conversationId: string;
} | { organizationId: string; tripId: string } {
  const notification = store.notifications.get(notificationId);
  if (!notification || notification.recipientUserId !== userId) throw new CommunicationError("notification_not_found", 404);
  if (notification.tripId) {
    if (!tripNoticeStillTheirs(store, notification)) throw new CommunicationError("notification_not_found", 404);
    return { organizationId: notification.recipientOrgId, tripId: notification.tripId };
  }
  const shipment = store.shipments.get(notification.shipmentId);
  if (!shipment || !isActiveEntity(shipment)) throw new CommunicationError("notification_not_found", 404);
  const role = notification.recipientOrgId === shipment.customerOrgId ? "SHIPPER"
    : notification.recipientOrgId === shipment.carrierId ? "CARRIER" : null;
  if (!role || !eligibleActor(store, userId, notification.recipientOrgId, role)) throw new CommunicationError("notification_not_found", 404);
  const memberRole = store.memberships.get(`${userId}:${notification.recipientOrgId}`)?.role ?? "";
  if (!assignedDriverMaySee(store, { internal: false, subrole: memberRole, userId }, shipment)) throw new CommunicationError("notification_not_found", 404);
  // As in the list: a payment notice stored before the rule, or tapped in an old push, does not exist here.
  if (mustNotHearPaymentEvent(memberRole, notification.eventKey)) throw new CommunicationError("notification_not_found", 404);
  return {
    organizationId: notification.recipientOrgId,
    shipmentId: shipment.id,
    conversationId: notification.conversationId ?? shipment.id,
  };
}

type TimelineItem =
  | { type: "message"; id: string; createdAtUtcMs: number; sequence: number; senderUserId?: string; senderOrgId: string; senderLabel: string; body: string }
  | { type: "event"; id: string; createdAtUtcMs: number; recipientSequence: number; eventKey: string; title: string; body: string; readAtUtcMs?: number };
type TimelineKey = { createdAtUtcMs: number; priority: number; id: string };
type TimelineCursor = {
  v: 1; userId: string; orgId: string; shipmentId: string; limit: number;
  notificationSequence: number; messageSequence: number; before: TimelineKey;
};
export type TimelinePageRequest = {
  conversationId: string; shipmentId: string; userId: string; orgId: string; limit: number;
  notificationSequence?: number; messageSequence?: number; before?: TimelineKey;
  /** Leave payment notices out in the query, so the page size and hasMore count only rows shown. */
  hidePaymentNotices: boolean;
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
  /** Leave payment notices out in the query, so the counts and paging match what is shown. */
  hidePaymentNotices: boolean;
};
export type GroupedInboxPageSource = {
  notificationSequence: number;
  unreadCount: number;
  /** A trip notice's row has shipmentId "", its tripId and notificationId, and no shipmentReference. */
  groups: Array<{ shipmentId: string; latestAtUtcMs: number; unreadCount: number; shipmentReference?: string; tripId?: string; notificationId?: string }>;
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

/**
 * Who a message is from, as the viewer reads it (owner, 22 Oct 2026). A person's name only within their own company:
 * another company's sender is that company's name, plus "Driver" or "Office" on the carrier side, since who drives
 * is the carrier's business, never the shipper's.
 */
function senderLabel(store: Store, viewer: Principal, message: ConversationMessage, tripDriverUserId: string | undefined): string {
  if (message.senderUserId === viewer.userId && message.senderOrgId === viewer.organizationId) return "You";
  const org = store.organizations.get(message.senderOrgId);
  if (org?.kind === "PLATFORM") return "NaviG8r";
  if (message.senderOrgId === viewer.organizationId) return store.users.get(message.senderUserId)?.fullName?.trim() || "Your team";
  const company = org?.displayName?.trim() || "Shipment participant";
  if (!isCarrierOrg(org?.kind)) return company;
  // The role kept when the message was sent; a message from before that was kept is worked out from today's trip.
  return `${company} · ${message.senderRoleLabel ?? carrierSenderRole(store, message.senderUserId, message.senderOrgId, tripDriverUserId)}`;
}

function isCarrierOrg(kind: string | undefined): boolean {
  return kind === "CARRIER_SOLO" || kind === "CARRIER_FLEET" || kind === "CARRIER_LEGACY";
}

/** A DRIVER member, or whoever the carrier named as this trip's driver (an owner who drives), is the Driver. */
function carrierSenderRole(store: Store, userId: string, orgId: string, tripDriverUserId: string | undefined): "Driver" | "Office" {
  const memberRole = store.memberships.get(`${userId}:${orgId}`)?.role;
  return memberRole === "DRIVER" || userId === tripDriverUserId ? "Driver" : "Office";
}

/**
 * Which shipment the Messages screen is about, as the app names a shipment: route plus date, never an ID or
 * reference (spec copy.md, "Shipment name"). The trip's own field names, so the app's lane helpers read it. Never an amount.
 */
function shipmentSummary(store: Store, shipment: Shipment): { originCity?: string; destCity?: string; windowStart?: string } {
  const trip = store.anchorTrips.get(shipment.anchorTripId);
  return trip ? { originCity: trip.originCity, destCity: trip.destCity, windowStart: trip.windowStart } : {};
}

/**
 * Acceptance closes replies for the shipper and the carrier, but NaviG8r staff with an approved support grant can still
 * answer, so a damage complaint raised after accepting gets a reply. Every other closed chat is closed to everyone.
 */
function repliesClosedFor(conversation: Conversation, principal: Principal): boolean {
  if (conversation.replyUntilUtcMs == null || Date.now() < conversation.replyUntilUtcMs) return false;
  return !(conversation.replyPolicyVersion === ACCEPTED_POLICY_VERSION && principal.roles.includes("OPS"));
}

function canPrincipalSend(store: Store, shipment: Shipment, conversation: Conversation, principal: Principal): boolean {
  if (repliesClosedFor(conversation, principal)) return false;
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
    ? await readPage({ conversationId: conversation.id, shipmentId, userId: principal.userId, orgId: principal.organizationId, limit: pageSize, hidePaymentNotices: mustNotHearPaymentEvent(principal.subrole, PAYMENT_EVENT_PREFIX), ...(decoded ? { notificationSequence: decoded.notificationSequence, messageSequence: decoded.messageSequence, before: decoded.before } : {}) })
    : {
      notificationSequence: decoded?.notificationSequence ?? store.notificationSequence,
      messageSequence: decoded?.messageSequence ?? [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id).reduce((max, m) => Math.max(max, m.sequence), 0),
      messages: [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id),
      notifications: [...store.notifications.values()].filter(n => n.conversationId === conversation.id || (n.conversationId == null && n.shipmentId === shipmentId)),
    };
  const notificationSequence = decoded?.notificationSequence ?? snapshot.notificationSequence;
  const messageSequence = decoded?.messageSequence ?? snapshot.messageSequence;
  const tripDriverUserId = store.anchorTrips.get(shipment.anchorTripId)?.assignedDriverUserId;
  const messages: TimelineItem[] = snapshot.messages
    .filter(m => m.conversationId === conversation.id && m.sequence <= messageSequence)
    .map(m => ({ type: "message", id: m.id, createdAtUtcMs: m.createdAtUtcMs, sequence: m.sequence, ...(m.senderOrgId === principal.organizationId ? { senderUserId: m.senderUserId } : {}), senderOrgId: m.senderOrgId, senderLabel: senderLabel(store, principal, m, tripDriverUserId), body: m.body }));
  const events: TimelineItem[] = principal.roles.includes("OPS") ? [] : snapshot.notifications
    .filter(n => n.recipientUserId === principal.userId && n.recipientOrgId === principal.organizationId && n.shipmentId === shipmentId && (n.conversationId === conversation.id || n.conversationId == null) && n.recipientSequence <= notificationSequence && n.eventKey !== "conversation.message" && !mustNotHearPaymentEvent(principal.subrole, n.eventKey))
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
    conversation, items, nextBefore, shipmentSummary: shipmentSummary(store, shipment),
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
      hidePaymentNotices: mustNotHearPaymentEvent(principal.subrole, PAYMENT_EVENT_PREFIX),
      ...(before ? { notificationSequence, before: cursor } : {}),
    });
    const hasMore = page.groups.length > pageSize;
    const shipments = page.groups.slice(0, pageSize);
    const last = shipments.at(-1);
    // The cursor holds the row's key, as below: the shipment id, or "notice:<id>" for a trip notice.
    const nextBefore = hasMore && last
      ? encodeOpaque({ ...cursorScope, notificationSequence: page.notificationSequence, latestAt: last.latestAtUtcMs, shipmentId: last.notificationId ? `notice:${last.notificationId}` : last.shipmentId })
      : null;
    // The database reader ignores trip assignments: drop a driver's other groups after the cursor, so paging advances.
    const shown = shipments.flatMap((group) => {
      if (group.tripId) {
        const notice = group.notificationId ? store.notifications.get(group.notificationId) : undefined;
        const trip = store.anchorTrips.get(group.tripId);
        return notice && trip && tripNoticeStillTheirs(store, notice) ? [{ ...group, tripRoute: `${trip.originCity} to ${trip.destCity}` }] : [];
      }
      const shipment = store.shipments.get(group.shipmentId);
      return !shipment || assignedDriverMaySee(store, principal, shipment) ? [group] : [];
    });
    return { shipments: shown, nextBefore, unreadCount: page.unreadCount, notificationSequence: page.notificationSequence };
  }
  // A row per shipment, and a row per trip notice, which has no shipment to group under. The cursor's
  // shipmentId holds the row's key: the shipment id, or "notice:<id>" for a trip notice.
  type InboxRow = { key: string; shipmentId: string; latestAtUtcMs: number; unreadCount: number; tripId?: string; notificationId?: string };
  const groups = new Map<string, InboxRow>();
  for (const n of store.notifications.values()) {
    if (n.recipientUserId !== principal.userId || n.recipientOrgId !== principal.organizationId || n.recipientSequence > notificationSequence || mustNotHearPaymentEvent(principal.subrole, n.eventKey)) continue;
    if (n.tripId) {
      if (!tripNoticeStillTheirs(store, n)) continue;
      const key = `notice:${n.id}`;
      groups.set(key, { key, shipmentId: "", latestAtUtcMs: n.createdAtUtcMs, unreadCount: n.readAtUtcMs == null ? 1 : 0, tripId: n.tripId, notificationId: n.id });
      continue;
    }
    const shipment = store.shipments.get(n.shipmentId);
    if (!shipment || !isActiveEntity(shipment)) continue;
    const belongs = (principal.roles.includes("SHIPPER") && shipment.customerOrgId === principal.organizationId) || (principal.roles.includes("CARRIER") && shipment.carrierId === principal.organizationId);
    if (!belongs || !assignedDriverMaySee(store, principal, shipment)) continue;
    const group = groups.get(n.shipmentId) ?? { key: n.shipmentId, shipmentId: n.shipmentId, latestAtUtcMs: n.createdAtUtcMs, unreadCount: 0 };
    group.latestAtUtcMs = Math.max(group.latestAtUtcMs, n.createdAtUtcMs);
    if (n.readAtUtcMs == null) group.unreadCount++;
    groups.set(n.shipmentId, group);
  }
  const ordered = [...groups.values()].sort((a, b) => b.latestAtUtcMs - a.latestAtUtcMs || compareIdBytes(b.key, a.key));
  const afterCursor = cursor ? ordered.filter(g => g.latestAtUtcMs < cursor!.latestAt || (g.latestAtUtcMs === cursor!.latestAt && compareIdBytes(g.key, cursor!.shipmentId) < 0)) : ordered;
  const selected = afterCursor.slice(0, pageSize + 1);
  const hasMore = selected.length > pageSize;
  const page = selected.slice(0, pageSize);
  const shipments = page.map(({ key: _key, ...group }) => {
    if (group.tripId) {
      const trip = store.anchorTrips.get(group.tripId)!;
      return { ...group, tripRoute: `${trip.originCity} to ${trip.destCity}` };
    }
    const shipment = store.shipments.get(group.shipmentId)!;
    return { ...group, shipmentReference: shipment.externalLoadId ?? group.shipmentId.slice(0, 8).toUpperCase() };
  });
  const last = page.at(-1);
  const nextBefore = hasMore && last ? encodeOpaque({ ...cursorScope, notificationSequence, latestAt: last.latestAtUtcMs, shipmentId: last.key }) : null;
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
  // The list never shows this member a payment notice, so marking one read is a notice that does not exist.
  if (mustNotHearPaymentEvent(principal.subrole, notification.eventKey)) throw new CommunicationError("not_found", 404);
  if (notification.tripId) {
    if (!tripNoticeStillTheirs(store, notification)) throw new CommunicationError("not_found", 404);
  } else {
    const shipment = store.shipments.get(notification.shipmentId);
    if (!shipment || !isActiveEntity(shipment)) throw new CommunicationError("not_found", 404);
    requireShipmentActor(store, shipment, "conversation.read");
  }
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
  if (repliesClosedFor(conversation, principal)) throw new CommunicationError("conversation_read_only", 409);
  const recent = [...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id && m.senderUserId === principal.userId && m.createdAtUtcMs > Date.now() - 60_000);
  const configuredLimit = Number(process.env.CONVERSATION_SENDS_PER_MINUTE ?? DEFAULT_MESSAGES_PER_MINUTE);
  const limit = Number.isFinite(configuredLimit) && configuredLimit > 0 ? Math.min(120, Math.trunc(configuredLimit)) : DEFAULT_MESSAGES_PER_MINUTE;
  if (recent.length >= limit) throw new CommunicationError("conversation_rate_limited", 429, Math.max(1000, recent[0]!.createdAtUtcMs + 60_000 - Date.now()));
  const now = Date.now();
  const sequence = Math.max(0, ...[...store.conversationMessages.values()].filter(m => m.conversationId === conversation.id).map(m => m.sequence)) + 1;
  // Kept on the message, so giving the trip to another driver later does not change who an old message says sent it.
  const senderRoleLabel = isCarrierOrg(store.organizations.get(principal.organizationId)?.kind)
    ? carrierSenderRole(store, principal.userId, principal.organizationId, store.anchorTrips.get(shipment.anchorTripId)?.assignedDriverUserId)
    : undefined;
  const message: ConversationMessage = { id: randomUUID(), conversationId: conversation.id, sequence, senderUserId: principal.userId, senderOrgId: principal.organizationId, ...(senderRoleLabel ? { senderRoleLabel } : {}), body, clientRequestId: requestId, createdAtUtcMs: now };
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
