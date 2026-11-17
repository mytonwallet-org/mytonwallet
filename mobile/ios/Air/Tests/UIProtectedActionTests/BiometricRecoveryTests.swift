import UIKit
import XCTest
@testable import UIPasscode
import WalletContext
import WalletCore
import WalletResources

@MainActor
final class BiometricRecoveryTests: XCTestCase {
    func testShowPasscodeFallbackAndOfferRecoveryAfterCorrectPasscode() async throws {
        try await runWithRecoveryScreen(shouldKeepFallback: true) { controller, _, completedTokens in
            let fallback = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
            XCTAssertEqual(fallback.message, lang("$biometric_recovery_passcode"))
            XCTAssertEqual(controller.passcodeScreenView.enterPasscodeLabel.label.text, lang("Enter your Wallet Passcode"))
            XCTAssertTrue(completedTokens().isEmpty)

            await dismissAlert(on: controller)
            controller.passcodeSelected(passcode: "1234")
            try await waitUntil { controller.presentedViewController is UIAlertController }
            let offer = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
            XCTAssertEqual(offer.message, lang("$biometric_recovery_offer"))
            XCTAssertEqual(offer.actions.map(\.title), [lang("Not Now"), lang("$biometric_recovery_enable")])
            XCTAssertEqual(RecoveryAuth.state.withLock { $0.extraUsages }, [3])
            XCTAssertTrue(completedTokens().isEmpty)
        }
    }

    func testDoNotOfferRecoveryAfterWrongPasscode() async throws {
        try await runWithRecoveryScreen { controller, _, completedTokens in
            RecoveryAuth.state.withLock { $0.shouldAcceptPasscode = false }
            controller.passcodeSelected(passcode: "0000")
            try await waitUntil { controller.passcodeScreenView.isUserInteractionEnabled }

            XCTAssertNil(controller.presentedViewController)
            XCTAssertTrue(RecoveryAuth.state.withLock { $0.recoveryChoices.isEmpty })
            XCTAssertTrue(completedTokens().isEmpty)
        }
    }

    func testContinueOriginalActionAfterRecoveryOrSkip() async throws {
        for shouldEnable in [false, true] {
            try await runWithRecoveryScreen { controller, _, completedTokens in
                await controller.completeBiometricRecovery(using: "passcode:original", shouldEnable: shouldEnable)
                try await waitUntil { !completedTokens().isEmpty }

                XCTAssertEqual(completedTokens(), ["passcode:original"])
                XCTAssertEqual(RecoveryAuth.state.withLock { $0.recoveryChoices }, [shouldEnable])
            }
        }
    }

    func testContinueOriginalActionAfterCanceledReEnrollment() async throws {
        try await runWithRecoveryScreen { controller, _, completedTokens in
            RecoveryAuth.state.withLock { $0.shouldCancelRecovery = true }
            await controller.completeBiometricRecovery(using: "passcode:original", shouldEnable: true)
            try await waitUntil { !completedTokens().isEmpty }

            XCTAssertEqual(completedTokens(), ["passcode:original"])
        }
    }

    func testContinueWhenOfferHasAlreadyDismissed() async throws {
        try await runWithRecoveryScreen { controller, _, completedTokens in
            controller.dismissBiometricRecoveryOffer(using: "passcode:original", shouldEnable: false)
            try await waitUntil { !completedTokens().isEmpty }

            XCTAssertEqual(completedTokens(), ["passcode:original"])
            XCTAssertEqual(RecoveryAuth.state.withLock { $0.recoveryChoices }, [false])
        }
    }

    func testRequirePasscodeAgainWhenRecoverySessionExpires() async throws {
        try await runWithRecoveryScreen { controller, _, completedTokens in
            RecoveryAuth.state.withLock { $0.shouldExpireRecovery = true }
            controller.passcodeScreenView.isUserInteractionEnabled = false
            await controller.completeBiometricRecovery(using: "passcode:expired", shouldEnable: true)
            try await waitUntil { controller.passcodeScreenView.isUserInteractionEnabled }

            XCTAssertTrue(completedTokens().isEmpty)
            let fallback = try XCTUnwrap(controller.presentedViewController as? UIAlertController)
            XCTAssertEqual(fallback.message, lang("$biometric_recovery_passcode"))
        }
    }

    func testSkipRecoveryPromptsAfterUserDecision() async throws {
        try await runWithRecoveryScreen(shouldKeepFallback: true, shouldOfferRecovery: false) { controller, _, completedTokens in
            XCTAssertNil(controller.presentedViewController)

            controller.passcodeSelected(passcode: "1234")
            try await waitUntil { !completedTokens().isEmpty }

            XCTAssertEqual(completedTokens(), ["passcode:original"])
            XCTAssertNil(controller.presentedViewController)
            XCTAssertEqual(RecoveryAuth.state.withLock { $0.extraUsages }, [2])
            XCTAssertTrue(RecoveryAuth.state.withLock { $0.recoveryChoices.isEmpty })
        }
    }

