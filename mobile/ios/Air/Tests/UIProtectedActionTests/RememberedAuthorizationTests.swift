import Foundation
import ProtectedAction
import Testing
@testable import UIProtectedAction
import WalletContext
import WalletCore

@Suite("Remembered authorization", .serialized)
@MainActor
struct RememberedAuthorizationTests {
    @Test
    func `remembered session avoids biometric authentication`() async {
        let previous = AuthSupport
        AuthSupport = TestAuth.self
        defer { AuthSupport = previous }
        TestAuth.state.withLock { $0 = .init(rememberedToken: EnclaveToken("passcode:remembered")) }

        let token = await PasswordPresenter.tokenBeforePresentation(
            requiresFreshAuthentication: false, biometricPolicy: .beforePresentation
        )

        #expect(token == EnclaveToken("passcode:remembered"))
        #expect(TestAuth.state.withLock { $0.biometricCalls } == 0)
    }

    @Test(arguments: [BiometricPolicy.disabled, .onAuthorizationScreen])
    func `fresh authentication never consults the remembered session`(policy: BiometricPolicy) async {
        let previous = AuthSupport
        AuthSupport = TestAuth.self
        defer { AuthSupport = previous }
        TestAuth.state.withLock { $0 = .init(rememberedToken: EnclaveToken("biometric:remembered")) }

        let token = await PasswordPresenter.tokenBeforePresentation(
            requiresFreshAuthentication: true, biometricPolicy: policy
        )

        #expect(token == nil)
        #expect(TestAuth.state.withLock { $0.rememberedCalls } == 0)
        #expect(TestAuth.state.withLock { $0.biometricCalls } == 0)
    }

    @Test
    func `missing session falls back to the configured biometric policy`() async {
        let previous = AuthSupport
        AuthSupport = TestAuth.self
        defer { AuthSupport = previous }
        TestAuth.state.withLock { $0 = .init() }

        let onScreen = await PasswordPresenter.tokenBeforePresentation(
            requiresFreshAuthentication: false, biometricPolicy: .onAuthorizationScreen
        )
        #expect(onScreen == nil)
        #expect(TestAuth.state.withLock { $0.biometricCalls } == 0)

        let beforePresentation = await PasswordPresenter.tokenBeforePresentation(
            requiresFreshAuthentication: false, biometricPolicy: .beforePresentation
        )
        #expect(beforePresentation == EnclaveToken("biometric:fresh"))
        #expect(TestAuth.state.withLock { $0.biometricCalls } == 1)
    }
}

private enum TestAuth: AuthSupportProtocol {
    struct State {
        var rememberedToken: EnclaveToken?
        var rememberedCalls = 0
        var biometricCalls = 0
    }

    static let state = UnfairLock(initialState: State())
    static let accountsSupportAppLock = true
    static let hasPendingMultichainUpgrade = false
    static let cooldownRemaining: TimeInterval? = nil
    static var status: AuthStatus {
        AuthStatus(
            requiresAuthorization: true,
            configuredMethods: [.passcode, .biometrics],
            authorizableMethods: [.passcode, .biometrics],
            configurableMethods: []
        )
    }

    static func rememberedToken() async -> EnclaveToken? {
        state.withLock {
            $0.rememberedCalls += 1
            return $0.rememberedToken
        }
    }

    static func authorizeWithBiometrics(sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? {
        state.withLock { $0.biometricCalls += 1 }
        return EnclaveToken("biometric:fresh")
    }

    static func invalidateSessions() async {}
    static func setPasscode(_ passcode: String) async throws -> EnclaveToken { throw UnexpectedCall.error }
    static func changePasscode(to newPasscode: String, using authorizationToken: EnclaveToken) async throws { throw UnexpectedCall.error }
    static func enableBiometrics(using authorizationToken: EnclaveToken) async throws -> EnclaveToken { throw UnexpectedCall.error }
    static func disableBiometrics(using authorizationToken: EnclaveToken) async throws { throw UnexpectedCall.error }
    static func authorizeWithPasscode(_ passcode: String, sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? { throw UnexpectedCall.error }

    private enum UnexpectedCall: Error { case error }
}
