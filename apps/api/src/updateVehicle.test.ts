import assert from "node:assert/strict";
import test from "node:test";
import { createStore } from "./store.ts";
import {
  registerSoloOwnerOperatorDriver,
  updatePilotDriverVehicle,
} from "./services.ts";

test("updatePilotDriverVehicle updates primary vehicle fields", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Aazad Khan",
    phone: "9896966907",
    orgDisplayName: "MKM Cargo",
    vehicleRegistrationNumber: "HR",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });

  const out = updatePilotDriverVehicle(store, onboard.user.id, {
    vehicleRegistrationNumber: "HR26AB1234",
    vehicleClass: "LARGE",
    vehicleCapacityKg: 8000,
  });

  assert.equal(out.vehicle.id, onboard.vehicle.id);
  assert.equal(out.vehicle.registrationNumber, "HR26AB1234");
  assert.equal(out.vehicle.vehicleClass, "LARGE");
  assert.equal(out.vehicle.capacityKg, 8000);
  assert.equal(store.vehicles.get(onboard.vehicle.id)?.registrationNumber, "HR26AB1234");
});

test("updatePilotDriverVehicle allows partial updates", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Aazad Khan",
    phone: "9896966908",
    orgDisplayName: "MKM Cargo 2",
    vehicleRegistrationNumber: "HR26OLD",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });

  const out = updatePilotDriverVehicle(store, onboard.user.id, {
    vehicleRegistrationNumber: "HR26NEW",
  });

  assert.equal(out.vehicle.registrationNumber, "HR26NEW");
  assert.equal(out.vehicle.vehicleClass, "MEDIUM");
  assert.equal(out.vehicle.capacityKg, 4000);
});

test("updatePilotDriverVehicle rejects empty registration", () => {
  const store = createStore();
  const onboard = registerSoloOwnerOperatorDriver(store, {
    fullName: "Aazad Khan",
    phone: "9896966909",
    orgDisplayName: "MKM Cargo 3",
    vehicleRegistrationNumber: "HR26AB",
    vehicleClass: "MEDIUM",
    vehicleCapacityKg: 4000,
  });

  assert.throws(
    () => updatePilotDriverVehicle(store, onboard.user.id, { vehicleRegistrationNumber: "   " }),
    (e: unknown) => e instanceof Error && e.message === "invalid_vehicleRegistrationNumber",
  );
});
