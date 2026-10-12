import { createCipheriv, createDecipheriv, createHash, randomBytes, randomUUID } from "node:crypto";
import type { Store } from "../../store.ts";
import { effectivePermissions, legacyRoles } from "../../rbac.ts";
import { isActiveEntity } from "../../softDelete.ts";
import type { Notification, PushDevice, PushDelivery, PushIntent } from "../../types.ts";
import type { FcmDeliveryMessage, FcmSendResult } from "./fcmSender.ts";

const PUSH_INTENT_TTL_MS = 24 * 60 * 60 * 1000;
const PUSH_RETRY_HORIZON_MS = 6 * 60 * 60 * 1000;
const PUSH_MAX_ATTEMPTS = 8;
const PUSH_LEASE_MS = 30_000;
const PUSH_MAX_BACKOFF_MS = 60 * 60 * 1000;
let cleanupDeliveryCursor: string | null = null;
let cleanupIntentCursor: string | null = null;
let cleanupDeviceCursor: string | null = null;

function nextCleanupPage<T>(map: Map<string, T>, cursor: string | null, limit: number): {
  entries: Array<[string, T]>;
  cursor: string | null;
} {
  const all = [...map.entries()].sort(([left], [right]) => left.localeCompare(right));
  if (all.length === 0) return { entries: [], cursor: null };
  const found = cursor == null ? 0 : all.findIndex(([id]) => id > cursor);
  const start = found < 0 ? 0 : found;
  const entries: Array<[string, T]> = [];
  for (let offset = 0; offset < Math.min(limit, all.length); offset++) {
    entries.push(all[(start + offset) % all.length]!);
  }
  return { entries, cursor: entries.at(-1)?.[0] ?? cursor };
}

export function pushFlagEnabled(name: "PUSH_DEVICE_REGISTRATION_ENABLED" | "PUSH_ENQUEUE_ENABLED" | "PUSH_SENDER_ENABLED"): boolean {
  return process.env[name] === "1";
}

export function pushEnvironment(): PushDevice["environment"] {
  const configured = process.env.PUSH_ENVIRONMENT?.trim().toUpperCase();
  if (configured === "DEVELOPMENT" || configured === "PRODUCTION") return configured;
  return process.env.NODE_ENV === "production" ? "PRODUCTION" : "DEVELOPMENT";
}

function encryptionKey(): Buffer {
  const encoded = process.env.PUSH_TOKEN_ENCRYPTION_KEY?.trim();
  if (!encoded) throw new Error("push_token_encryption_not_configured");
  const key = Buffer.from(encoded, "base64");
  if (key.length !== 32) throw new Error("push_token_encryption_key_invalid");
  return key;
}

export function assertPushTokenEncryptionConfigured(): void {
  void encryptionKey();
}

export function encryptPushToken(token: string): string {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", encryptionKey(), nonce);
  const ciphertext = Buffer.concat([cipher.update(token, "utf8"), cipher.final()]);
  return `v1:${nonce.toString("base64")}:${cipher.getAuthTag().toString("base64")}:${ciphertext.toString("base64")}`;
}

export function decryptPushToken(encoded: string): string {
  const [version, nonceText, tagText, ciphertextText] = encoded.split(":");
  if (version !== "v1" || !nonceText || !tagText || !ciphertextText) throw new Error("push_token_ciphertext_invalid");
  const decipher = createDecipheriv("aes-256-gcm", encryptionKey(), Buffer.from(nonceText, "base64"));
  decipher.setAuthTag(Buffer.from(tagText, "base64"));
  return Buffer.concat([decipher.update(Buffer.from(ciphertextText, "base64")), decipher.final()]).toString("utf8");
}

