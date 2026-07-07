//
//  PasswordOrLedger.swift
//  AirAsFramework
//
//  Created by nikstar on 22.07.2025.
//

import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore
import Ledger

private let passwordOrLedgerLog = Log("PasswordOrLedger")

@MainActor
public enum ProtectedActionPresenter {
    public static func authorizeProtectedAction<HeaderView: View, Result: MfaProtectedActionResult>(
        on viewController: UIViewController,
        account: MAccount,
        title: String,
        headerView: HeaderView,
        passwordAction: @escaping (String) async throws -> Result,
        ledgerSignData: (() async throws -> SignData)? = nil,
        ledgerFromAddress: String? = nil,
        presentationStyle: ProtectedActionPresentationStyle = .push,
        useBioOnPresent: Bool = true,
        completionBehavior: ProtectedActionCompletionBehavior = .popAuth,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        mfaTitle: String? = nil
    ) async throws -> Result? {
        try await viewController._authorizeProtectedAction(
            account: account,
            title: title,
            headerView: headerView,
            passwordAction: passwordAction,
            ledgerSignData: ledgerSignData,
            ledgerFromAddress: ledgerFromAddress,
            presentationStyle: presentationStyle,
            useBioOnPresent: useBioOnPresent,
            completionBehavior: completionBehavior,
            prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
            mfaTitle: mfaTitle
        )
    }
}

private extension UIViewController {
    func _authorizeProtectedAction<HeaderView: View, Result: MfaProtectedActionResult>(
        account: MAccount,
        title: String,
        headerView: HeaderView,
        passwordAction: @escaping (String) async throws -> Result,
        ledgerSignData: (() async throws -> SignData)? = nil,
        ledgerFromAddress: String? = nil,
        presentationStyle: ProtectedActionPresentationStyle = .push,
        useBioOnPresent: Bool = true,
        completionBehavior: ProtectedActionCompletionBehavior = .popAuth,
        prefersNavigationTitleWithCustomHeader: Bool = false,
        mfaTitle: String? = nil
    ) async throws -> Result? {
        if account.isHardware {
            guard let ledgerSignData else {
                throw DisplayError(text: lang("Transaction to this smart contract is not yet supported by Ledger."))
            }
            let signData = try await ledgerSignData()
            let fromAddress = ledgerFromAddress ?? account.firstAddress
            guard !fromAddress.isEmpty else {
                throw SdkError.unexpected(message: "No account address")
            }
            try await _authorizeLedger(
                title: title,
                headerView: headerView,
                accountId: account.id,
                fromAddress: fromAddress,
                ledgerSignData: signData,
                presentationStyle: presentationStyle,
                completionBehavior: completionBehavior
            )
            return nil
        }

        switch presentationStyle {
        case .push:
            return try await _pushPasswordProtected(
                title: title,
                headerView: headerView,
                account: account,
                passwordAction: passwordAction,
                useBioOnPresent: useBioOnPresent,
                completionBehavior: completionBehavior,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                mfaTitle: mfaTitle ?? title
            )
        case .sheet:
            return try await _presentPasswordProtected(
                title: title,
                headerView: headerView,
                account: account,
                passwordAction: passwordAction,
                useBioOnPresent: useBioOnPresent,
                completionBehavior: completionBehavior,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                mfaTitle: mfaTitle ?? title
            )
        }
    }

    private func runPasswordAction<Result: MfaProtectedActionResult>(
        account: MAccount,
        passwordAction: @escaping (String) async throws -> Result,
        password: String
    ) async throws -> Result {
        do {
            try await AccountStore.refreshStoredMfa(accountId: account.id, password: password)
        } catch {
            passwordOrLedgerLog.error("Failed to refresh MFA state before protected action: \(error, .public)")
        }

        let result: Result
        do {
            result = try await passwordAction(password)
        } catch {
            passwordOrLedgerLog.error("Protected action failed before MFA confirmation: \(error, .public)")
            throw error
        }
        if let error = result.protectedActionError {
            let bridgeError = SdkError.apiReturnedError(error: error, context: result)
            passwordOrLedgerLog.error("Protected action returned MFA error: \(bridgeError, .public)")
            throw bridgeError
        }
        return result
    }

