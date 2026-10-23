/**
 * Reads a photo's file format and rewrites it without the metadata a phone writes into it, where the place the
 * photo was taken is kept. Only JPEG, PNG and WebP, each by walking its own segment or chunk layout, so no image
 * library is needed. The pixels are never decoded or re-encoded.
 *
 * The phone's photo picker cannot be relied on for this: on Android it copies the GPS tags into the smaller photo
 * it makes, and on iOS it writes the original metadata back.
 */
import type { PodPhotoContentType } from "./types.ts";

export function photoContentType(bytes: Buffer): PodPhotoContentType | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(pngSignature)) return "image/png";
  if (bytes.length >= 12 && bytes.toString("latin1", 0, 4) === "RIFF" && bytes.toString("latin1", 8, 12) === "WEBP") return "image/webp";
  return null;
}

/** Null when the bytes do not follow their format's layout to its end, as a cut-off upload would not. */
export function withoutPhotoMetadata(bytes: Buffer, contentType: PodPhotoContentType): Buffer | null {
  if (contentType === "image/jpeg") return jpegWithoutMetadata(bytes);
  if (contentType === "image/png") return pngWithoutMetadata(bytes);
  return webpWithoutMetadata(bytes);
}

const pngSignature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

/**
 * Keeps the image data, its tables, JFIF (APP0), an ICC colour profile (APP2) and Adobe's colour flag (APP14).
 * Drops EXIF and XMP (APP1), every other APP segment, comments, and anything after the end marker, where some
 * phones append extra pictures with their own EXIF. A photo turned on its side has only EXIF to say so, so the
 * orientation goes back in as a new EXIF segment holding nothing else.
 */
function jpegWithoutMetadata(bytes: Buffer): Buffer | null {
  const kept: Buffer[] = [bytes.subarray(0, 2)];
  let orientation: number | undefined;
  let at = 2;
  while (at + 2 <= bytes.length) {
    if (bytes[at] !== 0xff) return null;
    const marker = bytes[at + 1]!;
    if (marker === 0xff) { at += 1; continue; }
    if (marker === 0xd9) {
      kept.push(bytes.subarray(at, at + 2));
      if (orientation) kept.splice(kept[1]?.[1] === 0xe0 ? 2 : 1, 0, orientationOnlyExif(orientation));
      return Buffer.concat(kept);
    }
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd8) || at + 4 > bytes.length) return null;
    const end = at + 2 + bytes.readUInt16BE(at + 2);
    if (end > bytes.length || end < at + 4) return null;
    const segment = bytes.subarray(at, end);
    if (marker === 0xda) {
      // The image data after a scan header runs to the next marker that is neither a stuffed 0xFF00 nor a restart.
      let scanEnd = end;
      while (scanEnd + 1 < bytes.length && !(bytes[scanEnd] === 0xff && bytes[scanEnd + 1] !== 0x00 && (bytes[scanEnd + 1]! < 0xd0 || bytes[scanEnd + 1]! > 0xd7))) scanEnd += 1;
      kept.push(bytes.subarray(at, scanEnd));
      at = scanEnd;
      continue;
    }
    if (marker === 0xe1) orientation ??= exifOrientation(segment.subarray(4));
    else if (!jpegMetadataSegment(marker, segment)) kept.push(segment);
    at = end;
  }
  return null;
}

function jpegMetadataSegment(marker: number, segment: Buffer): boolean {
  if (marker === 0xe0 || marker === 0xee) return false;
  if (marker === 0xe2) return segment.toString("latin1", 4, 16) !== "ICC_PROFILE\0";
  return (marker >= 0xe0 && marker <= 0xef) || marker === 0xfe;
}

