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

export type Store = {
  version: 4;
  carriers: Map<string, Carrier>;
  organizations: Map<string, Organization>;
  users: Map<string, User>;
  memberships: Map<string, Membership>; // key: `${userId}:${orgId}`
  vehicles: Map<string, Vehicle>;
  driverProfiles: Map<string, DriverProfile>; // key: userId (pilot assumes one profile per user)
  otpChallenges: Map<string, OtpChallenge>;
  authSessions: Map<string, AuthSession>;
  anchorTrips: Map<string, AnchorTrip>;
  shipments: Map<string, Shipment>;
  payments: Map<string, Payment>;
  ledgerLines: Map<string, LedgerLine>;
  payoutBatches: Map<string, PayoutBatch>;
  integrationConnections: Map<string, IntegrationConnection>;
  integrationApiKeys: Map<string, IntegrationApiKey>;
  integrationIdempotency: Map<string, IntegrationIdempotencyRecord>;
  integrationEvents: Map<string, IntegrationEvent>;
  integrationWebhookDeliveries: Map<string, IntegrationWebhookDelivery>;
};

export function createStore(): Store {
  return {
    version: 4,
    carriers: new Map(),
    organizations: new Map(),
    users: new Map(),
    memberships: new Map(),
    vehicles: new Map(),
    driverProfiles: new Map(),
    otpChallenges: new Map(),
    authSessions: new Map(),
    anchorTrips: new Map(),
    shipments: new Map(),
    payments: new Map(),
    ledgerLines: new Map(),
    payoutBatches: new Map(),
    integrationConnections: new Map(),
    integrationApiKeys: new Map(),
    integrationIdempotency: new Map(),
    integrationEvents: new Map(),
    integrationWebhookDeliveries: new Map(),
  };
}
