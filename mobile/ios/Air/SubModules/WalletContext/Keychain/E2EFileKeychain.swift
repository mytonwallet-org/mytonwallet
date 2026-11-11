import Foundation

// Debug builds only: lets UI automation keep secure storage in a file inside the
// app sandbox instead of the Keychain, so a copied simulator keeps its wallets.
// Off unless the UserDefaults flag below is set before launch; always off in Release.
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