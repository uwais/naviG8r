/**
 * Proof of delivery photos: one to three per shipment, sent by the trip's driver (or the carrier office) before
 * confirming delivery, and seen by the shipment's shipper, its carrier, the trip's driver and NaviG8r staff.
 *
 * Each photo is a file on the server's disk beside the data file, at pod-photos/<shipmentId>/<photoId>.<ext>; the
 * store keeps only what is known about it, on shipment.podPhotos. Location data is removed before the file is
 * written (photoFormat.ts). The ERP webhook and ERP responses never carry photos.
 *
 * Kept for 6 months, the same as e-way bills (owner, 22 Oct 2026). Nothing deletes them yet: the clean-up job is
 * not built, so that rule is not enforced.
 */
import { createHash, randomUUID } from "node:crypto";
import fs from "node:fs";
import type http from "node:http";
import path from "node:path";
import { AuthorizationError, recordAudit, requireAssistance, requirePermission, type Principal } from "./rbac.ts";
import { ApiError } from "./services.ts";
import { photoContentType, withoutPhotoMetadata } from "./photoFormat.ts";
import type { Store } from "./store.ts";
import type { PodPhoto, PodPhotoContentType, Shipment } from "./types.ts";

export const POD_PHOTO_MAX_BYTES = 1.5 * 1024 * 1024;
export const POD_PHOTOS_PER_SHIPMENT = 3;
const extensions: Record<PodPhotoContentType, string> = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp" };
const photoIdShape = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
// Every id the server makes fits this; a folder name never comes from anything else.
const shipmentIdShape = /^[A-Za-z0-9_-]{1,128}$/;

/** The body of one upload, or the fact it went over the limit. Read before the request takes the queue. */
export type PodPhotoUpload = { bytes: Buffer } | { tooLarge: true };

export function isPodPhotoUploadPath(pathname: string): boolean {
  return /^\/v1\/shipments\/[^/]+\/pod-photos$/.test(pathname);
}

/** Stops collecting at the limit and lets the rest of the body drain, so the 413 still reaches the phone. */
export function readPodPhotoUpload(req: http.IncomingMessage): Promise<PodPhotoUpload> {
  if (Number(req.headers["content-length"]) > POD_PHOTO_MAX_BYTES) {
    req.resume();
    return Promise.resolve({ tooLarge: true });
  }
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let length = 0;
    req.on("data", (chunk: Buffer) => {
      length += chunk.length;
      if (length <= POD_PHOTO_MAX_BYTES) return void chunks.push(chunk);
      req.removeAllListeners("data");
      req.resume();
      resolve({ tooLarge: true });
    });
    req.on("end", () => resolve({ bytes: Buffer.concat(chunks) }));
    req.on("error", reject);
    // A phone that loses signal mid-upload closes the connection without an end; half a photo is not kept.
    req.on("close", () => { if (!req.complete) reject(new Error("upload_incomplete")); });
  });
}

export function podPhotosRoot(dataFilePath: string): string {
  return path.join(path.dirname(dataFilePath), "pod-photos");
}

function photoFile(root: string, shipmentId: string, photo: PodPhoto): string {
  if (!shipmentIdShape.test(shipmentId) || !photoIdShape.test(photo.id)) throw new AuthorizationError("not_found", 404);
  return path.join(root, shipmentId, `${photo.id}.${extensions[photo.contentType]}`);
}

function findShipment(store: Store, shipmentId: string): Shipment {
  const shipment = store.shipments.get(shipmentId);
  if (!shipment) throw new AuthorizationError("not_found", 404);
  return shipment;
}

/** Photos change only while the shipment waits for proof of delivery, the state submitDriverPod accepts. */
function requirePhotoChangesOpen(store: Store, shipment: Shipment): Principal {
  const principal = requirePermission(store, "pod.upload", shipment);
  requireAssistance(store, principal, shipment.carrierId);
  if (shipment.status !== "BOOKED") {
    throw new ApiError("pod_photos_closed", { detail: "Photos can be added or removed only before delivery is confirmed." }, 409);
  }
  return principal;
}

