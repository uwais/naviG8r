import assert from "node:assert/strict";
import test from "node:test";
import { adminDashboardV1Html } from "./adminDashboardV1.ts";
import { opsConsoleBetaHtml } from "./opsConsoleBeta.ts";
import { opsPortalHtml } from "./opsPortal.ts";

test("each staff sign-in page words the fifth wrong code", () => {
  for (const [page, html, sentence] of [
    ["ops portal", opsPortalHtml(), "otp_too_many_wrong_codes:'Too many wrong codes. Send a new code.'"],
    ["admin dashboard", adminDashboardV1Html(), 'otp_too_many_wrong_codes: "Too many wrong codes. Send a new code."'],
    ["ops beta", opsConsoleBetaHtml(), "otp_too_many_wrong_codes: 'too many wrong codes, so send a new code'"],
  ] as const) {
    assert.ok(html.includes(sentence), `${page} must contain: ${sentence}`);
  }
});
