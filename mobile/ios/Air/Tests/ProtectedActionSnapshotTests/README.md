# Protected action presentation snapshots

The snapshot harness launches the real presentation controllers in the existing `MyTonWallet_Preview` scratch app and captures the simulator screen. Each deterministic protected-action fixture covers:

- the passcode screen with the action's full confirmation header;
- the MFA screen with the same header's compact representation;
- the actual completion controller when the protected action owns one.

Actions that finish by dismissing, showing a toast, or handing control back to their feature do not get a made-up success screen.

## Record references

Boot the simulator you want to use for visual review, then run from the repository root:

```sh
mobile/ios/Air/scripts/protected_action_snapshots.sh record
```

The command builds and installs `MyTonWallet_Preview`, launches one snapshot state at a time, waits for consecutive stable frames, records PNGs under the git-ignored `__Snapshots__` directory, and rebuilds `gallery.html`. Recording is transactional: existing local references are replaced only after every state succeeds. The gallery groups each action into passcode, MFA, and success columns; unavailable success states leave their cell empty.

## Verify references

```sh
mobile/ios/Air/scripts/protected_action_snapshots.sh verify
```

Verification compares pixels against local references created by `record`. It checks exact bytes first and, when ImageMagick is available, permits a 1% per-channel tolerance for sub-visible antialiasing noise at Core Animation and simulator-mask edges. Simulator device type and iOS version affect rendering, so record and verify on the same simulator. Set `SIMULATOR_ID` when more than one simulator is booted. Captures include the complete simulator display with a status bar refreshed before every state and an alpha hardware mask, preserving the device shape, safe-area, and bottom-sheet margins without cropping. Changed images and optional ImageMagick diffs are written under the git-ignored `__Failures__` directory.

The generated PNGs and `gallery.html` are intentionally not versioned while the protected-action presentation is still being shaped. Run `record` to rebuild the local gallery and captures.

## Add or change a flow

Update `AirAsFramework/Debug/ProtectedActionPresentationSnapshots.swift`. Construct the feature's real immutable confirmation snapshot so the full and compact representations come from the same `ConfirmationContent`. Add a completion closure only when the protected action itself presents a terminal controller, then add its generated identifiers to the manifest at the top of that file. Completion controllers are hosted in a real sheet so their production detent and self-sizing logic is exercised. The capture script reads the manifest directly.

The app launch hook exists only in Debug builds and only activates when `PROTECTED_ACTION_PRESENTATION_SNAPSHOT` is present in the process environment. Normal app and test runs are unaffected.
