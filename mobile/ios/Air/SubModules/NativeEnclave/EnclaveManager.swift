import Foundation

public actor EnclaveManager {
    public static let shared = EnclaveManager()

    public static func configuredAuthTypes() -> Set<AuthType> {
        let storage = EnclaveStorage()
        guard let version = try? storage.loadVersion(), version == EnclaveStorage.currentVersion else {
            return []
        }

        var authTypes = Set<AuthType>()

        if (try? storage.loadPasscodeCredential()) != nil {
            authTypes.insert(.passcode)
        }
        if storage.loadBiometricMasterKey() != nil {
            authTypes.insert(.biometric)
        }

        return authTypes
    }

    public static func isLegacyMigrationAllowed() -> Bool {
        do {
            return try EnclaveStorage().loadVersion() == nil
        } catch {
            return false
        }
    }

    private let storage = EnclaveStorage()
    private let sessionManager = SessionManager()
    private lazy var auths: [AuthType: any EnclaveAuth] = [
        .passcode: PasscodeAuth(storage: storage),
        .biometric: BiometricAuth(storage: storage),
    ]

    private init() {}

    public func setupAuth(authType: AuthType, passcode: String?) async throws -> SessionResult {
        try ensureStorageCanBeInitialized()
        try await resetForInitialization()
        let masterKey = try KeyDerivation.generateMasterKey()

        guard let auth = auths[authType] else {
            throw EnclaveError.unknownAuthType(authType.rawValue)
        }

        do {
            try await auth.setup(masterKey: masterKey, passcode: passcode)
            let session = try await sessionManager.createSession(
                authType: authType,
                isLong: false,
                masterKey: masterKey
            )
            try storage.storeCurrentVersion()
            return session
        } catch {
            try await resetForInitialization()
            throw error
        }
    }

    public func authorize(
        authType: AuthType,
        isLong: Bool,
        usageCount: Int = 1,
        passcode: String?
    ) async throws -> SessionResult? {
        try requireCurrentStorageVersion()

        guard let auth = auths[authType] else {
            throw EnclaveError.unknownAuthType(authType.rawValue)
        }

        do {
            let masterKey = try await auth.authorize(passcode: passcode)
            return try await sessionManager.createSession(
                authType: authType,
                isLong: isLong,
                usageCount: usageCount,
                masterKey: masterKey
            )
        } catch EnclaveError.invalidSessionToken where authType == .passcode {
            return nil
        }
    }

    public func migrateAuth(
        currentToken: EnclaveToken,
        newAuthType: AuthType,
        passcode: String?,
        shouldReplace: Bool,
        isLong: Bool = false,
        usageCount: Int = 1
    ) async throws -> SessionResult {
        try requireCurrentStorageVersion()

        let masterKey = try await sessionManager.validateSessionAndGetMasterKey(
            token: currentToken,
            invalidateShortSession: false
        )
        guard let currentAuthType = AuthType.from(token: currentToken) else {
            throw EnclaveError.invalidCurrentToken
        }

        guard let newAuth = auths[newAuthType] else {
            throw EnclaveError.unknownAuthType(newAuthType.rawValue)
        }

        try await newAuth.setup(masterKey: masterKey, passcode: passcode)
        await sessionManager.invalidateShortSession(token: currentToken)

        if shouldReplace && currentAuthType != newAuthType, let currentAuth = auths[currentAuthType] {
            await currentAuth.destroy()
        }

        return try await sessionManager.createSession(
            authType: newAuthType,
            isLong: isLong,
            usageCount: usageCount,
            masterKey: masterKey
        )
    }

    public func removeAuth(authType: AuthType) async {
        guard let auth = auths[authType] else {
            return
        }
        await auth.destroy()
    }

    public func ensureValidSession(token: EnclaveToken, consumeIfNeeded: Bool) async throws {
        _ = try await sessionManager.validateSessionAndGetMasterKey(
            token: token,
            invalidateShortSession: consumeIfNeeded
        )
    }

    public func importSecret(id: String, secret: String, token: EnclaveToken) async throws {
        try requireCurrentStorageVersion()

        let masterKey = try await sessionManager.validateSessionAndGetMasterKey(
            token: token,
            invalidateShortSession: true
        )
        let encrypted = try encryptForStorage(Data(secret.utf8), masterKey: masterKey)
        try storage.storeSecret(id: id, encrypted: encrypted)
    }

    public func exportSecret(id: String, token: EnclaveToken) async throws -> String {
        try requireCurrentStorageVersion()

        let masterKey = try await sessionManager.validateSessionAndGetMasterKey(
            token: token,
            invalidateShortSession: true
        )
        let stored = try storage.loadSecret(id: id)
        let decrypted = try decryptFromStorage(stored, masterKey: masterKey)
        guard let secret = String(data: decrypted, encoding: .utf8) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        return secret
    }

    public func duplicateSecret(fromId: String, toId: String) throws {
        try requireCurrentStorageVersion()
        try storage.copySecret(fromId: fromId, toId: toId)
    }

    public func removeSecret(id: String) {
        storage.removeSecret(id: id)
    }

    public func existingSecretIds(in accountIds: Set<String>) throws -> Set<String> {
        try requireCurrentStorageVersion()
        return try Set(
            accountIds.filter { try storage.containsSecret(id: $0) }
        )
    }

    // Deliberately ignores the storage version: answers whether anything is
    // sealed in storage at all, so callers can tell live auth from a leftover
    // of a setup that never stored a secret.
    public func hasStoredSecrets() throws -> Bool {
        try storage.hasAnySecret()
    }

    public func sign(id: String, data: String, token: EnclaveToken) async throws {
        try requireCurrentStorageVersion()

        _ = data
        _ = try await sessionManager.validateSessionAndGetMasterKey(
            token: token,
            invalidateShortSession: true
        )

        if try !storage.containsSecret(id: id) {
            throw EnclaveError.secretNotFound(id)
        }
    }

    public func reset() async {
        await sessionManager.clearAll()
        for auth in auths.values {
            await auth.destroy()
        }
        storage.clear()
    }

    public func migrateSecrets(
        secrets: [(id: String, secret: String)],
        requiredSecretIds: Set<String>,
        authType: AuthType,
        passcode: String?,
        isLong: Bool
    ) async throws -> SessionResult {
        let secretIds = Set(secrets.map(\.id))
        guard secretIds.count == secrets.count,
              requiredSecretIds.isSubset(of: secretIds) else {
            throw EnclaveError.malformedEncryptedPayload
        }
        try ensureStorageCanBeInitialized()
        try await resetForInitialization()

        do {
            let masterKey = try KeyDerivation.generateMasterKey()
            guard let auth = auths[authType] else {
                throw EnclaveError.unknownAuthType(authType.rawValue)
            }

            var encryptedPairs: [(id: String, encrypted: String)] = []
            encryptedPairs.reserveCapacity(secrets.count)

            for entry in secrets {
                let encrypted = try encryptForStorage(Data(entry.secret.utf8), masterKey: masterKey)
                encryptedPairs.append((id: entry.id, encrypted: encrypted))
            }

            try await auth.setup(masterKey: masterKey, passcode: passcode)
            try storage.storeSecretsBatch(encryptedPairs)
            let session = try await sessionManager.createSession(
                authType: authType,
                isLong: isLong,
                masterKey: masterKey
            )
            try storage.storeCurrentVersion()
            return session
        } catch {
            try await resetForInitialization()
            throw error
        }
    }

    private func resetForInitialization() async throws {
        await sessionManager.clearAll()
        for auth in auths.values {
            await auth.destroy()
        }
        try storage.clearChecked()
    }

    private func ensureStorageCanBeInitialized() throws {
        guard let version = try storage.loadVersion() else {
            return
        }
        guard version != EnclaveStorage.currentVersion else {
            throw EnclaveError.authAlreadyConfigured
        }
        throw EnclaveError.unsupportedEnclaveVersion(String(version))
    }

    private func requireCurrentStorageVersion() throws {
        guard let version = try storage.loadVersion() else {
            throw EnclaveError.enclaveNotConfigured
        }
        guard version == EnclaveStorage.currentVersion else {
            throw EnclaveError.unsupportedEnclaveVersion(String(version))
        }
    }

    private func encryptForStorage(_ data: Data, masterKey: Data) throws -> String {
        let encrypted = try AesGcm.encrypt(data, keyData: masterKey)
        return try HardwareKeyManager.encrypt(encrypted)
    }

    private func decryptFromStorage(_ stored: String, masterKey: Data) throws -> Data {
        let encrypted = try HardwareKeyManager.decrypt(stored)
        return try AesGcm.decrypt(encrypted, keyData: masterKey)
    }
}
