import Foundation
import LocalAuthentication

final class BiometricAuth: EnclaveAuth {
    private let storage: EnclaveStorage
    private let authReason = "Use biometrics to authorize this action"

    init(storage: EnclaveStorage) {
        self.storage = storage
    }

    func setup(masterKey: Data, passcode: String?) async throws {
        _ = passcode

        let context = try await Self.authenticateForSetup()
        try setup(masterKey: masterKey, context: context)
    }

    @MainActor
    static func authenticateForSetup() async throws -> sending LAContext {
        try await BiometricAuthenticator.authenticate(reason: "Use biometrics to protect your wallet")
    }

    func setup(masterKey: Data, context: LAContext) throws {
        try Self.setup(
            masterKey: masterKey,
            loadBiometricKey: { try HardwareKeyManager.loadBiometricKeyForSetup(context: context) },
            storeBiometricMasterKey: storage.storeBiometricMasterKey
        )
    }

    func authorize(passcode: String?) async throws -> Data {
        _ = passcode

        guard let encrypted = storage.loadBiometricMasterKey() else {
            throw EnclaveError.biometricNotConfigured
        }
        let context = try await BiometricAuthenticator.authenticate(reason: authReason)
        return try Self.authorize(
            encrypted: encrypted,
            loadBiometricKey: { try HardwareKeyManager.loadBiometricKey(context: context) }
        )
    }

    func destroy() async {
        HardwareKeyManager.deleteBiometricKey()
        storage.removeBiometricMasterKey()
    }

    static func setup(
        masterKey: Data,
        loadBiometricKey: () throws -> Data,
        storeBiometricMasterKey: (String) throws -> Void
    ) throws {
        let biometricKey = try loadBiometricKey()
        let encrypted = try AesGcm.encrypt(masterKey, keyData: biometricKey)
        try storeBiometricMasterKey(encrypted)
    }

    static func authorize(encrypted: String, loadBiometricKey: () throws -> Data) throws -> Data {
        let biometricKey = try loadBiometricKey()
        do {
            return try AesGcm.decrypt(encrypted, keyData: biometricKey)
        } catch {
            throw EnclaveError.biometricKeyInvalidated
        }
    }
}

enum BiometricAuthenticator {
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
            throw mapAuthenticationError(error)
        } catch {
            throw EnclaveError.biometricAuthenticationFailed(error.localizedDescription)
        }
    }

    static func mapAuthenticationError(_ error: LAError) -> EnclaveError {
        switch error.code {
        // "Enter Password" in the system prompt chooses the wallet passcode the caller already offers
        case .userCancel, .systemCancel, .appCancel, .userFallback:
            .biometricAuthenticationCanceled
        case .biometryNotAvailable:
            .biometricPermissionDenied
        default:
            .biometricAuthenticationFailed(error.localizedDescription)
        }
    }
}