    private func biometricPasscodeIfAvailable(useBioOnPresent: Bool) async -> String? {
        guard useBioOnPresent,
              AppStorageHelper.isBiometricActivated(),
              BiometricHelper.biometryType != nil
        else {
            return nil
        }

        guard case .success = await BiometricHelper.authenticate() else {
            return nil
        }

        let passcode = KeychainHelper.biometricPasscode()
        do {
            return try await AuthSupport.verifyPassword(password: passcode) ? passcode : nil
        } catch {
            return nil
        }
    }

    private func _presentPasswordProtected<HeaderView: View, Result: MfaProtectedActionResult>(
        title: String,
        headerView: HeaderView,
        account: MAccount,
        passwordAction: @escaping (String) async throws -> Result,
        useBioOnPresent: Bool,
        completionBehavior: ProtectedActionCompletionBehavior,
        prefersNavigationTitleWithCustomHeader: Bool,
        mfaTitle: String
    ) async throws -> Result {
        if let passcode = await biometricPasscodeIfAvailable(useBioOnPresent: useBioOnPresent) {
            let result = try await runPasswordAction(account: account, passwordAction: passwordAction, password: passcode)
            if let hash = result.mfaRequestHash {
                return try await presentMfaConfirmation(
                    account: account,
                    requestHash: hash,
                    title: mfaTitle,
                    result: result,
                    completionBehavior: completionBehavior
                )
            }
            return result
        }

        let vc = self
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, any Error>) in
            var _error: (any Error)?
            var _result: Result?
            var didResume = false
            weak var sheetNavigationController: UINavigationController?

            func resumeOnce(_ body: @escaping () -> Void) {
                guard !didResume else { return }
                didResume = true
                body()
            }

