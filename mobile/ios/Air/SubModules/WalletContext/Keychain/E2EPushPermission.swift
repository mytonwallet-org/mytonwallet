import Foundation

// Suppresses the push-permission prompt under E2E. The request fires a few
// seconds after the wallet becomes ready, so it lands on whichever step a flow
// happens to be running and swallows its taps. Maestro's launchApp permissions
// cannot pre-answer it, because the system asks through the notification
// center rather than a TCC service.
//
// Opt-in only: DEBUG builds, with UserDefaults "debug_e2eSuppressPushPrompt"
// flipped on by the Maestro driver before app launch
// (xcrun simctl spawn <udid> defaults write <bundle> debug_e2eSuppressPushPrompt -bool YES).
public enum E2EPushPermission {
    public static let userDefaultsKey = "debug_e2eSuppressPushPrompt"

    public static var isSuppressed: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: userDefaultsKey)
        #else
        return false
        #endif
    }
}
