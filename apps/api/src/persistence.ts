import fs from "node:fs";
import path from "node:path";
import { createStore, type Store } from "./store.ts";
import type {
  AnchorTrip,
  AuthSession,
  Carrier,
  DriverProfile,
  IntegrationApiKey,
  IntegrationConnection,
  IntegrationEvent,
  IntegrationIdempotencyRecord,
  IntegrationWebhookDelivery,
  LedgerLine,
  Membership,
  Organization,
  OtpChallenge,
  PayoutBatch,
  Payment,
  Shipment,
  User,
  Vehicle,
} from "./types.ts";

function normalizeHydratedPayment(raw: Payment): Payment {
  const p = raw as Payment & { provider?: Payment["provider"] };
  return {
    ...p,
    provider: p.provider ?? "MOCK",
  };
}

type StoreJsonV1 = {
  version: 1;
  carriers: Carrier[];
  anchorTrips: AnchorTrip[];
  shipments: Shipment[];
  payments?: Payment[];
  ledgerLines: LedgerLine[];
  payoutBatches: PayoutBatch[];
};

type StoreJsonV2 = {
  version: 2;
  carriers: Carrier[];
  organizations: Organization[];
  users: User[];
  memberships: Membership[];
  vehicles: Vehicle[];
  driverProfiles: DriverProfile[];
  anchorTrips: AnchorTrip[];
  shipments: Shipment[];
  payments: Payment[];
  ledgerLines: LedgerLine[];
  payoutBatches: PayoutBatch[];
};

type StoreJsonV3 = {
  version: 3;
  carriers: Carrier[];
  organizations: Organization[];
  users: User[];
  memberships: Membership[];
  vehicles: Vehicle[];
  driverProfiles: DriverProfile[];
  otpChallenges: OtpChallenge[];
  authSessions: AuthSession[];
  anchorTrips: AnchorTrip[];
  shipments: Shipment[];
  payments: Payment[];
  ledgerLines: LedgerLine[];
  payoutBatches: PayoutBatch[];
};

type StoreJsonV4 = StoreJsonV3 & {
  version: 4;
  integrationConnections: IntegrationConnection[];
  integrationApiKeys: IntegrationApiKey[];
  integrationIdempotency: IntegrationIdempotencyRecord[];
  integrationEvents: IntegrationEvent[];
  integrationWebhookDeliveries: IntegrationWebhookDelivery[];
};

function dumpStore(store: Store): StoreJsonV4 {
  return {
    version: 4,
    carriers: [...store.carriers.values()],
    organizations: [...store.organizations.values()],
    users: [...store.users.values()],
    memberships: [...store.memberships.values()],
    vehicles: [...store.vehicles.values()],
    driverProfiles: [...store.driverProfiles.values()],
    otpChallenges: [...store.otpChallenges.values()],
    authSessions: [...store.authSessions.values()],
    anchorTrips: [...store.anchorTrips.values()],
    shipments: [...store.shipments.values()],
    payments: [...store.payments.values()],
    ledgerLines: [...store.ledgerLines.values()],
    payoutBatches: [...store.payoutBatches.values()],
    integrationConnections: [...store.integrationConnections.values()],
    integrationApiKeys: [...store.integrationApiKeys.values()],
    integrationIdempotency: [...store.integrationIdempotency.values()],
    integrationEvents: [...store.integrationEvents.values()],
    integrationWebhookDeliveries: [...store.integrationWebhookDeliveries.values()],
  };
}

function membershipKey(userId: string, orgId: string): string {
  return `${userId}:${orgId}`;
}

function hydrateIntegrationMaps(
  store: Store,
  json: {
    integrationConnections?: IntegrationConnection[];
    integrationApiKeys?: IntegrationApiKey[];
    integrationIdempotency?: IntegrationIdempotencyRecord[];
    integrationEvents?: IntegrationEvent[];
    integrationWebhookDeliveries?: IntegrationWebhookDelivery[];
  },
): void {
  for (const c of json.integrationConnections ?? []) store.integrationConnections.set(c.id, c);
  for (const k of json.integrationApiKeys ?? []) store.integrationApiKeys.set(k.id, k);
  for (const r of json.integrationIdempotency ?? []) store.integrationIdempotency.set(r.key, r);
  for (const e of json.integrationEvents ?? []) store.integrationEvents.set(e.id, e);
  for (const d of json.integrationWebhookDeliveries ?? []) store.integrationWebhookDeliveries.set(d.id, d);
}