export function hashPushToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export function registerPushDevice(store: Store, input: {
  userId: string;
  installationId: string;
  token: string;
  consented: boolean;
  permissionGranted: boolean;
  channelEnabled: boolean;
  nowUtcMs?: number;
}): PushDevice {
  if (!pushFlagEnabled("PUSH_DEVICE_REGISTRATION_ENABLED")) throw new Error("push_registration_disabled");
  if (!input.consented || !input.permissionGranted || !input.channelEnabled) throw new Error("push_opt_in_required");
  const now = input.nowUtcMs ?? Date.now();
  const tokenHash = hashPushToken(input.token);
  const existing = [...store.pushDevices.values()].find(d => d.installationId === input.installationId);
  const conflictingToken = [...store.pushDevices.values()].find(d => d.tokenHash === tokenHash && d.id !== existing?.id && d.revokedAtUtcMs == null);
  if (conflictingToken) throw new Error("push_token_already_registered");

  if (existing) {
    const reassigned = existing.userId !== input.userId;
    const otherActiveInstallations = [...store.pushDevices.values()].filter(d =>
      d.id !== existing.id && d.userId === input.userId && d.revokedAtUtcMs == null,
    ).length;
    if (otherActiveInstallations >= 5) {
      throw new Error("push_device_limit_reached");
    }
    const rotated = existing.tokenHash !== tokenHash;
    const value: PushDevice = {
      ...existing,
      userId: input.userId,
      tokenCiphertext: encryptPushToken(input.token),
      tokenHash,
      environment: pushEnvironment(),
      consentedAtUtcMs: now,
      permissionGrantedHint: true,
      channelEnabledHint: true,
      ownershipGeneration: existing.ownershipGeneration + (reassigned || rotated || existing.revokedAtUtcMs != null ? 1 : 0),
      updatedAtUtcMs: now,
      lastSeenAtUtcMs: now,
      revokedAtUtcMs: null,
    };
    store.pushDevices.set(value.id, value);
    return value;
  }

  const activeInstallations = [...store.pushDevices.values()].filter(d => d.userId === input.userId && d.revokedAtUtcMs == null).length;
  if (activeInstallations >= 5) throw new Error("push_device_limit_reached");
  const value: PushDevice = {
    id: randomUUID(),
    installationId: input.installationId,
    userId: input.userId,
    platform: "ANDROID",
    tokenCiphertext: encryptPushToken(input.token),
    tokenHash,
    environment: pushEnvironment(),
    consentedAtUtcMs: now,
    permissionGrantedHint: true,
    channelEnabledHint: true,
    ownershipGeneration: 1,
    createdAtUtcMs: now,
    updatedAtUtcMs: now,
    lastSeenAtUtcMs: now,
    revokedAtUtcMs: null,
  };
  store.pushDevices.set(value.id, value);
  return value;
}

export function revokePushDevice(store: Store, input: {
  userId: string;
  deviceId: string;
  ownershipGeneration: number;
  nowUtcMs?: number;
}): boolean {
  const device = store.pushDevices.get(input.deviceId);
  if (!device || device.userId !== input.userId || device.ownershipGeneration !== input.ownershipGeneration || device.revokedAtUtcMs != null) return false;
  const now = input.nowUtcMs ?? Date.now();
  store.pushDevices.set(device.id, {
    ...device,
    tokenCiphertext: "",
    tokenHash: "",
    permissionGrantedHint: false,
    channelEnabledHint: false,
    ownershipGeneration: device.ownershipGeneration + 1,
    updatedAtUtcMs: now,
    revokedAtUtcMs: now,
  });
  return true;
}

function presentationKey(notification: Notification): string {
  const value = `${notification.recipientUserId}\n${notification.recipientOrgId}\n${notification.shipmentId}`;
  return createHash("sha256").update(value).digest("hex").slice(0, 32);
}

export function enqueuePushIntentForNotification(store: Store, notification: Notification): PushIntent | null {
  if (!pushFlagEnabled("PUSH_ENQUEUE_ENABLED")) return null;
  const existing = [...store.pushIntents.values()].find(i => i.notificationId === notification.id);
  if (existing) return existing;
  const intent: PushIntent = {
    id: randomUUID(),
    notificationId: notification.id,
    recipientUserId: notification.recipientUserId,
    recipientOrgId: notification.recipientOrgId,
    shipmentId: notification.shipmentId,
    presentationKey: presentationKey(notification),
    createdAtUtcMs: notification.createdAtUtcMs,
    expiresAtUtcMs: notification.createdAtUtcMs + PUSH_INTENT_TTL_MS,
  };
  store.pushIntents.set(intent.id, intent);
  const environment = pushEnvironment();
  for (const device of store.pushDevices.values()) {
    if (device.userId !== notification.recipientUserId || device.environment !== environment || device.revokedAtUtcMs != null || !device.permissionGrantedHint || !device.channelEnabledHint) continue;
    const id = `${notification.id}:${device.id}:${device.ownershipGeneration}`;
    if (store.pushDeliveries.has(id)) continue;
    const delivery: PushDelivery = {
      id,
      intentId: intent.id,
      deviceId: device.id,
      ownershipGeneration: device.ownershipGeneration,
      status: "PENDING",
      attempts: 0,
      nextAttemptAtUtcMs: notification.createdAtUtcMs,
      leaseId: null,
      leaseUntilUtcMs: null,
      providerAcceptedAtUtcMs: null,
      lastErrorCode: null,
      createdAtUtcMs: notification.createdAtUtcMs,
      updatedAtUtcMs: notification.createdAtUtcMs,
    };
    store.pushDeliveries.set(delivery.id, delivery);
  }
  return intent;
}

export type PushDeliveryClaim = {
  delivery: PushDelivery;
  intent: PushIntent;
  device: PushDevice;
  notification: Notification;
};

