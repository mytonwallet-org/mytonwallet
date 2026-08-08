import Foundation
import LocalAuthentication
import NativeEnclave
import WalletContext

private let authSupportLog = Log("AuthSupport")

public enum AuthMethod: String, Sendable, Hashable, CaseIterable {
    case passcode
    case biometrics = "biometric"
}

public enum AuthSessionKind: Sendable {
    case oneShot
    case reusable

    var isLong: Bool {
        self == .reusable
    }
}

public struct AuthStatus: Sendable {
    public let requiresAuthorization: Bool
    public let configuredMethods: Set<AuthMethod>
    public let authorizableMethods: Set<AuthMethod>
    public let configurableMethods: Set<AuthMethod>

    public init(
        requiresAuthorization: Bool,
        configuredMethods: Set<AuthMethod>,
        authorizableMethods: Set<AuthMethod>,
        configurableMethods: Set<AuthMethod>
    ) {
        self.requiresAuthorization = requiresAuthorization
        self.configuredMethods = configuredMethods
        self.authorizableMethods = authorizableMethods
        self.configurableMethods = configurableMethods
    }
}

public protocol AuthSupportProtocol {
    static var status: AuthStatus { get }
    static func setPasscode(_ passcode: String) async throws -> EnclaveToken
    static func changePasscode(to newPasscode: String, using authorizationToken: EnclaveToken) async throws
    static func enableBiometrics(using authorizationToken: EnclaveToken) async throws -> EnclaveToken
    static func disableBiometrics(using authorizationToken: EnclaveToken) async throws
    static func authorizeWithPasscode(_ passcode: String, sessionKind: AuthSessionKind) async throws -> EnclaveToken?
    static func authorizeWithBiometrics(sessionKind: AuthSessionKind) async throws -> EnclaveToken?
    static var accountsSupportAppLock: Bool { get }
    static var cooldownRemaining: TimeInterval? { get }
}

@MainActor public var AuthSupport: AuthSupportProtocol.Type = AuthSupportImpl.self

public struct AuthCooldownError: Error {
    public var waitFor: TimeInterval
}

public enum AuthSupportError: LocalizedError {
    case authAlreadyConfigured

    public var errorDescription: String? {
        switch self {
        case .authAlreadyConfigured:
            return lang("Authentication is already configured")
        }
    }
}

public enum AuthSupportBiometricsError: LocalizedError {
    case canceled
    case userDeniedBiometrics
    case notAvailable

    public var errorDescription: String? {
        switch self {
        case .canceled:
            return lang("Canceled by the user")
        case .userDeniedBiometrics:
            return lang("To use this feature, first enable biometrics in your phone settings.")
        case .notAvailable:
            return lang("Biometric authentication not available.")
        }
    }
}

final class AuthSupportImpl: AuthSupportProtocol {
    static var status: AuthStatus {
        let configuredMethods = configuredMethods()
        let requiresAuthorization = AccountStore.accountsById.values.any { $0.type.isStoredEncrypted }
        let biometricsAvailable = isBiometricsAvailable()

        var authorizableMethods = Set<AuthMethod>()
        if configuredMethods.contains(.passcode) {
            authorizableMethods.insert(.passcode)
        }
        if configuredMethods.contains(.biometrics), biometricsAvailable {
            authorizableMethods.insert(.biometrics)
        }

        var configurableMethods = Set<AuthMethod>()
        if !configuredMethods.contains(.passcode) {
            configurableMethods.insert(.passcode)
        }
        if configuredMethods.contains(.passcode),
           !configuredMethods.contains(.biometrics),
           biometricsAvailable {
            configurableMethods.insert(.biometrics)
        }

        return AuthStatus(
            requiresAuthorization: requiresAuthorization,
            configuredMethods: configuredMethods,
            authorizableMethods: authorizableMethods,
            configurableMethods: configurableMethods
        )
    }

    static var accountsSupportAppLock: Bool {
        status.requiresAuthorization
    }

    static var cooldownRemaining: TimeInterval? {
        let waitFor = cooldownForNumberOfFailedAttempts(failedLoginAttempts) - Date.now.timeIntervalSince(lastFailedAttempt)
        return waitFor > 0 ? waitFor : nil
    }

    static var failedLoginAttempts: Int {
        get {
            let (_, s) = KeychainStorageProvider.get(key: "failedLoginAttempts")
            if let s, let count = Int(s) {
                return count
            }
            return 0
        }
        set {
            _ = KeychainStorageProvider.set(key: "failedLoginAttempts", value: String(newValue))
        }
    }

