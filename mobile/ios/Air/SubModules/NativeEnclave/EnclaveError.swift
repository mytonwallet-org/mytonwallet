import Foundation
import Security

public enum EnclaveError: LocalizedError {
    case unknownAuthType(String)
    case passcodeRequired
    case passcodeNotConfigured
    case biometricNotConfigured
    case biometricNotAvailable
    case biometricPermissionDenied
    case biometricAuthenticationCanceled
    case biometricAuthenticationFailed(String)
    case invalidSessionToken
    case sessionExpired
    case secretNotFound(String)
    case malformedEncryptedPayload
    case keychainError(OSStatus)
    case invalidCurrentToken
    case enclaveNotConfigured
    case authAlreadyConfigured
    case unsupportedEnclaveVersion(String)

    public var errorDescription: String? {
        switch self {
        case let .unknownAuthType(value):
            return "Unknown auth type: \(value)"
        case .passcodeRequired:
            return "Passcode is required"
        case .passcodeNotConfigured:
            return "Passcode not configured"
        case .biometricNotConfigured:
            return "Biometric auth not configured"
        case .biometricNotAvailable:
            return "Biometric authentication is not available"
        case .biometricPermissionDenied:
            return "Biometric authentication permission was denied"
        case .biometricAuthenticationCanceled:
            return "Biometric authentication was canceled"
        case let .biometricAuthenticationFailed(message):
            return message
        case .invalidSessionToken:
            return "Invalid or expired session token"
        case .sessionExpired:
            return "Session expired"
        case let .secretNotFound(id):
            return "Secret not found: \(id)"
        case .malformedEncryptedPayload:
            return "Malformed encrypted payload"
        case let .keychainError(status):
            return "Keychain error: \(status)"
        case .invalidCurrentToken:
            return "Invalid current token"
        case .enclaveNotConfigured:
            return "Enclave storage is not configured"
        case .authAlreadyConfigured:
            return "Authentication is already configured"
        case let .unsupportedEnclaveVersion(value):
            return "Unsupported enclave version: \(value)"
        }
    }
}