export function claimPushDeliveries(store: Store, options: { nowUtcMs?: number; limit?: number; leaseMs?: number } = {}): {
  claims: PushDeliveryClaim[];
  changed: boolean;
} {
  const now = options.nowUtcMs ?? Date.now();
  const limit = Math.max(1, Math.min(20, options.limit ?? 4));
  const leaseMs = options.leaseMs ?? PUSH_LEASE_MS;
  const claims: PushDeliveryClaim[] = [];
  let changed = false;

  for (const delivery of store.pushDeliveries.values()) {
    if (claims.length >= limit) break;
    if (delivery.status !== "PENDING" || delivery.nextAttemptAtUtcMs > now || (delivery.leaseUntilUtcMs ?? 0) > now) continue;
    const intent = store.pushIntents.get(delivery.intentId);
    const device = store.pushDevices.get(delivery.deviceId);
    const notification = intent ? store.notifications.get(intent.notificationId) : undefined;
    if (!intent || !device || !notification || delivery.attempts >= PUSH_MAX_ATTEMPTS || now >= intent.expiresAtUtcMs || now - intent.createdAtUtcMs >= PUSH_RETRY_HORIZON_MS) {
      store.pushDeliveries.set(delivery.id, { ...delivery, status: "EXPIRED", lastErrorCode: delivery.attempts >= PUSH_MAX_ATTEMPTS ? "ATTEMPT_LIMIT" : delivery.lastErrorCode, leaseId: null, leaseUntilUtcMs: null, updatedAtUtcMs: now });
      changed = true;
      continue;
    }
    if (!eligibleCurrentRecipient(store, notification, device, delivery.ownershipGeneration)) {
      store.pushDeliveries.set(delivery.id, { ...delivery, status: "SUPPRESSED", leaseId: null, leaseUntilUtcMs: null, updatedAtUtcMs: now });
      changed = true;
      continue;
    }

    const leaseId = randomUUID();
    const claimed: PushDelivery = {
      ...delivery,
      attempts: delivery.attempts + 1,
      leaseId,
      leaseUntilUtcMs: now + leaseMs,
      updatedAtUtcMs: now,
    };
    store.pushDeliveries.set(claimed.id, claimed);
    claims.push({
      delivery: structuredClone(claimed),
      intent: structuredClone(intent),
      device: structuredClone(device),
      notification: structuredClone(notification),
    });
    changed = true;
  }
  return { claims, changed };
}

function eligibleCurrentRecipient(store: Store, notification: Notification, device: PushDevice, generation: number): boolean {
  if (device.revokedAtUtcMs != null || device.ownershipGeneration !== generation || device.userId !== notification.recipientUserId ||
      device.environment !== pushEnvironment() || !device.permissionGrantedHint || !device.channelEnabledHint || !device.consentedAtUtcMs) return false;
  const shipment = store.shipments.get(notification.shipmentId);
  const membership = store.memberships.get(`${notification.recipientUserId}:${notification.recipientOrgId}`);
  const organization = store.organizations.get(notification.recipientOrgId);
  const user = store.users.get(notification.recipientUserId);
  if (!shipment || !isActiveEntity(shipment) || !isActiveEntity(membership) || !isActiveEntity(organization) || !isActiveEntity(user)) return false;
  const role = notification.recipientOrgId === shipment.customerOrgId ? "SHIPPER"
    : notification.recipientOrgId === shipment.carrierId ? "CARRIER" : null;
  if (!role) return false;
  const roles = store.membershipRoles.get(`${notification.recipientUserId}:${notification.recipientOrgId}`) ?? legacyRoles(membership!, organization!);
  return roles.includes(role) && effectivePermissions(roles, membership!.role).includes("notification.read");
}

export function pushFcmMessage(claim: PushDeliveryClaim, token: string, now = Date.now()): FcmDeliveryMessage {
  return {
    token,
    notificationId: claim.notification.id,
    presentationKey: claim.intent.presentationKey,
    ttlMs: Math.max(0, Math.min(PUSH_INTENT_TTL_MS, claim.intent.expiresAtUtcMs - now)),
  };
}

