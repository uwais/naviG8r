import test from "node:test";
import assert from "node:assert/strict";
import { photoContentType, withoutPhotoMetadata } from "./photoFormat.ts";

const u16 = (value: number) => { const out = Buffer.alloc(2); out.writeUInt16BE(value); return out; };
const u32 = (value: number) => { const out = Buffer.alloc(4); out.writeUInt32BE(value); return out; };
const le32 = (value: number) => { const out = Buffer.alloc(4); out.writeUInt32LE(value); return out; };
const text = (value: string) => Buffer.from(value, "latin1");
const jpegSegment = (marker: number, payload: Buffer) => Buffer.concat([Buffer.from([0xff, marker]), u16(payload.length + 2), payload]);
const pngChunk = (type: string, data: Buffer) => Buffer.concat([u32(data.length), text(type), data, u32(0)]);
const webpChunk = (type: string, data: Buffer) => Buffer.concat([text(type), le32(data.length), data, data.length % 2 ? Buffer.from([0]) : Buffer.alloc(0)]);
const webp = (...chunks: Buffer[]) => { const body = Buffer.concat(chunks); return Buffer.concat([text("RIFF"), le32(4 + body.length), text("WEBP"), body]); };

/** Big-endian TIFF: orientation and a GPS directory holding a place name. */
function exifWithLocation(orientation: number): Buffer {
  return Buffer.concat([
    text("Exif\0\0MM"), u16(42), u32(8),
    u16(2), u16(0x0112), u16(3), u32(1), u16(orientation), u16(0), u16(0x8825), u16(4), u32(1), u32(38), u32(0),
    u16(1), u16(0x001b), u16(7), u32(18), u32(56), u32(0),
    text("SYNTHETIC-LOCATION"),
  ]);
}

const soi = Buffer.from([0xff, 0xd8]);
const eoi = Buffer.from([0xff, 0xd9]);
const jfif = jpegSegment(0xe0, text("JFIF\0\x01\x02\0\0\x01\0\x01\0\0"));
const icc = jpegSegment(0xe2, text("ICC_PROFILE\0\x01\x01"));
const quantization = jpegSegment(0xdb, Buffer.alloc(65, 1));
// A scan header, then image data with a stuffed 0xFF00 and a restart marker inside it.
const scan = Buffer.concat([jpegSegment(0xda, Buffer.from([1, 1, 0, 0, 0x3f, 0])), Buffer.from([0x11, 0xff, 0x00, 0x22, 0xff, 0xd0, 0x33])]);

test("a JPEG keeps its image data, tables, JFIF and colour profile, and only its orientation from EXIF", () => {
  const photo = Buffer.concat([
    soi, jfif,
    jpegSegment(0xe1, exifWithLocation(6)),
    jpegSegment(0xe1, text("http://ns.adobe.com/xap/1.0/\0<x:xmpmeta>SYNTHETIC-XMP-PLACE</x:xmpmeta>")),
    jpegSegment(0xfe, text("SYNTHETIC-COMMENT")),
    jpegSegment(0xed, text("Photoshop 3.0\0SYNTHETIC-IPTC-CITY")),
    jpegSegment(0xe2, text("MPF\0SYNTHETIC-MORE-PICTURES")),
    icc, quantization, scan, eoi,
    soi, jpegSegment(0xe1, exifWithLocation(1)), eoi,
  ]);
  assert.equal(photoContentType(photo), "image/jpeg");
  const cleaned = withoutPhotoMetadata(photo, "image/jpeg")!;
  const orientationOnly = jpegSegment(0xe1, Buffer.concat([text("Exif\0\0MM"), u16(42), u32(8), u16(1), u16(0x0112), u16(3), u32(1), u16(6), u16(0), u32(0)]));
  assert.deepEqual(cleaned, Buffer.concat([soi, jfif, orientationOnly, icc, quantization, scan, eoi]));
  for (const left of ["SYNTHETIC-LOCATION", "SYNTHETIC-XMP-PLACE", "SYNTHETIC-COMMENT", "SYNTHETIC-IPTC-CITY", "SYNTHETIC-MORE-PICTURES"]) {
    assert.equal(cleaned.includes(left), false, `${left} is removed`);
  }
});

test("a JPEG with no EXIF gets none added, and one cut off before its end marker is refused", () => {
  const plain = Buffer.concat([soi, quantization, scan, eoi]);
  assert.deepEqual(withoutPhotoMetadata(plain, "image/jpeg"), plain);
  assert.equal(withoutPhotoMetadata(plain.subarray(0, plain.length - 2), "image/jpeg"), null);
  assert.equal(withoutPhotoMetadata(Buffer.concat([soi, Buffer.from([0xff, 0xdb, 0x00, 0x50, 1, 2])]), "image/jpeg"), null, "a segment longer than the file");
});

test("a PNG loses its EXIF, text and time chunks, and keeps the rest in order", () => {
  const signature = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  const header = pngChunk("IHDR", Buffer.alloc(13, 1)), data = pngChunk("IDAT", Buffer.alloc(20, 2)), end = pngChunk("IEND", Buffer.alloc(0));
  const photo = Buffer.concat([signature, header, pngChunk("eXIf", exifWithLocation(1).subarray(6)), pngChunk("tEXt", text("Comment\0SYNTHETIC-TEXT")),
    pngChunk("iTXt", text("XML:com.adobe.xmp\0\0\0\0\0SYNTHETIC-XMP")), pngChunk("tIME", Buffer.alloc(7)), data, end]);
  assert.equal(photoContentType(photo), "image/png");
  assert.deepEqual(withoutPhotoMetadata(photo, "image/png"), Buffer.concat([signature, header, data, end]));
  assert.equal(withoutPhotoMetadata(Buffer.concat([signature, header, data]), "image/png"), null, "no end chunk");
});

test("a WebP loses its EXIF and XMP chunks and the flags that announce them", () => {
  const extended = (flags: number) => webpChunk("VP8X", Buffer.from([flags, 0, 0, 0, 9, 0, 0, 9, 0, 0]));
  const image = webpChunk("VP8L", Buffer.from([0x2f, 1, 2, 3, 4]));
  const photo = webp(extended(0x1c), image, webpChunk("EXIF", exifWithLocation(1).subarray(6)), webpChunk("XMP ", text("SYNTHETIC-XMP")));
  assert.equal(photoContentType(photo), "image/webp");
  assert.deepEqual(withoutPhotoMetadata(photo, "image/webp"), webp(extended(0x10), image));
});

test("anything that is not a JPEG, PNG or WebP has no type", () => {
  for (const bytes of [Buffer.alloc(0), text("GIF89a"), text("<svg xmlns='http://www.w3.org/2000/svg'/>"), text("RIFF\0\0\0\0WAVE")]) {
    assert.equal(photoContentType(bytes), null);
  }
});
