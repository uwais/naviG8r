/**
 * The HTTP side of proof of delivery photos: taking an upload in before the request queue, and the add, remove and
 * read routes that run inside it. What a photo is and who may change it lives in podPhotos.ts.
 */
import type http from "node:http";
import { authorizationContext, AuthorizationError, type RequestContext } from "./rbac.ts";
import { guardRequest, requestContext } from "./rbacRoutes.ts";
import { addPodPhoto, readPodPhoto, readPodPhotoUpload, removePodPhoto, removePodPhotoFile, type PodPhotoUpload } from "./podPhotos.ts";
import type { Store } from "./store.ts";

type Json = (res: http.ServerResponse, status: number, body: unknown) => void;

// Each upload being read holds up to 1.5 MB, so only a few are read at once and the server keeps memory for everyone.
const UPLOADS_READ_AT_ONCE = 4;
// A phone that stops sending for this long has lost its signal; its connection is closed.
const UPLOAD_IDLE_TIMEOUT_MS = 30_000;
let uploadsBeingRead = 0;
// One upload read at a time per sign-in, so one login cannot take every slot. The app sends one photo at a time.
const usersWithUploadBeingRead = new Set<string>();

/** The sign-in, the shipment and the caller's right to add photos, from the store alone. The signed-in user when all pass. */
function uploaderOrRefusal(req: http.IncomingMessage, store: Store): { status: number; error: string } | { userId: string } {
  try {
    const context: RequestContext = requestContext();
    authorizationContext.run(context, () => guardRequest(req, store, new URL(req.url ?? "/", "http://localhost")));
    return { userId: context.principal!.userId };
  } catch (error) {
    if (error instanceof AuthorizationError) return { status: error.status, error: error.message };
    if ((error as Error)?.message === "account_inactive") return { status: 403, error: "account_inactive" };
    return { status: 401, error: "unauthorized" };
  }
}

/** Answers, then closes the connection once the answer is out, so the body is never read. */
function refuseUnread(req: http.IncomingMessage, res: http.ServerResponse, json: Json, status: number, error: string): void {
  res.setHeader("connection", "close");
  res.once("finish", () => req.destroy());
  json(res, status, { error });
}

/**
 * Takes an upload in before the request queue, so a slow phone does not hold up others. The checks the queued route
 * makes again are made here first, from the store, so a caller who may not add a photo is answered without its body
 * being read. Then calls handle with the body.
 */
export function receivePodPhotoUpload(req: http.IncomingMessage, res: http.ServerResponse, store: Store, json: Json, handle: (upload: PodPhotoUpload) => unknown): void {
  const uploader = uploaderOrRefusal(req, store);
  if ("error" in uploader) return refuseUnread(req, res, json, uploader.status, uploader.error);
  const { userId } = uploader;
  if (uploadsBeingRead >= UPLOADS_READ_AT_ONCE || usersWithUploadBeingRead.has(userId)) return refuseUnread(req, res, json, 503, "busy_try_again");
  uploadsBeingRead += 1;
  usersWithUploadBeingRead.add(userId);
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    uploadsBeingRead -= 1;
    usersWithUploadBeingRead.delete(userId);
  };
  req.once("end", release);
  req.once("close", release);
  req.once("error", release);
  req.setTimeout(UPLOAD_IDLE_TIMEOUT_MS, () => req.destroy());
  readPodPhotoUpload(req).then((upload) => {
    release();
    // The whole body is in; waiting for the queue is not the phone going quiet. A body over the limit still drains, under the timeout.
    if ("bytes" in upload) req.setTimeout(0);
    return handle(upload);
  }, () => {
    release();
    res.destroy();
  });
}

export type PodPhotoRouteContext = { store: Store; root: string; persist: () => Promise<void>; json: Json };

/** The add, remove and read routes, inside the request queue. True when the request was one of them and is answered. */
export async function handlePodPhotoRoute(req: http.IncomingMessage, res: http.ServerResponse, url: URL, upload: PodPhotoUpload | null, context: PodPhotoRouteContext): Promise<boolean> {
  const { store, root, persist, json } = context;
  const method = req.method ?? "GET";
  const route = /^\/v1\/shipments\/([^/]+)\/pod-photos(?:\/([^/]+))?$/.exec(url.pathname);
  if (!route) return false;
  const [, shipmentId, photoId] = route;
  if (!photoId && method === "POST" && upload) {
    const contentType = req.headers["content-type"];
    const added = addPodPhoto(store, root, shipmentId!, upload, Array.isArray(contentType) ? contentType[0] : contentType);
    try {
      await persist();
    } catch (error) {
      removePodPhotoFile(added.file);
      throw error;
    }
    const { id, contentType: savedType, uploadedAtUtcMs } = added.photo;
    json(res, 201, { photo: { id, contentType: savedType, uploadedAtUtcMs } });
    return true;
  }
  if (photoId && method === "DELETE") {
    const removed = removePodPhoto(store, root, shipmentId!, photoId);
    await persist();
    removePodPhotoFile(removed.file);
    json(res, 200, { removed: true });
    return true;
  }
  if (photoId && method === "GET") {
    const photo = readPodPhoto(store, root, shipmentId!, photoId);
    res.statusCode = 200;
    res.setHeader("content-type", photo.contentType);
    res.setHeader("content-length", photo.bytes.length);
    res.setHeader("cache-control", "private, no-store");
    res.setHeader("x-content-type-options", "nosniff");
    // A photo opened on its own, outside the app, runs nothing and is not embedded by another site.
    res.setHeader("content-security-policy", "default-src 'none'");
    res.setHeader("cross-origin-resource-policy", "same-origin");
    res.end(photo.bytes);
    return true;
  }
  return false;
}
