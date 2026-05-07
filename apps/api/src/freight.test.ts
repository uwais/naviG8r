import assert from "node:assert/strict";
import test from "node:test";
import {
  ApiError,
  computeFreightGrossPaise,
  pilotRatesEstimate,
  quoteShipmentMarketplace,
  registerCustomerOrgAdmin,
  registerSoloOwnerOperatorDriver,
} from "./services.ts";
import { createStore } from "./store.ts";

test("computeFreightGrossPaise — weight_only when no distance", () => {
  const { grossPaise, breakdown } = computeFreightGrossPaise({
    weightKg: 10,
    vehicleClass: "MEDIUM",
    laneKm: null,
    shipmentKm: null,
  });
  assert.equal(grossPaise, 5000);
  assert.equal(breakdown.pricingMode, "weight_only");
  assert.equal(breakdown.distanceKmForPrice, null);
});

test("computeFreightGrossPaise — prefers shipmentKm over laneKm", () => {
  const prev = process.env.FREIGHT_PAISE_PER_KM_SMALL;
  process.env.FREIGHT_PAISE_PER_KM_SMALL = "1000";
  try {
    const { grossPaise, breakdown } = computeFreightGrossPaise({
      weightKg: 50,
      vehicleClass: "SMALL",
      laneKm: 1000,
      shipmentKm: 10,
    });
    assert.equal(breakdown.distanceKmForPrice, 10);
    assert.equal(breakdown.distanceComponentPaise, 10000);
    assert.equal(breakdown.weightComponentPaise, 25000);
    assert.equal(grossPaise, 35000);
  } finally {
    process.env.FREIGHT_PAISE_PER_KM_SMALL = prev;
  }
});

test("quoteShipmentMarketplace — rejects partial pickup/drop", () => {
  const store = createStore();
  assert.throws(
    () => quoteShipmentMarketplace(store, { weightKg: 10, pickup: { lat: 1, lng: 2 } }),
    (e: unknown) =>
      e instanceof ApiError && e.message === "pickup_drop_both_required",
  );
});

test("pilotRatesEstimate requires carrier membership", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Ravi Kumar",
    phone: "9876543214",
    orgDisplayName: "Ravi Transport",
    vehicleRegistrationNumber: "HR26AB9999",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 5000,
  });
  const cust = registerCustomerOrgAdmin(store, {
    fullName: "ACME Ops",
    phone: "9123456700",
    orgDisplayName: "ACME",
  });

  pilotRatesEstimate(store, onboard.user.id, {
    origin: { lat: 28.4, lng: 77.0 },
    destination: { lat: 26.9, lng: 75.7 },
    vehicleClass: "MEDIUM",
  });

  assert.throws(
    () =>
      pilotRatesEstimate(store, cust.user.id, {
        origin: { lat: 28.4, lng: 77.0 },
        destination: { lat: 26.9, lng: 75.7 },
      }),
    (e: unknown) =>
      e instanceof ApiError && e.message === "pilot_carrier_required" && e.httpStatus === 403,
  );
});