    static var lastFailedAttempt: Date {
        get {
            let (_, s) = KeychainStorageProvider.get(key: "lastFailedAttempt")
            if let s, let ts = Double(s) {
                return Date(timeIntervalSince1970: ts)
            }
            return .distantPast
        }
        set {
            _ = KeychainStorageProvider.set(key: "lastFailedAttempt", value: String(newValue.timeIntervalSince1970))
        }
    }

    static func setPasscode(_ passcode: String) async throws -> EnclaveToken {
        let status = Self.status
        if !status.configuredMethods.isEmpty {
            // Auth that guards no secret and no encrypted account is a leftover of
            // a setup that never stored a wallet; keeping it would block wallet
            // creation forever. Resetting is safe only in that provably-empty state.
            let hasStoredSecrets = try await EnclaveManager.shared.hasStoredSecrets()
            guard !status.requiresAuthorization, !hasStoredSecrets else {
                throw AuthSupportError.authAlreadyConfigured
            }
            await clearAllAuth()
        }

        let session = try await setupAuth(authType: .passcode, passcode: passcode)
        return session.token
    }

    static func changePasscode(to newPasscode: String, using authorizationToken: EnclaveToken) async throws {
        _ = try await migrateAuth(
            currentToken: authorizationToken,
            newAuthType: .passcode,
            passcode: newPasscode,
            shouldReplace: false
        )
    }

    static func enableBiometrics(using authorizationToken: EnclaveToken) async throws -> EnclaveToken {
        do {
            let session = try await migrateAuth(
                currentToken: authorizationToken,
                newAuthType: .biometric,
                passcode: nil,
                shouldReplace: false
            )
            AuthSupportLegacy.clearBiometricArtifacts()
            return session.token
        } catch EnclaveError.biometricAuthenticationCanceled {
            throw AuthSupportBiometricsError.canceled
        } catch EnclaveError.biometricPermissionDenied {
            throw AuthSupportBiometricsError.userDeniedBiometrics
        } catch EnclaveError.biometricNotAvailable {
            throw AuthSupportBiometricsError.notAvailable
        }
    }

    static func disableBiometrics(using authorizationToken: EnclaveToken) async throws {
        try await EnclaveManager.shared.ensureValidSession(
            token: authorizationToken,
            consumeIfNeeded: true
        )
        await EnclaveManager.shared.removeAuth(authType: .biometric)
        AuthSupportLegacy.clearBiometricArtifacts()
    }

    static func clearAllAuth() async {
        failedLoginAttempts = 0
        lastFailedAttempt = .distantPast
        await EnclaveManager.shared.reset()
        AuthSupportLegacy.clearBiometricArtifacts()
    }

    static func authorizeWithPasscode(
        _ passcode: String,
        sessionKind: AuthSessionKind
    ) async throws -> EnclaveToken? {
        do {
            if let waitFor = cooldownRemaining {
                throw AuthCooldownError(waitFor: waitFor)
            }
            if failedLoginAttempts >= 5 {
                try await Task.sleep(for: .seconds(3))
            }
            let upgradeUsageCount = await pendingMultichainUpgradeUsageCount()
            let enclaveToken = try await authorizeWithEnclave(
                passcode: passcode,
                sessionKind: sessionKind,
                usageCount: 1 + upgradeUsageCount
            )
            if let enclaveToken {
                failedLoginAttempts = 0
                lastFailedAttempt = .distantPast
                await AuthSupportLegacy.retryCleanupAfterCommittedMigration()
                startMultichainUpgradeIfNeeded(
                    enclaveToken: enclaveToken,
                    usageCount: upgradeUsageCount
                )
            } else {
                failedLoginAttempts += 1
                lastFailedAttempt = .now

                let waitFor = cooldownForNumberOfFailedAttempts(failedLoginAttempts)
                if waitFor > 0 {
                    throw AuthCooldownError(waitFor: waitFor)
                }
            }
            return enclaveToken
        } catch {
            throw error
        }
    }

