# Dependency patches

`npm install` and `npm ci` apply these patches through `patch-package --error-on-fail`.
Build installations require dev dependencies and lifecycle scripts, including `postinstall`.

`@ton+crypto-primitives+2.1.0.patch` makes the browser crypto backend use
`globalThis.crypto` for random generation, HMAC and PBKDF2. The shared wallet SDK
runs in both Web Workers and window-based WebViews; workers have no `window`.
The cryptographic algorithms and native Node backend are unchanged.

The modified package is MIT-licensed; its original license and source notices are
retained. `tests/tonCryptoPrimitives.test.ts` exercises its browser backend in a
worker without `window`. Recheck that test when updating `@ton/crypto` or its
primitives dependency, and remove the patch when the upstream browser backend
supports workers directly.
