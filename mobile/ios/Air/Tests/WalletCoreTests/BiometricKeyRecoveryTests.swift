import Foundation
import LocalAuthentication
import Security
import Testing
import WalletContext
@testable import NativeEnclave

@Suite("Biometric key recovery")
struct BiometricKeyRecoveryTests {
    @Test
    func identifyMissingOrInvalidatedKeyAfterBiometricAuthentication() {
        for loadData: () throws -> Data? in [
            { nil },
            { throw EnclaveError.keychainError(errSecAuthFailed) },
        ] {
            do {
                _ = try HardwareKeyManager.loadBiometricKey(loadData: loadData)
                Issue.record("An unavailable biometric key must require passcode recovery")
            } catch EnclaveError.biometricKeyInvalidated {
            } catch {
                Issue.record("Unexpected biometric recovery error: \(error)")
            }
        }
    }

    @Test(arguments: [LAError.Code.userCancel, .systemCancel, .appCancel, .userFallback])
    func treatPasscodeFallbackAsCancellation(code: LAError.Code) {
        guard case .biometricAuthenticationCanceled = BiometricAuthenticator.mapAuthenticationError(LAError(code)) else {
            Issue.record("Choosing the wallet passcode must not report a biometric failure")
            return
        }
    }

    @Test(arguments: [LAError.Code.authenticationFailed, .biometryLockout])
    func reportUnsuccessfulBiometricAuthentication(code: LAError.Code) {
        guard case .biometricAuthenticationFailed = BiometricAuthenticator.mapAuthenticationError(LAError(code)) else {
            Issue.record("An unsuccessful biometric match must report a failure")
            return
        }
    }

    @Test
    func reuseAvailableKey() throws {
        let key = Data(repeating: 7, count: 32)
        let loaded = try HardwareKeyManager.loadBiometricKeyForSetup(
            ensureKey: {},
            loadKey: { key },
            deleteKey: { Issue.record("An available key must remain intact") }
        )
        #expect(loaded == key)
    }

    @Test
    func replaceOnlyInvalidatedKey() throws {
        let key = Data(repeating: 9, count: 32)
        var operations: [String] = []
        var hasRecreatedKey = false
        let loaded = try HardwareKeyManager.loadBiometricKeyForSetup(
            ensureKey: { operations.append("ensure") },
            loadKey: {
                operations.append("load")
                guard hasRecreatedKey else { throw EnclaveError.biometricKeyInvalidated }
                return key
            },
            deleteKey: {
                operations.append("delete")
                hasRecreatedKey = true
            }
        )
        #expect(loaded == key)
        #expect(operations == ["ensure", "load", "delete", "ensure", "load"])
    }

