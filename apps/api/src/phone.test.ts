import assert from "node:assert/strict";
import test from "node:test";

import { DEFAULT_COUNTRY_CODE, findUserByPhone, normalizePhone } from "./phone.ts";
import { registerCustomerUser } from "./services.ts";
import { createStore } from "./store.ts";

test("phone parsing defaults legacy national numbers to India", () => {
  assert.deepEqual(normalizePhone("98765 43210"), {
    countryCode: DEFAULT_COUNTRY_CODE,
    phone: "9876543210",
    e164: "+919876543210",
    key: "+91:9876543210",
  });
  assert.equal(normalizePhone("+919876543210").countryCode, "+91");
});

test("US and India identities may share national digits without colliding", () => {
  const store = createStore();
  const india = registerCustomerUser(store, {
    fullName: "India user",
    phone: "2025550100",
    countryCode: "+91",
  });
  const us = registerCustomerUser(store, {
    fullName: "US user",
    phone: "2025550100",
    countryCode: "+1",
  });

  assert.notEqual(india.user.id, us.user.id);
  assert.equal(findUserByPhone(store, "+912025550100")?.id, india.user.id);
  assert.equal(findUserByPhone(store, "+12025550100")?.id, us.user.id);
});

test("an explicit international number cannot be paired with another country code", () => {
  assert.throws(
    () => normalizePhone("+12025550100", "+91"),
    /phone_country_mismatch/,
  );
});
