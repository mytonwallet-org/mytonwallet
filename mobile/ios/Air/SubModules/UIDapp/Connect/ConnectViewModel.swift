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
    var accountViewModel: AccountViewModel
    @PerceptionIgnored
    var onConfirm: ((_ accountId: String, _ password: String) -> ())?
    @PerceptionIgnored
    var onCancel: (() -> ())?
    var didConfirm: Bool = false

    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    
    init(accountId: String, update: ApiUpdate.DappConnect?, onConfirm: ((_ accountId: String, _ password: String) -> ())?, onCancel: (() -> ())?) {
        self.accountViewModel = AccountViewModel(accountId: accountId)
        self.update = update
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    var isDisabled: Bool {
        if let update {
            return update.proof != nil && accountViewModel.account.isView
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
            accountViewModel.accountId = accountId
            _ = try await AccountStore.activateAccount(accountId: accountId)
        }
    }
    
    func onConnectWallet() {
        if accountViewModel.account.isHardware {
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
            onConfirm?(accountViewModel.accountId, passcode)
            topVC.dismiss(animated: true)
        }, cancellable: true)
    }
    
    private func confirmLedger() async {
        guard
            let update
        else { return }
        
        let signModel = await LedgerSignModel(
            accountId: accountViewModel.accountId,
            fromAddress: accountViewModel.account.firstAddress,
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
            onConfirm?(accountViewModel.accountId, "")
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