function findPhoto(shipment: Shipment, photoId: string): PodPhoto {
  const photo = photoIdShape.test(photoId) ? shipment.podPhotos?.find((candidate) => candidate.id === photoId) : undefined;
  if (!photo) throw new AuthorizationError("not_found", 404);
  return photo;
}

/**
 * Checks the upload, writes the file (to a temporary name, then renamed, so a half-written file is never served)
 * and records the photo. The caller saves the store; if that fails it calls removePodPhotoFile.
 */
export function addPodPhoto(store: Store, root: string, shipmentId: string, upload: PodPhotoUpload, declaredType: string | undefined): { shipment: Shipment; photo: PodPhoto; file: string } {
  const shipment = findShipment(store, shipmentId);
  const principal = requirePhotoChangesOpen(store, shipment);
  if ("tooLarge" in upload) throw new ApiError("pod_photo_too_large", { detail: "This photo is too large. The limit is 1.5 MB." }, 413);
  const contentType = photoContentType(upload.bytes);
  const declared = (declaredType ?? "").split(";", 1)[0]!.trim().toLowerCase();
  const cleaned = contentType && Object.hasOwn(extensions, declared) ? withoutPhotoMetadata(upload.bytes, contentType) : null;
  if (!contentType || !cleaned) throw new ApiError("pod_photo_wrong_type", { detail: "Send a JPEG, PNG or WebP photo." }, 415);
  if ((shipment.podPhotos?.length ?? 0) >= POD_PHOTOS_PER_SHIPMENT) {
    throw new ApiError("pod_photo_limit", { detail: "A delivery can have up to 3 photos. Remove one to add another." }, 409);
  }
  const photo: PodPhoto = {
    id: randomUUID(),
    contentType,
    bytes: cleaned.length,
    sha256: createHash("sha256").update(cleaned).digest("hex"),
    uploadedAtUtcMs: Date.now(),
    uploadedByUserId: principal.userId,
  };
  const file = photoFile(root, shipment.id, photo);
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(`${file}.tmp`, cleaned);
  fs.renameSync(`${file}.tmp`, file);
  const updated: Shipment = { ...shipment, podPhotos: [...(shipment.podPhotos ?? []), photo], updatedAtUtcMs: photo.uploadedAtUtcMs };
  store.shipments.set(updated.id, updated);
  recordAudit(store, "POD_PHOTO_ADDED", "shipment", shipment.id);
  return { shipment: updated, photo, file };
}

/** Takes the photo off the shipment. The caller saves the store, then removes the file. */
export function removePodPhoto(store: Store, root: string, shipmentId: string, photoId: string): { shipment: Shipment; file: string } {
  const shipment = findShipment(store, shipmentId);
  requirePhotoChangesOpen(store, shipment);
  const photo = findPhoto(shipment, photoId);
  const file = photoFile(root, shipment.id, photo);
  const updated: Shipment = { ...shipment, podPhotos: shipment.podPhotos!.filter((candidate) => candidate.id !== photo.id), updatedAtUtcMs: Date.now() };
  store.shipments.set(updated.id, updated);
  recordAudit(store, "POD_PHOTO_REMOVED", "shipment", shipment.id);
  return { shipment: updated, file };
}

export function removePodPhotoFile(file: string): void {
  fs.rmSync(file, { force: true });
}

/** Who may read the shipment may read its photos: the guard and requirePermission settle that, with 404 for anyone else. */
export function readPodPhoto(store: Store, root: string, shipmentId: string, photoId: string): { contentType: PodPhotoContentType; bytes: Buffer } {
  const shipment = findShipment(store, shipmentId);
  requirePermission(store, "load.read", shipment);
  const photo = findPhoto(shipment, photoId);
  try {
    return { contentType: photo.contentType, bytes: fs.readFileSync(photoFile(root, shipment.id, photo)) };
  } catch (error) {
    if ((error as { code?: string })?.code === "ENOENT") throw new AuthorizationError("not_found", 404);
    throw error;
  }
}

/** ERP callers are other systems, not people the shipper chose to show a delivery photo to. */
export function withoutPodPhotos<T extends { podPhotos?: unknown }>(shipment: T): Omit<T, "podPhotos"> {
  const copy = { ...shipment };
  delete copy.podPhotos;
  return copy;
}