function hydrateStoreV4(json: StoreJsonV4): Store {
  const store = createStore();
  for (const c of json.carriers ?? []) store.carriers.set(c.id, c);
  for (const o of json.organizations ?? []) store.organizations.set(o.id, o);
  for (const u of json.users ?? []) store.users.set(u.id, u);
  for (const m of json.memberships ?? []) store.memberships.set(membershipKey(m.userId, m.orgId), m);
  for (const v of json.vehicles ?? []) store.vehicles.set(v.id, v);
  for (const d of json.driverProfiles ?? []) store.driverProfiles.set(d.userId, d);
  for (const o of json.otpChallenges ?? []) store.otpChallenges.set(o.id, o);
  for (const s of json.authSessions ?? []) store.authSessions.set(s.id, s);
  for (const t of json.anchorTrips ?? []) store.anchorTrips.set(t.id, t);
  for (const s of json.shipments ?? []) store.shipments.set(s.id, s);
  for (const pr of json.payments ?? []) store.payments.set(pr.id, normalizeHydratedPayment(pr));
  for (const l of json.ledgerLines ?? []) store.ledgerLines.set(l.id, l);
  for (const b of json.payoutBatches ?? []) store.payoutBatches.set(b.id, b);
  hydrateIntegrationMaps(store, json);
  return store;
}

function hydrateStoreV3(json: StoreJsonV3): Store {
  return hydrateStoreV4({
    ...json,
    version: 4,
    integrationConnections: [],
    integrationApiKeys: [],
    integrationIdempotency: [],
    integrationEvents: [],
    integrationWebhookDeliveries: [],
  });
}

function migrateV2JsonToStore(json: StoreJsonV2): Store {
  return hydrateStoreV3({
    version: 3,
    carriers: json.carriers ?? [],
    organizations: json.organizations ?? [],
    users: json.users ?? [],
    memberships: json.memberships ?? [],
    vehicles: json.vehicles ?? [],
    driverProfiles: json.driverProfiles ?? [],
    otpChallenges: [],
    authSessions: [],
    anchorTrips: json.anchorTrips ?? [],
    shipments: json.shipments ?? [],
    payments: json.payments ?? [],
    ledgerLines: json.ledgerLines ?? [],
    payoutBatches: json.payoutBatches ?? [],
  });
}

function migrateV1ToStore(v1: StoreJsonV1): Store {
  const store = hydrateStoreV3({
    version: 3,
    carriers: v1.carriers ?? [],
    organizations: [],
    users: [],
    memberships: [],
    vehicles: [],
    driverProfiles: [],
    otpChallenges: [],
    authSessions: [],
    anchorTrips: v1.anchorTrips ?? [],
    shipments: v1.shipments ?? [],
    payments: v1.payments ?? [],
    ledgerLines: v1.ledgerLines ?? [],
    payoutBatches: v1.payoutBatches ?? [],
  });

  for (const c of v1.carriers ?? []) {
    if (!store.organizations.has(c.id)) {
      store.organizations.set(c.id, {
        id: c.id,
        kind: "CARRIER_LEGACY",
        displayName: c.name,
        kycStatus: "NOT_STARTED",
        createdAtUtcMs: c.createdAtUtcMs,
      });
    }
  }

  return store;
}

export function loadStoreFromDisk(dataFilePath: string): Store {
  try {
    const raw = fs.readFileSync(dataFilePath, "utf8");
    const parsed = JSON.parse(raw) as StoreJsonV1 | StoreJsonV2 | StoreJsonV3 | StoreJsonV4;
    if (parsed?.version === 1) return migrateV1ToStore(parsed);
    if (parsed?.version === 2) return migrateV2JsonToStore(parsed);
    if (parsed?.version === 3) return hydrateStoreV3(parsed);
    if (parsed?.version === 4) return hydrateStoreV4(parsed);
    throw new Error("unsupported_store_version");
  } catch (e: any) {
    if (e?.code === "ENOENT") return createStore();
    throw e;
  }
}

export function saveStoreToDisk(dataFilePath: string, store: Store): void {
  const dir = path.dirname(dataFilePath);
  fs.mkdirSync(dir, { recursive: true });

  const tmp = `${dataFilePath}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(dumpStore(store), null, 2), "utf8");
  fs.renameSync(tmp, dataFilePath);
}
