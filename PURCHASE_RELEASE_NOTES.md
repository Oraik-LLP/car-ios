# Billing and offline purchase update (1.0.5, version code 15)

- RevenueCat Flutter SDK upgraded from 8.11.0 to 11.0.0. Verify the resolved
  Billing dependency and merged release manifest when making each release.
- Startup uses RevenueCat's native CustomerInfo cache before loading products.
  Product/network errors no longer erase a previously verified paid entitlement.
- Trusted Entitlements response verification is explicitly enabled. Failed or
  unsigned responses cannot create paid access. The app never persists a paid
  tier in editable app preferences.
- Pro access from a verified cached response is bounded to three days from its
  signed server request time; a 48-hour Emergency Pass never exceeds 48 hours
  from purchase. A verified refund/revocation removes access immediately.
- On upgrading from an unsigned cache, connect once to obtain a verified cache.
  New purchases and restoring purchases still require the store/network.

## Backend deployment

Deploy the updated Node backend together with a **server-only RevenueCat API v1
secret key** in `REVENUECAT_SECRET_API_KEY`. Never put this secret in Dart defines,
the APK, or version control. The app now sends its RevenueCat customer identifier;
the server verifies that customer's entitlements instead of trusting a Pro plan
header. Verification outages return a retryable error rather than consuming free
quota. Old apps without the customer header must update for paid API requests.

The existing app uses anonymous RevenueCat identities, not account authentication.
Treat their identifiers as sensitive and don't log/share them. For account-bound
authorization across devices, add authenticated app accounts and bind the
RevenueCat identity on the server. Client-only offline features can still be
patched in a modified APK; cryptographic cache verification cannot prevent all
client-code modification. The backend check prevents a plan-header-only bypass.

## Play upload and test

`build_playstore.ps1 -SigningCredentialsFile ..\signing\LOCAL_CREDENTIALS.txt`
builds a signed AAB and APK, using `.local/play-defines.json` for the public Android
SDK key. Secrets remain outside the app repository. The replacement upload key
will be accepted by Play only after the pending upload-key reset is active.

Test on an internal track using a license tester: purchase/restore online, restart
in airplane mode, use paid local features, restart again, and reconnect to verify
renewal/refund changes. Confirm no purchase is granted for a pending transaction.
AI requests require connectivity. First launch after this upgrade needs one online
verification if the previous cache was unsigned. Do not clear app storage during
the offline test, because doing so removes the native purchase cache.
