import assert from "node:assert/strict";
import test from "node:test";
import { validatePayoutBankDetails } from "./bankAccountValidation.ts";

function ok(input: Parameters<typeof validatePayoutBankDetails>[0]) {
  const r = validatePayoutBankDetails(input);
  assert.equal(r.ok, true, `expected valid, got: ${r.ok ? "" : r.detail}`);
  return r.ok ? r.value : undefined!;
}

function rejects(input: Parameters<typeof validatePayoutBankDetails>[0], field: string) {
  const r = validatePayoutBankDetails(input);
  assert.equal(r.ok, false, "expected this to be rejected");
  if (!r.ok) assert.equal(r.field, field);
}

const VALID = {
  accountHolderName: "Ravi Kumar",
  ifsc: "HDFC0000123",
  accountNumber: "50100123456789",
};

test("accepts a well-formed payout profile", () => {
  const v = ok(VALID);
  assert.equal(v.ifsc, "HDFC0000123");
  assert.equal(v.accountHolderName, "Ravi Kumar");
});

test("IFSC is upper-cased and trimmed, so a lower-case entry still reaches the provider correctly", () => {
  const v = ok({ ...VALID, ifsc: "  hdfc0000123  " });
  assert.equal(v.ifsc, "HDFC0000123");
});

// Several Indian banks issue alphanumeric account numbers. A digits-only rule
// would refuse real carriers, which is worse than no validation at all.
test("accepts an alphanumeric account number", () => {
  ok({ ...VALID, accountNumber: "ABCD1234567890" });
});

test("accepts the shortest and longest account numbers the payout provider allows", () => {
  ok({ ...VALID, accountNumber: "12345" });
  ok({ ...VALID, accountNumber: "1".repeat(35) });
});

test("accepts real-world names with punctuation", () => {
  for (const name of ["O'Brien Transport", "Ravi Kumar & Sons".replace("&", "-"), "M/S Sharma (Delhi)", "Shree Ram Transport Co., Ltd."]) {
    ok({ ...VALID, accountHolderName: name });
  }
});

test("rejects an IFSC whose fifth character is not zero", () => {
  rejects({ ...VALID, ifsc: "HDFC1000123" }, "ifsc");
});

test("rejects an IFSC of the wrong length", () => {
  rejects({ ...VALID, ifsc: "HDFC000012" }, "ifsc");
  rejects({ ...VALID, ifsc: "HDFC00001234" }, "ifsc");
});

test("rejects an IFSC whose bank code is not four letters", () => {
  rejects({ ...VALID, ifsc: "HD1C0000123" }, "ifsc");
});

test("rejects a missing IFSC", () => {
  rejects({ ...VALID, ifsc: "" }, "ifsc");
  rejects({ ...VALID, ifsc: undefined }, "ifsc");
});

test("rejects an account number with spaces, which is how people paste them", () => {
  rejects({ ...VALID, accountNumber: "5010 0123 4567" }, "accountNumber");
});

test("rejects account numbers outside the provider's length limits", () => {
  rejects({ ...VALID, accountNumber: "1234" }, "accountNumber");
  rejects({ ...VALID, accountNumber: "1".repeat(36) }, "accountNumber");
});

// The account number is only required once real payouts are switched on, so an
// empty one is a valid state rather than an error.
test("allows an absent account number, because it is not always collected yet", () => {
  const v = ok({ accountHolderName: "Ravi Kumar", ifsc: "HDFC0000123" });
  assert.equal(v.accountNumber, "");
});

test("rejects a missing or too-short account holder name", () => {
  rejects({ ...VALID, accountHolderName: "" }, "accountHolderName");
  rejects({ ...VALID, accountHolderName: "Ra" }, "accountHolderName");
});

test("rejects an account holder name carrying characters the provider refuses", () => {
  rejects({ ...VALID, accountHolderName: "Ravi <script>" }, "accountHolderName");
});

test("reports the first bad field rather than a generic failure", () => {
  const r = validatePayoutBankDetails({ accountHolderName: "", ifsc: "nope", accountNumber: "x" });
  assert.equal(r.ok, false);
  if (!r.ok) {
    assert.equal(r.field, "accountHolderName");
    assert.match(r.detail, /required/i);
  }
});
