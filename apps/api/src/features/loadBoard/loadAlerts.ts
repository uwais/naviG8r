/**
 * What the Load Board tells people, and who turned it off. A new load tells every approved carrier office member
 * with load alerts on; a route made for a load tells the posting shipper company's members, as a booking notice
 * would. Never a driver, never an amount, never the shipper's name to a carrier (owner, 4 Nov 2026).
 * Each notice goes to the inbox and to the push queue, which sends it only to phones with push turned on.
 */
import { randomUUID } from "node:crypto";
import { enqueuePushIntentForNotification } from "../push/push.ts";
import type { Store } from "../../store.ts";
import type { AnchorTrip, Notification } from "../../types.ts";
import { isApprovedCarrierOffice, isShipperMember } from "./loadBoardAudience.ts";
import { indiaToday, type PostedLoad } from "./postedLoad.ts";

export const POSTED_LOAD_NEW_EVENT = "posted_load.new";
export const POSTED_LOAD_ROUTE_MADE_EVENT = "posted_load.route_made";

const SHORT_MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
/** "6 Nov" from 2026-11-06, as the app writes a short date. */
function shortDay(day: string): string {
  const [, month, date] = day.split("-").map(Number);
  return `${date} ${SHORT_MONTHS[month! - 1]}`;
}

function pickupDays(load: PostedLoad): string {
  return load.earliestPickupDate === load.latestPickupDate
    ? shortDay(load.earliestPickupDate)
    : `${shortDay(load.earliestPickupDate)} to ${shortDay(load.latestPickupDate)}`;
}

/** On unless the user turned it off. */
export function loadAlertsOn(store: Store, userId: string): boolean {
  return store.loadAlertSettings.get(userId)?.loadAlertsOn ?? true;
}

export function setLoadAlerts(store: Store, userId: string, on: boolean, nowUtcMs = Date.now()): void {
  store.loadAlertSettings.set(userId, { userId, loadAlertsOn: on, updatedAtUtcMs: nowUtcMs });
}

// No check for an earlier copy: each event id names a load or route just made, and memberships hold each person
// once per company, so a repeat cannot exist.
function notify(store: Store, load: PostedLoad, recipient: { userId: string; orgId: string; audience: "SHIPPER" | "CARRIER" }, eventKey: string, eventId: string, title: string, body: string, nowUtcMs: number): void {
  const notification: Notification = {
    id: randomUUID(), recipientSequence: ++store.notificationSequence,
    eventId, eventKey, recipientUserId: recipient.userId, recipientOrgId: recipient.orgId,
    shipmentId: "", postedLoadId: load.id, createdAtUtcMs: nowUtcMs,
    data: { postedLoadId: load.id, audience: recipient.audience, title, body },
  };
  store.notifications.set(notification.id, notification);
  enqueuePushIntentForNotification(store, notification);
}

/** Every owner or dispatcher of an approved carrier, except the poster and anyone with load alerts off. */
export function alertCarriersOfNewLoad(store: Store, load: PostedLoad, nowUtcMs = Date.now()): void {
  const body = `${load.from.city} to ${load.to.city}, ${load.weightKg.toLocaleString("en-IN")} kg, pickup ${pickupDays(load)}.`;
  for (const membership of store.memberships.values()) {
    const { userId, orgId } = membership;
    if (userId === load.postedByUserId || !loadAlertsOn(store, userId) || !isApprovedCarrierOffice(store, userId, orgId)) continue;
    notify(store, load, { userId, orgId, audience: "CARRIER" }, POSTED_LOAD_NEW_EVENT, `${POSTED_LOAD_NEW_EVENT}:${load.id}`, "New load on the Load Board", body, nowUtcMs);
  }
}

/** The posting shipper company's members, except whoever made the route (a person in both companies). */
export function alertShipperOfRoute(store: Store, load: PostedLoad, trip: AnchorTrip, madeByUserId: string, nowUtcMs = Date.now()): void {
  const carrierName = store.organizations.get(trip.carrierId)?.displayName?.trim() || "A carrier";
  const leavesUtcMs = Date.parse(trip.windowStart);
  const leaves = Number.isNaN(leavesUtcMs) ? "" : `, leaves ${shortDay(indiaToday(leavesUtcMs))}`;
  const body = `${carrierName} made a route from ${trip.originCity} to ${trip.destCity}${leaves}. Open My loads to book it.`;
  for (const membership of store.memberships.values()) {
    const { userId, orgId } = membership;
    if (orgId !== load.shipperOrgId || userId === madeByUserId || !isShipperMember(store, userId, orgId)) continue;
    notify(store, load, { userId, orgId, audience: "SHIPPER" }, POSTED_LOAD_ROUTE_MADE_EVENT, `${POSTED_LOAD_ROUTE_MADE_EVENT}:${trip.id}`, "A carrier made a route for your load", body, nowUtcMs);
  }
}
