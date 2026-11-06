import assert from "node:assert/strict";
import test from "node:test";
import { opsPortalHtml } from "./opsPortal.ts";

test("the ops portal sign-in words the fifth wrong code", () => {
  assert.ok(opsPortalHtml().includes("otp_too_many_wrong_codes:'Too many wrong codes. Send a new code.'"));
});