export function completePushDelivery(store: Store, claim: PushDeliveryClaim, result: FcmSendResult, options: {
  nowUtcMs?: number;
  random?: () => number;
} = {}): boolean {
  const now = options.nowUtcMs ?? Date.now();
  const current = store.pushDeliveries.get(claim.delivery.id);
  if (!current || current.leaseId !== claim.delivery.leaseId || current.ownershipGeneration !== claim.delivery.ownershipGeneration) return false;
  const common = { ...current, leaseId: null, leaseUntilUtcMs: null, updatedAtUtcMs: now };
  const currentDevice = store.pushDevices.get(claim.device.id);
  if (!currentDevice || currentDevice.ownershipGeneration !== claim.device.ownershipGeneration || currentDevice.userId !== claim.device.userId || currentDevice.revokedAtUtcMs != null) {
    store.pushDeliveries.set(current.id, { ...common, status: "SUPPRESSED", lastErrorCode: "DEVICE_OWNERSHIP_CHANGED" });
    return true;
  }
  if (result.kind === "accepted") {
    store.pushDeliveries.set(current.id, { ...common, status: "ACCEPTED", providerAcceptedAtUtcMs: now, lastErrorCode: null });
    return true;
  }
  if (result.kind === "invalid_token") {
    store.pushDeliveries.set(current.id, { ...common, status: "INVALID_TOKEN", lastErrorCode: result.errorCode });
    const device = store.pushDevices.get(claim.device.id);
    if (device && device.ownershipGeneration === claim.device.ownershipGeneration && device.tokenHash === claim.device.tokenHash) {
      store.pushDevices.set(device.id, {
        ...device,
        tokenCiphertext: "",
        tokenHash: "",
        ownershipGeneration: device.ownershipGeneration + 1,
        permissionGrantedHint: false,
        channelEnabledHint: false,
        revokedAtUtcMs: now,
        updatedAtUtcMs: now,
      });
    }
    return true;
  }
  if (result.kind === "permanent") {
    store.pushDeliveries.set(current.id, { ...common, status: "PERMANENT_FAILURE", lastErrorCode: result.errorCode.slice(0, 64) });
    return true;
  }

  const base = result.quota ? 60_000 : 10_000;
  const exponential = Math.min(PUSH_MAX_BACKOFF_MS, base * 2 ** Math.max(0, current.attempts - 1));
  const jitter = exponential * (0.8 + Math.max(0, Math.min(1, options.random?.() ?? Math.random())) * 0.4);
  const delay = Math.max(base, Math.ceil(jitter), result.retryAfterMs ?? 0);
  const retryAt = now + delay;
  const intent = store.pushIntents.get(current.intentId);
  if (!intent || current.attempts >= PUSH_MAX_ATTEMPTS || now - (intent?.createdAtUtcMs ?? now) >= PUSH_RETRY_HORIZON_MS || retryAt >= (intent?.expiresAtUtcMs ?? now)) {
    store.pushDeliveries.set(current.id, { ...common, status: "EXPIRED", lastErrorCode: result.errorCode.slice(0, 64) });
  } else {
    store.pushDeliveries.set(current.id, {
      ...common,
      status: "PENDING",
      nextAttemptAtUtcMs: retryAt,
      lastErrorCode: result.errorCode.slice(0, 64),
    });
  }
  return true;
}

export function cleanupPushState(store: Store, now = Date.now(), limit = 500): number {
  const retentionCutoff = now - 30 * 24 * 60 * 60 * 1000;
  let changed = 0;
  const max = Math.max(1, Math.min(5000, limit));

  const deliveries = nextCleanupPage(store.pushDeliveries, cleanupDeliveryCursor, max);
  cleanupDeliveryCursor = deliveries.cursor;
  for (const [id, delivery] of deliveries.entries) {
    if (changed >= max) break;
    const intent = store.pushIntents.get(delivery.intentId);
    if (delivery.status === "PENDING" && intent && (now >= intent.expiresAtUtcMs || now - intent.createdAtUtcMs >= PUSH_RETRY_HORIZON_MS)) {
      store.pushDeliveries.set(id, { ...delivery, status: "EXPIRED", leaseId: null, leaseUntilUtcMs: null, updatedAtUtcMs: now });
      changed += 1;
      continue;
    }
    if (delivery.status !== "PENDING" && delivery.updatedAtUtcMs < retentionCutoff) {
      store.pushDeliveries.delete(id);
      changed += 1;
    }
  }
  const intents = nextCleanupPage(store.pushIntents, cleanupIntentCursor, max);
  cleanupIntentCursor = intents.cursor;
  for (const [id, intent] of intents.entries) {
    if (changed >= max) break;
    if (intent.createdAtUtcMs >= retentionCutoff || now < intent.expiresAtUtcMs) continue;
    const hasDeliveries = [...store.pushDeliveries.values()].some(delivery => delivery.intentId === id);
    if (!hasDeliveries) {
      store.pushIntents.delete(id);
      changed += 1;
    }
  }
  const devices = nextCleanupPage(store.pushDevices, cleanupDeviceCursor, max);
  cleanupDeviceCursor = devices.cursor;
  for (const [id, device] of devices.entries) {
    if (changed >= max) break;
    if (device.revokedAtUtcMs != null && device.revokedAtUtcMs < retentionCutoff && !device.tokenCiphertext && !device.tokenHash) {
      store.pushDevices.delete(id);
      changed += 1;
    }
  }
  return changed;
}