    static func authorizeWithBiometrics(
        sessionKind: AuthSessionKind
    ) async throws -> EnclaveToken? {
        let upgradeUsageCount = await pendingMultichainUpgradeUsageCount()
        let usageCount = 1 + upgradeUsageCount
        let enclaveToken: EnclaveToken?

        if AuthSupportLegacy.hasLegacyBiometrics {
            enclaveToken = try await AuthSupportLegacy.authorizeWithBiometrics(
                sessionKind: sessionKind,
                usageCount: usageCount
            )
        } else {
            enclaveToken = try await authorizeEnclave(
                authType: .biometric,
                sessionKind: sessionKind,
                usageCount: usageCount,
                passcode: nil
            )
        }

        if let enclaveToken {
            await AuthSupportLegacy.retryCleanupAfterCommittedMigration()
            startMultichainUpgradeIfNeeded(
                enclaveToken: enclaveToken,
                usageCount: upgradeUsageCount
            )
        }
        return enclaveToken
    }

    private static func setupAuth(
        authType: AuthType,
        passcode: String?
    ) async throws -> SessionResult {
        do {
            return try await EnclaveManager.shared.setupAuth(authType: authType, passcode: passcode)
        } catch EnclaveError.authAlreadyConfigured {
            // EnclaveError text is not localized; surface the localized equivalent
            throw AuthSupportError.authAlreadyConfigured
        }
    }

    private static func migrateAuth(
        currentToken: EnclaveToken,
        newAuthType: AuthType,
        passcode: String?,
        shouldReplace: Bool
    ) async throws -> SessionResult {
        try await EnclaveManager.shared.migrateAuth(
            currentToken: currentToken,
            newAuthType: newAuthType,
            passcode: passcode,
            shouldReplace: shouldReplace
        )
    }

    private static func authorizeWithEnclave(
        passcode: String,
        sessionKind: AuthSessionKind,
        usageCount: Int
    ) async throws -> EnclaveToken? {
        if AuthSupportLegacy.needsMigration() {
            return try await AuthSupportLegacy.authorizeWithPasscode(
                passcode,
                sessionKind: sessionKind,
                usageCount: usageCount
            )
        }

        return try await authorizeEnclave(
            authType: .passcode,
            sessionKind: sessionKind,
            usageCount: usageCount,
            passcode: passcode
        )
    }

    private static func authorizeEnclave(
        authType: AuthType,
        sessionKind: AuthSessionKind,
        usageCount: Int,
        passcode: String?
    ) async throws -> EnclaveToken? {
        let session = try await EnclaveManager.shared.authorize(
            authType: authType,
            isLong: sessionKind.isLong,
            usageCount: usageCount,
            passcode: passcode
        )
        return session?.token
    }

    private static func pendingMultichainUpgradeUsageCount() async -> Int {
        guard MultichainAccountUpgradeDetector.needsSDKPreparation(
            nativeAccountsById: AccountStore.accountsById,
            storedAccountsJSON: KeychainHelper.getStorage(key: "accounts")
        ) else {
            return 0
        }

        do {
            try await Api.waitDataPreload()
            try await Api.repairInvalidBip39TonAuthTokens()
            return try await Api.getMultichainUpgradeCandidateIds().count
        } catch {
            authSupportLog.error("Failed to prepare multichain account upgrade: \(error, .public)")
            return 0
        }
    }

    private static func startMultichainUpgradeIfNeeded(
        enclaveToken: EnclaveToken,
        usageCount: Int
    ) {
        guard usageCount > 0 else {
            return
        }

        Task {
            do {
                try await Api.upgradeMultichainAccounts(enclaveToken: enclaveToken)
                authSupportLog.info("Upgraded \(usageCount, .public) multichain accounts")
            } catch {
                authSupportLog.error("Failed to upgrade multichain accounts: \(error, .public)")
            }
        }
    }

    private static func configuredMethods() -> Set<AuthMethod> {
        let nativeMethods = Set(EnclaveManager.configuredAuthTypes().map(authMethod))
        if !nativeMethods.isEmpty {
            return nativeMethods
        }

        return AuthSupportLegacy.configuredMethodsIfNoNativeAuth()
    }

    private static func isBiometricsAvailable() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    private static func authMethod(_ authType: AuthType) -> AuthMethod {
        switch authType {
        case .passcode:
            .passcode
        case .biometric:
            .biometrics
        }
    }

    private static func cooldownForNumberOfFailedAttempts(_ attempts: Int) -> TimeInterval {
        switch attempts {
        case ...4:
            0
        case 5:
            60
        case 6:
            300
        case 7:
            900
        default:
            3600
        }
    }
}
