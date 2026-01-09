//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIPasscode
import UIComponents
import WalletCore
import WalletContext
import Ledger
import Perception
import Dependencies

@Perceptible
@MainActor final class ConnectViewModel {
        
    var update: ApiUpdate.DappConnect?
    var accountContext: AccountContext
    @PerceptionIgnored
    var onConfirm: ((_ accountId: String, _ password: String) -> ())?
    @PerceptionIgnored
    var onCancel: (() -> ())?
    var didConfirm: Bool = false

    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    
    init(accountId: String, update: ApiUpdate.DappConnect?, onConfirm: ((_ accountId: String, _ password: String) -> ())?, onCancel: (() -> ())?) {
        self.accountContext = AccountContext(accountId: accountId)
        self.update = update
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    var isDisabled: Bool {
        if let update {
            return update.proof != nil && accountContext.account.isView
        }
        return true
    }
    
    func onSelectWallet() {
        guard let update else { return }
        let vc = ChooseWalletVC(
            host: update.dapp.displayUrl,
            allowViewAccounts: update.proof == nil,
            onSelect: { [weak self] in self?.onWalletSelected(accountId: $0) }
        )
        let nc = WNavigationController(rootViewController: vc)
        topViewController()?.present(nc, animated: true)
    }
    
    func onWalletSelected(accountId: String) {
        Task {
            accountContext.accountId = accountId
            _ = try await AccountStore.activateAccount(accountId: accountId)
        }
    }
    
    func onConnectWallet() {
        if accountContext.account.isHardware {
            Task {
                await confirmLedger()
            }
        } else {
            confirmMnemonic()
        }
    }
    
    private func confirmMnemonic() {
        guard let update, let topVC = topViewController() else { return }
        UnlockVC.presentAuth(on: topVC,
                             title: lang("Confirm Connect"),
                             subtitle: URL(string: update.dapp.url)?.host, onDone: { [weak self] passcode in
            guard let self, let passcode else { return }
            didConfirm = true
            onConfirm?(accountContext.accountId, passcode)
            topVC.dismiss(animated: true)
        }, cancellable: true)
    }
    
    private func confirmLedger() async {
        guard
            let update
        else { return }
        
        let signModel = await LedgerSignModel(
            accountId: accountContext.accountId,
            fromAddress: accountContext.account.firstAddress,
            signData: .signLedgerProof(
                promiseId: update.promiseId,
                proof: update.proof
            )
        )
        let vc = LedgerSignVC(
            model: signModel,
            title: lang("Confirm Sending"),
            headerView: EmptyView()
        )
        vc.onDone = { [weak self] _ in
            guard let self else { return }
            self.didConfirm = true
            onConfirm?(accountContext.accountId, "")
            topViewController()?.dismiss(animated: true, completion: {
                topViewController()?.dismiss(animated: true)
            })
        }
        vc.onCancel = { _ in
            topViewController()?.dismiss(animated: true, completion: {
                topViewController()?.dismiss(animated: true)
            })
        }
        topViewController()?.present(vc, animated: true)
    }
}
