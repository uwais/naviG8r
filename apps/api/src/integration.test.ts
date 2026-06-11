import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  acceptCarrierShipment,
  bookShipment,
  publishAnchorTripAsPilotDriver,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
  startAnchorTripAsPilot,
} from "./services.ts";
import {
  createIntegrationApiKey,
  createIntegrationLoad,
  listIntegrationEvents,
  updateIntegrationConnection,
} from "./integrationServices.ts";
import { buildIntegrationEventPayload } from "./integrationWebhooks.ts";
import { hashIntegrationSecret, resolveIntegrationAuth } from "./integrationAuth.ts";

const GURGAON = { lat: 28.4595, lng: 77.0266, label: "Gurugram" };
const JAIPUR = { lat: 26.9124, lng: 75.7873, label: "Jaipur" };

function seedOpenTrip(store: ReturnType<typeof createStore>) {
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Carrier ERP Test",
    phone: "9876543299",
    orgDisplayName: "Carrier ERP Test",
    vehicleRegistrationNumber: "HR26AB9999",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const trip = publishAnchorTripAsPilotDriver(store, {
    userId: onboard.user.id,
    orgId: onboard.org.id,
    originCity: "Gurugram",
    destCity: "Jaipur",
    origin: GURGAON,
    destination: JAIPUR,
    windowStart: "2026-04-24T00:00:00+05:30",
    windowEnd: "2026-04-25T23:59:59+05:30",
    vehicleClass: "MEDIUM",
    capacityKg: 1000,
  });
  return { trip, driver: onboard };
}

test("integration load create is idempotent by externalLoadId", async () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  seedOpenTrip(store);
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "ERP Admin",
    phone: "9111001199",
    orgDisplayName: "ERP Shipper Co",
  });
  const { token } = createIntegrationApiKey(store, admin.org.id);
  updateIntegrationConnection(store, admin.org.id, { paymentPolicy: "erp_preauthorized" });

  const ctx = resolveIntegrationAuth(store, { bearerToken: token });
  const params = {
    externalLoadId: "ERP-LOAD-001",
    weightKg: 120,
    pickupAddress: "Warehouse A, Gurugram",
    dropAddress: "Plant B, Jaipur",
    pickup: GURGAON,
    drop: JAIPUR,
    metadata: { poNumber: "PO-9912" },
  };

  const first = await createIntegrationLoad(store, ctx, params);
  assert.equal(first.created, true);
  assert.equal(first.shipment.externalLoadId, "ERP-LOAD-001");
  assert.equal(first.shipment.customerOrgId, admin.org.id);

  const second = await createIntegrationLoad(store, ctx, params);
  assert.equal(second.created, false);
  assert.equal(second.shipment.id, first.shipment.id);
});

test("integration events emit on carrier accept", () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  const { trip, driver } = seedOpenTrip(store);
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "ERP Admin",
    phone: "9111001198",
    orgDisplayName: "ERP Shipper 2",
  });
  updateIntegrationConnection(store, admin.org.id, {
    webhookUrl: "https://example.com/webhook",
    paymentPolicy: "erp_preauthorized",
  });

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: admin.org.displayName,
    customerOrg: { id: admin.org.id, displayName: admin.org.displayName },
    weightKg: 50,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
    pickup: GURGAON,
    drop: JAIPUR,
    externalLoadId: "ERP-002",
    integrationConnectionId: [...store.integrationConnections.values()].find((c) => c.orgId === admin.org.id)!.id,
  });

  const pay = store.payments.get(shipment.paymentId)!;
  store.payments.set(pay.id, { ...pay, status: "AUTHORIZED" });

  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });

  const events = listIntegrationEvents(store, admin.org.id, {});
  assert.ok(events.some((e) => e.eventType === "load.created"));
  assert.ok(events.some((e) => e.eventType === "load.carrier_accepted"));
  assert.ok([...store.integrationWebhookDeliveries.values()].length >= 1);
});

test("integration webhook payload includes trip start and carrier ops fields", () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  const { trip, driver } = seedOpenTrip(store);
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "ERP Admin",
    phone: "9111001196",
    orgDisplayName: "ERP Shipper 3",
  });

  const shipment = bookShipment(store, {
    anchorTripId: trip.id,
    customerOrgName: admin.org.displayName,
    customerOrg: { id: admin.org.id, displayName: admin.org.displayName },
    weightKg: 50,
    pickupAddress: "Gurugram",
    dropAddress: "Jaipur",
    pickup: GURGAON,
    drop: JAIPUR,
    externalLoadId: "ERP-003",
  });

  acceptCarrierShipment(store, { shipmentId: shipment.id, userId: driver.user.id });
  startAnchorTripAsPilot(store, { userId: driver.user.id, tripId: trip.id });

  const updated = store.shipments.get(shipment.id)!;
  const inTransit = listIntegrationEvents(store, admin.org.id, {}).find((e) => e.eventType === "load.in_transit");
  assert.ok(inTransit);

  const payload = buildIntegrationEventPayload(store, {
    eventType: "load.in_transit",
    shipment: updated,
    sequence: updated.integrationSequence ?? 1,
  });

  const tripPayload = payload.trip as Record<string, unknown>;
  assert.ok(typeof tripPayload.startedAtUtcMs === "number");

  const carrier = payload.carrier as Record<string, unknown>;
  assert.equal(carrier.name, driver.org.displayName);
  assert.equal(carrier.vehicleNumber, "HR26AB9999");
  assert.equal(carrier.driverName, driver.user.fullName);
});

test("resolveIntegrationAuth accepts X-Api-Key headers", () => {
  process.env.AUTH_SECRET = "test-secret-min-16-chars!!";
  const store = createStore();
  const admin = registerCustomerOrgAdmin(store, {
    fullName: "Key User",
    phone: "9111001197",
    orgDisplayName: "Key Co",
  });
  const { key, token } = createIntegrationApiKey(store, admin.org.id);
  const parsed = token.match(/^nvg8r_([a-f0-9]+)_(.+)$/);
  assert.ok(parsed);
  const ctx = resolveIntegrationAuth(store, {
    apiKey: parsed![1],
    apiSecret: parsed![2],
  });
  assert.equal(ctx.orgId, admin.org.id);
  assert.equal(key.secretHash, hashIntegrationSecret(parsed![2]!));
});
