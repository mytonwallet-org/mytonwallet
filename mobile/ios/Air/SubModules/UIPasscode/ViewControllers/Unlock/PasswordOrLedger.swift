//
//  PasswordOrLedger.swift
//  AirAsFramework
//
//  Created by nikstar on 22.07.2025.
//

import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import Ledger


extension WViewController {
    
    public func pushAuthUsingPasswordOrLedger<HeaderView: View>(
        title: String,
        headerView: HeaderView,
        passwordAction: @escaping (String) async throws -> (),
        ledgerSignData: SignData,
    ) async throws {
        let account = try AccountStore.account.orThrow("no active account")
        if account.isHardware {
            let fromAddress = account.firstAddress
            try await _pushLedger(
                title: title,
                headerView: headerView,
                accountId: account.id,
                fromAddress: fromAddress,
                ledgerSignData: ledgerSignData
            )
        } else {
            try await _pushPassword(
                title: title,
                headerView: headerView,
                passwordAction: passwordAction,
            )
        }
    }
    
    private func _pushPassword<HeaderView: View>(
        title: String,
        headerView: HeaderView,
        passwordAction: @escaping (String) async throws -> (),
    ) async throws {
        let vc = self
        let headerVC = UIHostingController(rootView: headerView)
        headerVC.view.backgroundColor = .clear
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            var _error: (any Error)?
            UnlockVC.pushAuth(
                on: vc,
                title: title,
                customHeaderVC: headerVC,
                onAuthTask: { password, onTaskDone in
                    Task {
                        do {
                            try await passwordAction(password)
                        } catch {
                            _error = error
                        }
                        onTaskDone()
                    }
                },
                onDone: { _ in
                    if let _error {
                        continuation.resume(throwing: _error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func _pushLedger<HeaderView: View>(
        title: String,
        headerView: HeaderView,
        accountId: String,
        fromAddress: String,
        ledgerSignData: SignData,
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
                if vc?.canGoBack == true {
                    vc?.navigationController?.popViewController(animated: true)
                } else {
                    vc?.dismiss(animated: true)
                }
                continuation.resume()
            }
            vc.onCancel = { [weak vc] _ in
                if vc?.canGoBack == true {
                    vc?.navigationController?.popViewController(animated: true)
                } else {
                    vc?.dismiss(animated: true)
                }
                continuation.resume(throwing: CancellationError())
            }
            if let navigationController = navigationController {
                navigationController.pushViewController(vc, animated: true)
            } else {
                present(WNavigationController(rootViewController: vc), animated: true)
            }
        }
    }
}
