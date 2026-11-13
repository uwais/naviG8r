/**
 * What a typed form on the practice e-way bill site must look like: each check returns the first problem as a plain
 * sentence, or "" when the form can go ahead. Who may act on a bill is in ewayDemoPortalRules.ts.
 */
// The date, GSTIN, invoice and truck shapes are the app's own, so for those four the practice site refuses exactly what the app refuses.
import { isGstinShaped, isInvoiceNumberShaped, isRealCalendarDate, isTruckNumberShaped } from "./ewayBillValidation.ts";
import { EXTENSION_REASONS, MAX_DISTANCE_KM, TRANSPORT_REASONS, VEHICLE_UPDATE_REASONS, indiaDateIso } from "./ewayDemoPortalRules.ts";
import type { Persona } from "./ewayDemoPortalRules.ts";

const OTHERS = "3";
const PIN_PATTERN = /^[1-9][0-9]{5}$/;
const HSN_PATTERN = /^[0-9]{4}(?:[0-9]{2}){0,2}$/;
const MONEY_PATTERN = /^[0-9]{1,11}(?:\.[0-9]{1,2})?$/;
const PRINTABLE_ASCII = /^[\x20-\x7E]+$/;

// Transporter IDs share the GSTIN shape.
export { isGstinShaped };

export function cleanVehicleNumber(text: string): string {
  return text.replace(/[\s-]/g, "").toUpperCase();
}

export function cleanGstin(text: string): string {
  return text.replace(/\s/g, "").toUpperCase();
}

/** A whole number of km from 1 to the cap, or null. */
export function parseDistanceKm(text: string): number | null {
  if (!/^[0-9]{1,5}$/.test(text.trim())) return null;
  const distanceKm = Number(text.trim());
  return distanceKm >= 1 && distanceKm <= MAX_DISTANCE_KM ? distanceKm : null;
}

export type GenerateTyped = {
  supplierGstin: string; recipientGstin: string; dispatchPin: string; deliveryPin: string; documentNumber: string;
  documentDate: string; goodsValueRupees: string; hsnCode: string; transportReason: string; vehicleNumber: string;
  distanceKm: string; transporterId: string;
};

/** Returns the first problem as a plain sentence, or "" when the form can make a bill. */
export function generateInputProblem(typed: GenerateTyped, persona: Persona, nowUtcMs: number): string {
  if (!isGstinShaped(typed.supplierGstin)) return "A.1 GSTIN of Supplier is 15 letters and digits, for example 29ABCDE1234F1Z5.";
  if (persona.key === "supplier" && typed.supplierGstin !== persona.id) {
    return `Signed in as the supplier, A.1 must be your own GSTIN, ${persona.id}.`;
  }
  if (typed.recipientGstin !== "URP" && !isGstinShaped(typed.recipientGstin)) {
    return "A.3 GSTIN of Recipient is 15 letters and digits, or URP for an unregistered recipient.";
  }
  if (!PIN_PATTERN.test(typed.dispatchPin)) return "A.2 Place of Dispatch is a 6-digit PIN code.";
  if (!PIN_PATTERN.test(typed.deliveryPin)) return "A.4 Place of Delivery is a 6-digit PIN code.";
  if (!isInvoiceNumberShaped(typed.documentNumber)) {
    return "A.5 Document Number is up to 32 characters.";
  }
  if (!isRealCalendarDate(typed.documentDate)) return "Choose A.6 Document Date.";
  if (typed.documentDate > indiaDateIso(nowUtcMs)) return "A.6 Document Date cannot be in the future.";
  if (!MONEY_PATTERN.test(typed.goodsValueRupees) || Number(typed.goodsValueRupees) <= 0) {
    return "A.7 Value of Goods is an amount in rupees, for example 75000 or 75000.50.";
  }
  if (!HSN_PATTERN.test(typed.hsnCode)) return "A.8 HSN Code is 4, 6 or 8 digits.";
  if (!TRANSPORT_REASONS.includes(typed.transportReason)) return "Choose A.9 Reason for Transportation.";
  if (parseDistanceKm(typed.distanceKm) === null) return `Approximate distance is a whole number of km from 1 to ${MAX_DISTANCE_KM}.`;
  if (typed.vehicleNumber && !isTruckNumberShaped(typed.vehicleNumber)) {
    return "B.1 Vehicle Number is 6 to 12 letters and digits, for example KA01AB1234.";
  }
  if (typed.transporterId && !isGstinShaped(typed.transporterId)) {
    return "The Transporter ID is 15 letters and digits, for example 29TRNSP1234A1Z7.";
  }
  if (!typed.vehicleNumber && !typed.transporterId) {
    return "Enter B.1 Vehicle Number, or name a Transporter ID so the transporter can add the vehicle later.";
  }
  return "";
}

export function vehicleInputProblem(vehicleNumber: string, reasonCode: string, remark: string): string {
  if (!isTruckNumberShaped(vehicleNumber)) return "The vehicle number is 6 to 12 letters and digits, for example KA01AB1234.";
  if (!VEHICLE_UPDATE_REASONS.some((reason) => reason.code === reasonCode)) return "Choose a reason for the vehicle update.";
  return remarkProblem(remark, reasonCode === OTHERS);
}

export function extensionInputProblem(reasonCode: string, remark: string, remainingDistanceKm: string): string {
  if (!EXTENSION_REASONS.some((reason) => reason.code === reasonCode)) return "Choose a reason for the extension.";
  const problem = remarkProblem(remark, reasonCode === "OTHER");
  if (problem) return problem;
  if (parseDistanceKm(remainingDistanceKm) === null) return `Remaining distance is a whole number of km from 1 to ${MAX_DISTANCE_KM}.`;
  return "";
}

function remarkProblem(remark: string, required: boolean): string {
  if (required && remark.length < 3) return "With Others as the reason, write a remark of 3 to 50 characters.";
  if (remark.length > 50 || (remark && !PRINTABLE_ASCII.test(remark))) return "The remark is up to 50 characters.";
  return "";
}
