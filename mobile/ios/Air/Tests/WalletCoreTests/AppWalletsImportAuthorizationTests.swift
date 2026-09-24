#if DEBUG && targetEnvironment(simulator)

import Foundation
import Testing
@testable import NativeEnclave
@testable import WalletCore

@Suite("Debug Wallet Restore Authorization", .serialized)
@MainActor
struct AppWalletsImportAuthorizationTests {
    @Test
    func `fresh setup provides reusable authorization for mnemonic reads`() async throws {
        RestoreAuthSupport.state = .init()

        let token = try await authorize(.reusable)

        #expect(RestoreAuthSupport.state.setupCount == 1)
        for _ in 0..<3 {
            try await consume(token)
        }
    }

    @Test
    func `each restored mnemonic receives a fresh one-use token`() async throws {
        RestoreAuthSupport.state = .init()
        let inspectionToken = try await authorize(.reusable)
        try await consume(inspectionToken)

        var importedTokens = Set<EnclaveToken>()
        for _ in 0..<3 {
            let token = try await authorize(.oneShot)
            #expect(importedTokens.insert(token).inserted)
            try await consume(token)
            await #expect(throws: EnclaveError.self) {
                try await consume(token)
            }
        }
        #expect(RestoreAuthSupport.state.setupCount == 1)
    }

    @Test
    func `existing authentication is preserved when restoring again`() async throws {
        RestoreAuthSupport.state = .init(isConfigured: true)

        let token = try await authorize(.reusable)

        #expect(RestoreAuthSupport.state.setupCount == 0)
        try await consume(token)
        try await consume(token)
    }

    @Test
    func `invalid passcode stops restore authorization`() async {
        RestoreAuthSupport.state = .init(isConfigured: true)

        await #expect(throws: AppWalletsExport.ImportError.self) {
            _ = try await AppWalletsExport.authorizeImport(
                passcode: "wrong",
                sessionKind: .oneShot,
                authSupport: RestoreAuthSupport.self
            )
        }
        #expect(RestoreAuthSupport.state.setupCount == 0)
    }

    private func authorize(_ sessionKind: AuthSessionKind) async throws -> EnclaveToken {
        try await AppWalletsExport.authorizeImport(
            passcode: "2222",
            sessionKind: sessionKind,
            authSupport: RestoreAuthSupport.self
        )
    }

    private func consume(_ token: EnclaveToken) async throws {
        _ = try await RestoreAuthSupport.state.sessions.validateSessionAndGetMasterKey(
            token: token,
            invalidateShortSession: true
        )
    }
}

private enum RestoreAuthSupport: AuthSupportProtocol {
    struct State {
        var isConfigured = false
        var setupCount = 0
        let sessions = SessionManager()
    }

    // Accessed only by the serialized suite; production AuthSupport and Keychain are untouched.
    nonisolated(unsafe) static var state = State()

    static var status: AuthStatus {
        AuthStatus(
            requiresAuthorization: state.isConfigured,
            configuredMethods: state.isConfigured ? [.passcode] : [],
            authorizableMethods: state.isConfigured ? [.passcode] : [],
            configurableMethods: []
        )
    }

    static func setPasscode(_ passcode: String) async throws -> EnclaveToken {
        state.isConfigured = true
        state.setupCount += 1
        return try await state.sessions.createSession(
            authType: .passcode,
            isLong: false,
            masterKey: Data(repeating: 7, count: 32)
        ).token
    }

    static func authorizeWithPasscode(_ passcode: String, sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? {
        guard state.isConfigured, passcode == "2222" else { return nil }
        return try await state.sessions.createSession(
            authType: .passcode,
            isLong: sessionKind == .reusable,
            usageCount: 1 + extraUsages,
            masterKey: Data(repeating: 7, count: 32)
        ).token
    }

    static var accountsSupportAppLock: Bool { state.isConfigured }
    static var hasPendingMultichainUpgrade: Bool { false }
    static var cooldownRemaining: TimeInterval? { nil }

    static func rememberedToken() async -> EnclaveToken? {
        await state.sessions.rememberedSession()?.token
    }

    static func invalidateSessions() async {
        await state.sessions.clearAll()
    }

    static func changePasscode(to: String, using: EnclaveToken) async throws { throw UnexpectedCall.unused }
    static func enableBiometrics(using: EnclaveToken) async throws -> EnclaveToken { throw UnexpectedCall.unused }
    static func disableBiometrics(using: EnclaveToken) async throws { throw UnexpectedCall.unused }
    static func authorizeWithBiometrics(sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? {
        throw UnexpectedCall.unused
    }

    private enum UnexpectedCall: Error { case unused }
}

#endif
