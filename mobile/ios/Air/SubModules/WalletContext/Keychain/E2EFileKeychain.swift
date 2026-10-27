import Foundation

// Routes WSecureStorage / KeychainHelper writes to a JSON file in the app
// sandbox (Application Support) under E2E. The real Keychain doesn't survive
// simctl clone (data-protection class keys are device-bound), so snapshot
// flows can't reuse stored passcode-derived material. The sandbox is copied
// 1:1 by simctl clone, so a file-backed adapter keeps imported-wallet
// snapshots usable.
//
// Opt-in only: DEBUG builds, with UserDefaults "debug_e2eFileKeychain"
// flipped on by the Maestro driver before app launch
// (xcrun simctl spawn <udid> defaults write <bundle> debug_e2eFileKeychain -bool YES).
public enum E2EFileKeychain {
    public static let userDefaultsKey = "debug_e2eFileKeychain"

    public static var isEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
        #else
        return false
        #endif
    }
}