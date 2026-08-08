//
//  ConnectDappVC.swift
//  UIDapp
//
//  Created by Sina on 8/13/24.
//

import SwiftUI
import ProtectedAction
import UIKit
import UIComponents
import WalletCore
import WalletContext
import Perception

@Perceptible
@MainActor final class ConnectViewModel {
        
    var update: ApiUpdate.DappConnect?
    var accountContext: AccountContext
    @PerceptionIgnored
    var onCreateMultichainWalletAction: (() -> ())?
    @PerceptionIgnored
    weak var presenter: WViewController?
    var didConfirm: Bool = false
    var extraBottomPadding: CGFloat = 16

    @PerceptionIgnored
    private var resolver: ConnectRequestResolver?
    @PerceptionIgnored
    private var executionTask: Task<Void, Never>?
    @PerceptionIgnored
    private var didCancel = false

    init(
        accountId: String,
        update: ApiUpdate.DappConnect?,
        onCreateMultichainWallet: (() -> ())? = nil,
        resolver: ConnectRequestResolver? = nil
    ) {
        self.accountContext = AccountContext(accountId: accountId)
        self.update = update
        self.onCreateMultichainWalletAction = onCreateMultichainWallet
        self.resolver = resolver ?? update.map { ConnectRequestResolver(promiseId: $0.promiseId) }
    }

    var needsNewMultichainWallet: Bool {
        update?.multichainResolution == .needsNewWallet
    }

    var connectButtonTitle: String {
        if update != nil, !isSelectedAccountCompatible {
            return lang("Connect Wallet")
        }
        if update?.dapp.resolvedUrlTrustStatus == .dangerous {
            return lang("Connect Anyway")
        }
        return lang("Connect Wallet")
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

    var isCreateMultichainWalletDisabled: Bool {
        update == nil || onCreateMultichainWalletAction == nil
    }

    struct DisabledWarning {
        var header: String?
        var text: String
        var kind: WarningView.Kind
    }

    var disabledWarning: DisabledWarning? {
        if needsNewMultichainWallet {
            return nil
        }
        if update != nil, !isSelectedAccountCompatible {
            return DisabledWarning(
                header: lang("No matching chains"),
                text: lang("Select multichain wallet"),
                kind: .warning
            )
        }
        if isDisabled {
            return DisabledWarning(
                header: nil,
                text: lang("Action is not possible on a view-only wallet."),
                kind: .error
            )
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
            let presenter,
            let resolver,
            executionTask == nil,
            !didCancel
        else { return }

        let account = accountContext.account
        let requiresSigning = update.proof != nil || account.getChainInfo(chain: .ton)?.mfa != nil
        guard !(requiresSigning && account.isView) else {
            return
        }
        let protectedAction = ProtectedAction.connectDapp(
            account: account,
            accountContext: accountContext,
            update: update,
            resolver: resolver,
            onCommitted: { [weak self, weak presenter] in
                self?.didConfirm = true
                presenter?.dismiss(animated: true)
            }
        )
        executionTask = Task { @MainActor [weak self, weak presenter] in
            defer { self?.executionTask = nil }
            guard let presenter else { return }
            _ = await ProtectedActionExecutor.execute(protectedAction, on: presenter)
        }
    }

    func replaceRequest(
        _ request: ApiUpdate.DappConnect,
        onCreateMultichainWallet: @escaping () -> ()
    ) {
        accountContext.accountId = request.initialSelectedAccountId
        update = request
        onCreateMultichainWalletAction = onCreateMultichainWallet
        resolver = ConnectRequestResolver(promiseId: request.promiseId)
        didConfirm = false
        didCancel = false
    }

    func cancel() {
        cancel(reason: "Cancel")
    }

    @discardableResult
    private func cancel(reason: String) -> Bool {
        guard !didConfirm, !didCancel, let update, let resolver else { return false }
        guard resolver.cancel(reason: reason) else { return false }
        didCancel = true
        executionTask?.cancel()
        Api.recordTonConnectEvent(
            eventName: "wallet-connect-rejected",
            promiseId: update.promiseId
        )
        return true
    }

    func onCreateMultichainWallet() {
        guard
            let onCreateMultichainWalletAction,
            cancel(reason: lang("Canceled by the user"))
        else { return }
        presenter?.dismiss(animated: true) { [weak self] in
            guard self?.didCancel == true else { return }
            onCreateMultichainWalletAction()
        }
    }
}
