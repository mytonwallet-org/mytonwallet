import Foundation

public enum AuthType: String, Sendable {
    case passcode
    case biometric

    public static func from(token: EnclaveToken) -> AuthType? {
        guard let prefix = token.rawValue.split(separator: ":").first else {
            return nil
        }
        return AuthType(rawValue: String(prefix))
    }
}
