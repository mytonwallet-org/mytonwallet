//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception
import Dependencies

@Perceptible
@MainActor final class ConnectViewModel {
        
    var update: ApiUpdate.DappConnect?
    var accountContext: AccountContext
    @PerceptionIgnored
    var onCancel: (() -> ())?
    @PerceptionIgnored
    weak var presenter: WViewController?
    var didConfirm: Bool = false
    var extraBottomPadding: CGFloat = 16

    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    
    init(accountId: String, update: ApiUpdate.DappConnect?, onCancel: (() -> ())?) {
        self.accountContext = AccountContext(accountId: accountId)
        self.update = update
        self.onCancel = onCancel
    }
    
    var isDisabled: Bool {
        if let update {
            guard isSelectedAccountCompatible else {
                return true
            }
            let requiresSigning = update.proof != nil || accountContext.account.getChainInfo(chain: .ton)?.mfa != nil
            return requiresSigning && accountContext.account.isView
        }
        return true
    }

    var disabledReason: String? {
        if !isSelectedAccountCompatible {
            return lang("No matching chains")
        }
        if isDisabled {
            return lang("Action is not possible on a view-only wallet.")
        }
        return nil
    }

    var requiredChains: [ApiDappSessionChain] {
        update?.dapp.chains ?? []
    }

    private var isSelectedAccountCompatible: Bool {
        guard !requiredChains.isEmpty else { return true }
        let account = accountContext.account
        return requiredChains.allSatisfy { chain in
            account.supports(chain: chain.chain)
        }
    }
    
    func onSelectWallet() {
        guard let update else { return }
        let vc = ChooseWalletVC(
            host: update.dapp.displayUrl,
            allowViewAccounts: update.proof == nil,
            requiredChains: requiredChains,
            onSelect: { [weak self] in self?.onWalletSelected(accountId: $0) }
        )
        let nc = WNavigationController(rootViewController: vc)
        presenter?.present(nc, animated: true)
    }
    
    func onWalletSelected(accountId: String) {
        Task {
            accountContext.accountId = accountId
            _ = try await AccountStore.activateAccount(accountId: accountId)
        }
    }
    
    func onConnectWallet() {
        guard
            let update,
            let presenter
        else { return }

        Task {
            do {
                let account = accountContext.account
                let requiresSigning = update.proof != nil || account.getChainInfo(chain: .ton)?.mfa != nil
                guard !(requiresSigning && account.isView) else {
                    return
                }
                let result = try await AppActions.authorizeProtectedAction(
                    on: presenter,
                    account: account,
                    title: lang("Confirm Connect"),
                    headerView: DappHeaderView(dapp: update.dapp, accountContext: accountContext),
                    passwordAction: { passcode in
                        return try await TonConnect.shared.submitConnect(
                            request: update,
                            accountId: account.id,
                            passcode: passcode
                        )
                    },
                    ledgerSignData: {
                        .signLedgerProof(
                            promiseId: update.promiseId,
                            proof: update.proof
                        )
                    },
                    ledgerFromAddress: account.getAddress(chain: .ton),
                    presentationStyle: .sheet,
                    mfaTitle: lang("Confirm Connect")
                )
                if let result {
                    try await TonConnect.shared.finishConnect(result)
                }
                didConfirm = true
                presenter.dismiss(animated: true)
            } catch is CancellationError {
            } catch {
                presenter.showAlert(error: error)
            }
        }
    }
}