/** EXIF tag 0x0112 in the first image directory, 1 to 8; undefined when absent or unreadable. */
function exifOrientation(payload: Buffer): number | undefined {
  if (payload.length < 14 || payload.toString("latin1", 0, 6) !== "Exif\0\0") return undefined;
  const tiff = payload.subarray(6);
  const byteOrder = tiff.toString("latin1", 0, 2);
  if (byteOrder !== "II" && byteOrder !== "MM") return undefined;
  const short = (at: number) => byteOrder === "II" ? tiff.readUInt16LE(at) : tiff.readUInt16BE(at);
  const directory = byteOrder === "II" ? tiff.readUInt32LE(4) : tiff.readUInt32BE(4);
  if (directory + 2 > tiff.length) return undefined;
  for (let index = 0; index < short(directory); index++) {
    const entry = directory + 2 + index * 12;
    if (entry + 12 > tiff.length) return undefined;
    if (short(entry) !== 0x0112) continue;
    const value = short(entry + 8);
    return value >= 1 && value <= 8 ? value : undefined;
  }
  return undefined;
}

/** An APP1 segment whose EXIF has one tag, the orientation, big-endian. */
function orientationOnlyExif(orientation: number): Buffer {
  const segment = Buffer.alloc(36);
  segment.writeUInt16BE(0xffe1, 0);
  segment.writeUInt16BE(34, 2);
  segment.write("Exif\0\0MM", 4, "latin1");
  segment.writeUInt16BE(42, 12);
  segment.writeUInt32BE(8, 14);
  segment.writeUInt16BE(1, 18);
  segment.writeUInt16BE(0x0112, 20);
  segment.writeUInt16BE(3, 22);
  segment.writeUInt32BE(1, 24);
  segment.writeUInt16BE(orientation, 28);
  return segment;
}

/**
 * The PNG chunks kept: the image itself and how to show its colours. Anything else is dropped, EXIF, text (which
 * holds XMP), times and any chunk a phone or editor invents, since a chunk not on this list could hold a place.
 */
const pngKeptChunks = ["IHDR", "PLTE", "IDAT", "IEND", "tRNS", "gAMA", "cHRM", "sRGB", "iCCP", "sBIT", "pHYs", "bKGD"];

function pngWithoutMetadata(bytes: Buffer): Buffer | null {
  const kept: Buffer[] = [pngSignature];
  let at = 8;
  while (at + 12 <= bytes.length) {
    const type = bytes.toString("latin1", at + 4, at + 8);
    const end = at + 12 + bytes.readUInt32BE(at);
    if (end > bytes.length) return null;
    if (pngKeptChunks.includes(type)) kept.push(bytes.subarray(at, end));
    at = end;
    if (type === "IEND") return Buffer.concat(kept);
  }
  return null;
}

/** The WebP chunks kept: the image, its alpha, colour profile and animation frames. EXIF, XMP and any other go. */
const webpKeptChunks = ["VP8 ", "VP8L", "VP8X", "ALPH", "ICCP", "ANIM", "ANMF"];

/** Keeps only webpKeptChunks, and clears the two flags in VP8X that say EXIF and XMP are there. */
function webpWithoutMetadata(bytes: Buffer): Buffer | null {
  const riffEnd = 8 + bytes.readUInt32LE(4);
  if (riffEnd > bytes.length) return null;
  const kept: Buffer[] = [];
  let at = 12;
  while (at + 8 <= riffEnd) {
    const type = bytes.toString("latin1", at, at + 4);
    const size = bytes.readUInt32LE(at + 4);
    if (at + 8 + size > riffEnd) return null;
    const end = Math.min(at + 8 + size + (size % 2), riffEnd);
    if (webpKeptChunks.includes(type)) kept.push(Buffer.from(bytes.subarray(at, end)));
    at = end;
  }
  if (!kept.length) return null;
  const extendedHeader = kept.find((chunk) => chunk.toString("latin1", 0, 4) === "VP8X" && chunk.length > 8);
  if (extendedHeader) extendedHeader[8] = extendedHeader[8]! & ~0x0c;
  const chunks = Buffer.concat(kept);
  const header = Buffer.alloc(12);
  header.write("RIFF", 0, "latin1");
  header.writeUInt32LE(4 + chunks.length, 4);
  header.write("WEBP", 8, "latin1");
  return Buffer.concat([header, chunks]);
}
