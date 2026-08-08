import Foundation
import LocalAuthentication

final class BiometricAuth: EnclaveAuth {
    private let storage: EnclaveStorage
    private let setupReason = "Use biometrics to protect your wallet"
    private let authReason = "Use biometrics to authorize this action"

    init(storage: EnclaveStorage) {
        self.storage = storage
    }

    func setup(masterKey: Data, passcode: String?) async throws {
        _ = passcode

        try HardwareKeyManager.ensureBiometricKey()
        let context = try await BiometricAuthenticator.authenticate(reason: setupReason)
        let biometricKey = try HardwareKeyManager.loadBiometricKey(context: context)
        let encrypted = try AesGcm.encrypt(masterKey, keyData: biometricKey)
        try storage.storeBiometricMasterKey(encrypted)
    }

    func authorize(passcode: String?) async throws -> Data {
        _ = passcode

        guard let encrypted = storage.loadBiometricMasterKey() else {
            throw EnclaveError.biometricNotConfigured
        }
        let context = try await BiometricAuthenticator.authenticate(reason: authReason)
        let biometricKey = try HardwareKeyManager.loadBiometricKey(context: context)
        return try AesGcm.decrypt(encrypted, keyData: biometricKey)
    }

    func destroy() async {
        HardwareKeyManager.deleteBiometricKey()
        storage.removeBiometricMasterKey()
    }
}

private enum BiometricAuthenticator {
    @MainActor
    static func authenticate(reason: String) async throws(EnclaveError) -> sending LAContext {
        let context = LAContext()

        var canEvaluateError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &canEvaluateError) else {
            throw EnclaveError.biometricNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            if !success {
                throw EnclaveError.biometricAuthenticationFailed("Biometric authentication failed")
            }
            return context
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .systemCancel, .appCancel:
                throw EnclaveError.biometricAuthenticationCanceled
            case .biometryNotAvailable:
                throw EnclaveError.biometricPermissionDenied
            default:
                throw EnclaveError.biometricAuthenticationFailed(error.localizedDescription)
            }
        } catch {
            throw EnclaveError.biometricAuthenticationFailed(error.localizedDescription)
        }
    }
}
