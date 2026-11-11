import Foundation

// Debug builds only: lets UI automation skip the push-permission prompt, which
// otherwise appears a few seconds after the wallet is ready and takes the taps.
// Off unless the UserDefaults flag below is set before launch; always off in Release.
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
