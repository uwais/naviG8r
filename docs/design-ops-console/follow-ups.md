# Ops page beta: follow-ups from review

Found by the review pack on 30 Sep 2026 and not fixed in the first PR, each with where it lives and a
suggested fix. Security items are tracked privately and are not listed here.

| Item | Where | Suggested fix | Severity |
|---|---|---|---|
| No "someone acted first" message: two people reviewing the same carrier both see success, and the second silently replaces the first | `apps/api/src/httpServer.ts`, the `/v1/organizations/:id/kyc` handler | Server work: accept the status the reviewer saw, refuse on a mismatch, and answer with who acted and when. Then show that answer in the card | Medium, needs a team decision |
| The new browser tests do not run in CI | `.github/workflows/dashboard.yml` | Add a step that runs `npx playwright test --config=playwright.ops-beta.config.ts`, and add the new paths to the workflow's path filter | Low, CI change needs an OK |
| The review endpoint accepts any organization, not only carriers, so "Review any carrier by ID" can change a shipper's approval | `apps/api/src/httpServer.ts`, the same handler | Refuse organizations whose kind is not a carrier kind | Low, existed before this page |
| "Payments waiting" counts payments still on hold, under the caption "Needs someone" | `apps/api/src/opsConsoleBeta.ts`, `showPaymentCount` | Count only payments that are ready, or rename the caption. The design counts all of them, so this needs a design call | Low |
| Switching organization during a card review reloads the list and turns the review-by-ID button back on mid-save | `apps/api/src/opsConsoleBeta.ts`, `loadCarriers` | Skip controls that are busy when re-enabling the form | Low |
