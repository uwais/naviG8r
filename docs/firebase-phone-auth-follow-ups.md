# Firebase phone-auth follow-ups

These items were identified during the review of PR #166 and are intentionally deferred from
the current Firebase web phone-auth change.

- [ ] **Managed reCAPTCHA lifecycle:** make failed, timed-out, superseded, and disposed web
  verification requests clean up safely without reintroducing stale-token failures. Add browser
  coverage for retries and navigation during a pending challenge.
- [ ] **Firebase exchange retry:** retain a verified Firebase state bound to the phone identity
  until the NaviG8r backend exchange succeeds, so a temporary API failure does not require another
  SMS. Clear it when the phone changes or the user signs out.
- [ ] **Restore expired-payment shipment copy:** preserve the `unpaidBookingExpired` explanation
  in the driver shipment screen and add a named screen assertion for that status.
- [ ] **Firebase web test coverage:** inject a fake phone-auth client and test successful web
  verification, failed resend, identity changes, exchange retry, disposal, and the country-code
  selectors on affected registration and invitation screens.