            let unlockVC = UnlockVC(
                title: title,
                replacedTitle: nil,
                subtitle: nil,
                customHeaderVC: headerVC,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                animatedPresentation: false,
                dissmissWhenAuthorized: false,
                shouldBeThemedLikeHeader: false,
                onAuthTask: { password, onTaskDone in
                    Task {
                        do {
                            _result = try await vc.runPasswordAction(
                                account: account,
                                passwordAction: passwordAction,
                                password: password
                            )
                        } catch {
                            _error = error
                        }
                        onTaskDone()
                    }
                },
                onDone: { [weak vc] _ in
                    if let _error {
                        sheetNavigationController?.dismiss(animated: true) {
                            resumeOnce {
                                continuation.resume(throwing: _error)
                            }
                        }
                    } else if let _result, let hash = _result.mfaRequestHash, let sheetNavigationController {
                        vc?.showMfaConfirmationInSheet(
                            navigationController: sheetNavigationController,
                            account: account,
                            requestHash: hash,
                            title: mfaTitle,
                            continuation: continuation,
                            result: _result,
                            completionBehavior: completionBehavior
                        )
                    } else if let _result {
                        if completionBehavior == .popAuth {
                            sheetNavigationController?.dismiss(animated: true) {
                                resumeOnce {
                                    continuation.resume(returning: _result)
                                }
                            }
                        } else {
                            resumeOnce {
                                continuation.resume(returning: _result)
                            }
                        }
                    } else {
                        sheetNavigationController?.dismiss(animated: true) {
                            resumeOnce {
                                continuation.resume(throwing: CancellationError())
                            }
                        }
                    }
                },
                cancellable: true,
                onCancel: {
                    sheetNavigationController?.dismiss(animated: true) {
                        resumeOnce {
                            continuation.resume(throwing: CancellationError())
                        }
                    }
                },
                useBioOnPresent: false
            )
            let navigationController = WNavigationController(rootViewController: unlockVC)
            navigationController.navigationBar.tintColor = AirTintColor
            sheetNavigationController = navigationController
            vc.present(navigationController, animated: true)
        }
    }

    private func _pushPasswordProtected<HeaderView: View, Result: MfaProtectedActionResult>(
        title: String,
        headerView: HeaderView,
        account: MAccount,
        passwordAction: @escaping (String) async throws -> Result,
        useBioOnPresent: Bool,
        completionBehavior: ProtectedActionCompletionBehavior,
        prefersNavigationTitleWithCustomHeader: Bool,
        mfaTitle: String
    ) async throws -> Result {
        guard navigationController != nil else {
            throw SdkError.unexpected(message: "No navigation controller")
        }
        let vc = self
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, any Error>) in
            var _error: (any Error)?
            var _result: Result?
            UnlockVC.pushAuth(
                on: vc,
                title: title,
                customHeaderVC: headerVC,
                useBioOnPresent: useBioOnPresent,
                prefersNavigationTitleWithCustomHeader: prefersNavigationTitleWithCustomHeader,
                onAuthTask: { password, onTaskDone in
                    Task {
                        do {
                            _result = try await vc.runPasswordAction(
                                account: account,
                                passwordAction: passwordAction,
                                password: password
                            )
                        } catch {
                            _error = error
                        }
                        onTaskDone()
                    }
                },
                onDone: { [weak vc] _ in
                    if let _error {
                        vc?.popPushedUnlockIfStillOnTop()
                        continuation.resume(throwing: _error)
                    } else if let _result, let hash = _result.mfaRequestHash {
                        vc?.pushMfaConfirmation(
                            account: account,
                            requestHash: hash,
                            title: mfaTitle,
                            continuation: continuation,
                            result: _result,
                            completionBehavior: completionBehavior
                        )
                    } else if let _result {
                        if completionBehavior == .popAuth {
                            vc?.popPushedUnlockIfStillOnTop()
                        }
                        continuation.resume(returning: _result)
                    } else {
                        vc?.popPushedUnlockIfStillOnTop()
                        continuation.resume(throwing: CancellationError())
                    }
                }
            )
        }
    }

    private func popPushedUnlockIfStillOnTop() {
        guard navigationController?.topViewController is UnlockVC else { return }
        navigationController?.popViewController(animated: true)
    }

    private func removePushedUnlock(_ unlockVC: UnlockVC?, from navigationController: UINavigationController) {
        guard let unlockVC else { return }
        var viewControllers = navigationController.viewControllers
        guard let index = viewControllers.firstIndex(where: { $0 === unlockVC }) else { return }
        viewControllers.remove(at: index)
        navigationController.setViewControllers(viewControllers, animated: false)
    }

    private func _authorizeLedger<HeaderView: View>(
        title: String,
        headerView: HeaderView,
        accountId: String,
        fromAddress: String,
        ledgerSignData: SignData,
        presentationStyle: ProtectedActionPresentationStyle,
        completionBehavior: ProtectedActionCompletionBehavior,
    ) async throws {
        let signModel = await LedgerSignModel(
            accountId: accountId,
            fromAddress: fromAddress,
            signData: ledgerSignData
        )
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let vc = LedgerSignVC(
                model: signModel,
                title: title,
                headerView: headerView
            )
            vc.onDone = { [weak vc] _ in
                if completionBehavior == .popAuth {
                    if let navigationController = vc?.navigationController {
                        if navigationController.topViewController === vc {
                            if vc?.canGoBack == true {
                                navigationController.popViewController(animated: true)
                            } else {
                                vc?.dismiss(animated: true)
                            }
                        }
                    } else {
                        vc?.dismiss(animated: true)
                    }
                }
                continuation.resume()
            }
            vc.onCancel = { [weak vc] _ in
                if let navigationController = vc?.navigationController {
                    if navigationController.topViewController === vc {
                        if vc?.canGoBack == true {
                            navigationController.popViewController(animated: true)
                        } else {
                            vc?.dismiss(animated: true)
                        }
                    }
                } else {
                    vc?.dismiss(animated: true)
                }
                continuation.resume(throwing: CancellationError())
            }
            if presentationStyle == .push, let navigationController = navigationController {
                navigationController.pushViewController(vc, animated: true)
            } else {
                present(WNavigationController(rootViewController: vc), animated: true)
            }
        }
    }

    private func pushMfaConfirmation<Result: MfaProtectedActionResult>(
        account: MAccount,
        requestHash: String,
        title: String,
        continuation: CheckedContinuation<Result, any Error>,
        result: Result,
        completionBehavior: ProtectedActionCompletionBehavior
    ) {
        guard let navigationController else {
            continuation.resume(throwing: CancellationError())
            return
        }
        let mfaVC = MfaConfirmationVC(account: account, requestHash: requestHash, title: title)
        var didResume = false
        func resumeOnce(_ body: () -> Void) {
            guard !didResume else { return }
            didResume = true
            body()
        }
        mfaVC.onDone = { [weak self, weak mfaVC] request in
            do {
                try await result.handleMfaConfirmation(accountId: account.id, request: request)
                if completionBehavior == .popAuth {
                    mfaVC?.navigationController?.popViewController(animated: true)
                }
                resumeOnce {
                    continuation.resume(returning: result)
                }
            } catch {
                passwordOrLedgerLog.error("MFA confirmation completion failed: \(error, .public)")
                if completionBehavior == .popAuth {
                    mfaVC?.navigationController?.popViewController(animated: true)
                }
                resumeOnce {
                    continuation.resume(throwing: error)
                }
            }
            self?.view.endEditing(true)
        }
        mfaVC.onCancel = { [weak mfaVC] in
            mfaVC?.navigationController?.popViewController(animated: true)
            resumeOnce {
                continuation.resume(throwing: CancellationError())
            }
        }
        navigationController.pushViewController(mfaVC, animated: true)
        let unlockVC = navigationController.viewControllers.dropLast().last as? UnlockVC
        if let transitionCoordinator = navigationController.transitionCoordinator {
            transitionCoordinator.animate(alongsideTransition: nil) { [weak self, weak navigationController] context in
                guard !context.isCancelled, let navigationController else { return }
                self?.removePushedUnlock(unlockVC, from: navigationController)
            }
        } else {
            removePushedUnlock(unlockVC, from: navigationController)
        }
    }

    private func presentMfaConfirmation<Result: MfaProtectedActionResult>(
        account: MAccount,
        requestHash: String,
        title: String,
        result: Result,
        completionBehavior: ProtectedActionCompletionBehavior
    ) async throws -> Result {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, any Error>) in
            let mfaVC = MfaConfirmationVC(account: account, requestHash: requestHash, title: title)
            let navigationController = WNavigationController(rootViewController: mfaVC)
            navigationController.isModalInPresentation = true
            configureMfaConfirmation(
                mfaVC,
                accountId: account.id,
                continuation: continuation,
                result: result,
                completionBehavior: completionBehavior,
                dismiss: { [weak navigationController] in
                    navigationController?.dismiss(animated: true)
                }
            )
            present(navigationController, animated: true)
        }
    }

    private func showMfaConfirmationInSheet<Result: MfaProtectedActionResult>(
        navigationController: UINavigationController,
        account: MAccount,
        requestHash: String,
        title: String,
        continuation: CheckedContinuation<Result, any Error>,
        result: Result,
        completionBehavior: ProtectedActionCompletionBehavior
    ) {
        let mfaVC = MfaConfirmationVC(account: account, requestHash: requestHash, title: title)
        navigationController.isModalInPresentation = true
        configureMfaConfirmation(
            mfaVC,
            accountId: account.id,
            continuation: continuation,
            result: result,
            completionBehavior: completionBehavior,
            dismiss: { [weak navigationController] in
                navigationController?.dismiss(animated: true)
            }
        )
        navigationController.setViewControllers([mfaVC], animated: false)
    }

    private func configureMfaConfirmation<Result: MfaProtectedActionResult>(
        _ mfaVC: MfaConfirmationVC,
        accountId: String,
        continuation: CheckedContinuation<Result, any Error>,
        result: Result,
        completionBehavior: ProtectedActionCompletionBehavior,
        dismiss: @escaping () -> Void
    ) {
        var didResume = false
        func resumeOnce(_ body: () -> Void) {
            guard !didResume else { return }
            didResume = true
            body()
        }
        mfaVC.onDone = { [weak self] request in
            do {
                try await result.handleMfaConfirmation(accountId: accountId, request: request)
                if completionBehavior == .popAuth {
                    dismiss()
                }
                resumeOnce {
                    continuation.resume(returning: result)
                }
            } catch {
                passwordOrLedgerLog.error("MFA confirmation completion failed: \(error, .public)")
                if completionBehavior == .popAuth {
                    dismiss()
                }
                resumeOnce {
                    continuation.resume(throwing: error)
                }
            }
            self?.view.endEditing(true)
        }
        mfaVC.onCancel = {
            dismiss()
            resumeOnce {
                continuation.resume(throwing: CancellationError())
            }
        }
    }
}