    private func runWithRecoveryScreen(
        shouldKeepFallback: Bool = false,
        shouldOfferRecovery: Bool = true,
        run: (UnlockVC, UIWindow, () -> [EnclaveToken]) async throws -> Void
    ) async throws {
        _ = WalletResourcesBundle.bundle.load()
        let previousAuth = AuthSupport
        let wereAnimationsEnabled = UIView.areAnimationsEnabled
        AuthSupport = RecoveryAuth.self
        RecoveryAuth.state.withLock { $0 = .init(shouldOfferRecovery: shouldOfferRecovery) }
        UIView.setAnimationsEnabled(false)
        var completedTokens: [EnclaveToken] = []
        let controller = RecoveryUnlockController(
            animatedPresentation: true, dissmissWhenAuthorized: false,
            onDone: { completedTokens.append($0) }, extraAuthUsages: 2, successCompletionDelay: 0
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.beginAppearanceTransition(true, animated: false)
        controller.endAppearanceTransition()
        defer {
            window.isHidden = true
            AuthSupport = previousAuth
            UIView.setAnimationsEnabled(wereAnimationsEnabled)
        }
        if shouldOfferRecovery {
            try await waitUntil { controller.presentedViewController is UIAlertController }
        }
        if !shouldKeepFallback {
            await dismissAlert(on: controller)
        }
        try await run(controller, window, { completedTokens })
    }

    private func dismissAlert(on controller: UIViewController) async {
        (controller as? RecoveryUnlockController)?.dismissAlert()
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date.now.addingTimeInterval(5)
        while !condition(), Date.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(condition())
    }

}

private final class RecoveryUnlockController: UnlockVC {
    // Hostless package tests inspect alert content; UIKit presentation requires an app host
    private var alertController: UIViewController?

    override var presentedViewController: UIViewController? { alertController }

    override func presentBiometricRecoveryAlert(_ alert: UIAlertController) {
        alertController = alert
    }

    func dismissAlert() {
        alertController = nil
    }
}

private enum RecoveryAuth: AuthSupportProtocol {
    struct State {
        var extraUsages: [Int] = []
        var recoveryChoices: [Bool] = []
        var shouldAcceptPasscode = true
        var shouldCancelRecovery = false
        var shouldExpireRecovery = false
        var shouldOfferRecovery = true
    }

    static let state = UnfairLock(initialState: State())
    static let isBiometricRecoveryRequired = true
    static var shouldOfferBiometricRecovery: Bool { state.withLock { $0.shouldOfferRecovery } }
    static let accountsSupportAppLock = true
    static let hasPendingMultichainUpgrade = false
    static let cooldownRemaining: TimeInterval? = nil
    static var status: AuthStatus {
        AuthStatus(
            requiresAuthorization: true, configuredMethods: [.passcode, .biometrics],
            authorizableMethods: [.passcode], configurableMethods: []
        )
    }

    static func authorizeWithPasscode(_ passcode: String, sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? {
        state.withLock {
            $0.extraUsages.append(extraUsages)
            return $0.shouldAcceptPasscode ? "passcode:original" : nil
        }
    }

    static func recoverBiometrics(using authorizationToken: EnclaveToken, shouldEnable: Bool) async throws {
        try state.withLock {
            $0.recoveryChoices.append(shouldEnable)
            if $0.shouldExpireRecovery { throw AuthSupportBiometricsError.passcodeRequired }
            if $0.shouldCancelRecovery { throw AuthSupportBiometricsError.canceled }
        }
    }

    static func rememberedToken() async -> EnclaveToken? { nil }
    static func invalidateSessions() async {}
    static func setPasscode(_ passcode: String) async throws -> EnclaveToken { throw UnexpectedCall.error }
    static func changePasscode(to newPasscode: String, using authorizationToken: EnclaveToken) async throws { throw UnexpectedCall.error }
    static func enableBiometrics(using authorizationToken: EnclaveToken) async throws -> EnclaveToken { throw UnexpectedCall.error }
    static func disableBiometrics(using authorizationToken: EnclaveToken) async throws { throw UnexpectedCall.error }
    static func authorizeWithBiometrics(sessionKind: AuthSessionKind, extraUsages: Int) async throws -> EnclaveToken? { throw UnexpectedCall.error }

    private enum UnexpectedCall: Error { case error }
}
