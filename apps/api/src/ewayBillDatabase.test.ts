import assert from "node:assert/strict";
import test from "node:test";
import { httpFixture } from "../test/httpFixtures.ts";

// Needs a disposable Postgres whose ShipmentRow already has the "ewayBill" JSONB column.
const databaseUrl = process.env.EWAY_BILL_TEST_DATABASE_URL;
const disposableDatabaseUrl = databaseUrl &&
  /^postgres(?:ql)?:\/\/[^/]*127\.0\.0\.1(?::\d+)?\/navig8r_eway_bill_test(?:\?.*)?$/.test(databaseUrl)
  ? databaseUrl
  : undefined;

test("PostgreSQL keeps an e-way bill across a save and reload, and a removed bill stays removed", {
  skip: !databaseUrl,
}, async t => {
  assert.ok(disposableDatabaseUrl, "EWAY_BILL_TEST_DATABASE_URL must target 127.0.0.1/navig8r_eway_bill_test");
  const previousDatabaseUrl = process.env.DATABASE_URL;
  process.env.DATABASE_URL = disposableDatabaseUrl;
  const f = await httpFixture(t);
  const id = (await f.book()).body.shipment.id as string;
  const bill = { kind: "BILL", billNumber: "123456789012", billDate: "2026-10-01", makerGstin: "29ABCDE1234F1Z5", invoiceNumber: "INV/1" };
  assert.equal((await f.request(`/shipments/${id}/eway-bill`, "POST", bill, f.tokens.shipperA)).status, 200);
  const database = await import("./persistenceDb.ts");
  t.after(async () => { await database.disconnectDatabase(); process.env.DATABASE_URL = previousDatabaseUrl; });
  await database.saveStoreToDatabase(f.store);
  assert.equal((await database.loadStoreFromDatabase()).shipments.get(id)?.ewayBill?.billNumber, "123456789012");
  assert.equal((await f.request(`/shipments/${id}/eway-bill/remove`, "POST", {}, f.tokens.shipperA)).status, 200);
  await database.saveStoreToDatabase(f.store);
  assert.equal((await database.loadStoreFromDatabase()).shipments.get(id)?.ewayBill, undefined);
});