    @Test(arguments: [
        EnclaveError.biometricAuthenticationCanceled,
        .biometricNotAvailable,
        .biometricAuthenticationFailed("Locked out"),
        .keychainError(errSecInteractionNotAllowed),
        .keychainError(errSecNotAvailable),
    ])
    func preserveKeyAfterTemporaryFailure(error: EnclaveError) {
        #expect(throws: EnclaveError.self) {
            try HardwareKeyManager.loadBiometricKeyForSetup(
                ensureKey: {},
                loadKey: { throw error },
                deleteKey: { Issue.record("Temporary failures must not delete biometric credentials") }
            )
        }
    }

    @Test
    func stopWhenInvalidatedKeyCannotBeRemoved() {
        var ensureCount = 0
        #expect(throws: EnclaveError.self) {
            try HardwareKeyManager.loadBiometricKeyForSetup(
                ensureKey: { ensureCount += 1 },
                loadKey: { throw EnclaveError.biometricKeyInvalidated },
                deleteKey: { throw EnclaveError.keychainError(errSecInteractionNotAllowed) }
            )
        }
        #expect(ensureCount == 1)
    }

    @Test
    func requireRecoveryAfterFailedWrapperWriteAndRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let keyUrl = directory.appendingPathComponent("biometric-key")
        let wrapperUrl = directory.appendingPathComponent("biometric-wrapper")
        let masterKey = Data(repeating: 5, count: 32)
        let originalKey = Data(repeating: 7, count: 32)
        let replacementKey = Data(repeating: 9, count: 32)
        let originalWrapper = try AesGcm.encrypt(masterKey, keyData: originalKey)
        try originalKey.write(to: keyUrl)
        try originalWrapper.write(to: wrapperUrl, atomically: true, encoding: .utf8)

        do {
            try BiometricAuth.setup(
                masterKey: masterKey,
                loadBiometricKey: {
                    try HardwareKeyManager.loadBiometricKeyForSetup(
                        ensureKey: {
                            if !FileManager.default.fileExists(atPath: keyUrl.path) {
                                try replacementKey.write(to: keyUrl)
                            }
                        },
                        loadKey: {
                            let key = try Data(contentsOf: keyUrl)
                            guard key != originalKey else { throw EnclaveError.biometricKeyInvalidated }
                            return key
                        },
                        deleteKey: { try FileManager.default.removeItem(at: keyUrl) }
                    )
                },
                storeBiometricMasterKey: { _ in throw EnclaveError.keychainError(errSecNotAvailable) }
            )
            Issue.record("The wrapper write must fail after key replacement")
        } catch EnclaveError.keychainError(errSecNotAvailable) {
        }

        // A fresh launch loads only the key and wrapper that survived the failed write
        let reloadedKey = try Data(contentsOf: keyUrl)
        let reloadedWrapper = try String(contentsOf: wrapperUrl, encoding: .utf8)
        #expect(reloadedKey == replacementKey)
        #expect(reloadedWrapper == originalWrapper)
        do {
            _ = try BiometricAuth.authorize(encrypted: reloadedWrapper, loadBiometricKey: { reloadedKey })
            Issue.record("A mismatched biometric wrapper must require passcode recovery")
        } catch EnclaveError.biometricKeyInvalidated {
        }

        try BiometricAuth.setup(
            masterKey: masterKey,
            loadBiometricKey: { reloadedKey },
            storeBiometricMasterKey: { try $0.write(to: wrapperUrl, atomically: true, encoding: .utf8) }
        )
        let recoveredWrapper = try String(contentsOf: wrapperUrl, encoding: .utf8)
        #expect(try BiometricAuth.authorize(encrypted: recoveredWrapper, loadBiometricKey: { reloadedKey }) == masterKey)
    }

    @Test(arguments: ["not-base64", "AAA="])
    func requireRecoveryForMalformedBiometricWrapper(encrypted: String) throws {
        do {
            _ = try BiometricAuth.authorize(encrypted: encrypted, loadBiometricKey: { Data(repeating: 7, count: 32) })
            Issue.record("An unreadable biometric wrapper must require passcode recovery")
        } catch EnclaveError.biometricKeyInvalidated {
        }
    }

    @Test(arguments: [errSecInteractionNotAllowed, errSecNotAvailable])
    func preserveKeychainErrorsBeforeWrapperDecryption(status: OSStatus) throws {
        do {
            _ = try BiometricAuth.authorize(encrypted: "not-read", loadBiometricKey: { throw EnclaveError.keychainError(status) })
            Issue.record("The keychain failure must propagate")
        } catch EnclaveError.keychainError(let actualStatus) {
            #expect(actualStatus == status)
        }
    }

    @Test(arguments: [1, 4])
    func preserveOriginalUsageBudgetAfterRecovery(originalUsages: Int) async throws {
        let manager = SessionManager()
        let key = Data(repeating: 7, count: 32)
        let session = try await manager.createSession(
            authType: .passcode, isLong: false, usageCount: originalUsages + 1, masterKey: key
        )

        try await manager.consumeBiometricRecoveryUsage(token: session.token)

        for _ in 0..<originalUsages {
            #expect(try await manager.validateSessionAndGetMasterKey(
                token: session.token, invalidateShortSession: true
            ) == key)
        }
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: session.token, invalidateShortSession: true)
        }
    }

    @Test
    func rejectRecoveryWithoutReservedUsage() async throws {
        let manager = SessionManager()
        let key = Data(repeating: 7, count: 32)
        let session = try await manager.createSession(authType: .passcode, isLong: false, masterKey: key)

        await #expect(throws: EnclaveError.self) {
            try await manager.consumeBiometricRecoveryUsage(token: session.token)
        }
        #expect(try await manager.validateSessionAndGetMasterKey(
            token: session.token, invalidateShortSession: true
        ) == key)
    }

    @Test
    func rejectBiometricSessionForRecovery() async throws {
        let manager = SessionManager()
        let session = try await manager.createSession(
            authType: .biometric, isLong: true, masterKey: Data(repeating: 7, count: 32)
        )
        await #expect(throws: EnclaveError.self) {
            try await manager.consumeBiometricRecoveryUsage(token: session.token)
        }
    }

    @Test
    func rejectExpiredRecoverySession() async throws {
        let now = UnfairLock<Int64>(initialState: 1_000)
        let manager = SessionManager(now: { now.withLock { $0 } })
        let session = try await manager.createSession(
            authType: .passcode, isLong: true, masterKey: Data(repeating: 7, count: 32)
        )
        now.withLock { $0 = session.validUntil }
        await #expect(throws: EnclaveError.self) {
            try await manager.consumeBiometricRecoveryUsage(token: session.token)
        }
    }

    @Test
    func revokeOtherLongSessionsWithoutInterruptingRecoveryAction() async throws {
        let manager = SessionManager()
        let key = Data(repeating: 7, count: 32)
        let previous = try await manager.createSession(authType: .biometric, isLong: true, remember: true, masterKey: key)
        let current = try await manager.createSession(authType: .passcode, isLong: true, masterKey: key)
        let otherAction = try await manager.createSession(authType: .passcode, isLong: false, masterKey: key)

        await manager.invalidateLongSessions(except: current.token)

        #expect(await manager.rememberedSession() == nil)
        await #expect(throws: EnclaveError.self) {
            _ = try await manager.validateSessionAndGetMasterKey(token: previous.token, invalidateShortSession: false)
        }
        for token in [current.token, otherAction.token] {
            #expect(try await manager.validateSessionAndGetMasterKey(token: token, invalidateShortSession: true) == key)
        }
    }
}
