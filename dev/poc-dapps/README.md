# WebView Camera Permission POC dApps

This folder contains two demo dApps for reproducing origin-isolation issues in Android WebView camera permissions.

- `good/`: legitimate-style QR scanner flow (requests camera on user button click).
- `evil/`: malicious-style page (tries to start camera stream on load).

Production code does not include Explore POC injection hooks.
To test locally, use the patch workflow from this folder.

## 1. Serve both dApps locally (different origins)

Use two ports so origins differ:

```bash
./dev/poc-dapps/serve-all.sh
```

Or run manually:

```bash
python3 -m http.server 8787 --directory dev/poc-dapps/good
python3 -m http.server 8788 --directory dev/poc-dapps/evil
```

## 2. Expose both over HTTPS (ngrok)

Run two tunnels (one per port):

```bash
ngrok http 8787
ngrok http 8788
```

Copy resulting HTTPS URLs, for example:

- good: `https://good-abc.ngrok-free.app`
- evil: `https://evil-def.ngrok-free.app`

## 3. Enable local Explore POC injection

Apply local patch with POC code:

```bash
./dev/poc-dapps/enable-local-poc.sh
```

## 4. Build mobile with POC URLs

One-command build (applies patch automatically if needed):

```bash
./dev/poc-dapps/build-mobile-poc.sh \
  "https://good-abc.ngrok-free.app" \
  "https://evil-def.ngrok-free.app" \
  development
```

Use `staging` as the third arg for staging builds.

Manual build alternative:

```bash
APP_ENV=development \
EXPLORE_POC_DAPPS=1 \
EXPLORE_POC_DAPP_GOOD_URL="https://good-abc.ngrok-free.app" \
EXPLORE_POC_DAPP_EVIL_URL="https://evil-def.ngrok-free.app" \
npm run mobile:build
```

## 5. Disable patch after tests

```bash
./dev/poc-dapps/disable-local-poc.sh
```

This returns `src/config.ts` and `src/api/methods/dapps.ts` to clean state.

## 6. Manual vulnerability scenario

1. Open `[POC] Camera QR Scanner` in Explore.
2. Tap `Start QR Scan` and allow camera.
3. Open `[POC] Silent Camera Sniffer`.
4. If camera starts there without a new origin prompt, origin isolation is broken.

## Files

- `patches/explore-poc-injection.patch`: stored diff with Explore POC injection code.
- `enable-local-poc.sh`: applies patch.
- `disable-local-poc.sh`: reverts patch.
- `build-mobile-poc.sh`: helper build command for local testing.
