//
//  HomeVM.swift
//  WalletContext
//
//  Created by Sina on 3/20/24.
//

import Foundation
import UIKit
import WalletContext
import WalletCore
import UIComponents
import SwiftNavigation
import UIEarn
import Perception

private let log = Log("HomeVM")

@MainActor protocol HomeVMDelegate: AnyObject {
    func update(state: UpdateStatusView.State, animated: Bool)
    func changeAccountTo(accountId: String, isNew: Bool) async
    func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool)
    func tokensChanged()
    func removeSelfFromStack()
}

@Perceptible
@MainActor final class HomeViewModel: WalletCoreData.EventsObserver {
    
    @PerceptionIgnored
    weak var delegate: HomeVMDelegate? {
        didSet { delegate?.update(state: updateStatusModel.state, animated: false) }
    }

    @PerceptionIgnored private let updateStatusModel = WalletUpdateStatusModel.shared
    @PerceptionIgnored private var updateStatusObservation: ObserveToken?

    @PerceptionIgnored
    @AccountContext var account: MAccount

    var isTrackingActiveAccount: Bool { $account.source == .current }
    
    init(accountSource: AccountSource) {
        self._account = AccountContext(source: accountSource)
        
        if !isTrackingActiveAccount {
            _account.onAccountDeleted = { [weak self] in
                guard let self else { return }
                self.delegate?.removeSelfFromStack()
            }
        }
        
        WalletCoreData.add(eventObserver: self)

        var previousState = updateStatusModel.state
        updateStatusObservation = observe { [weak self] in
            guard let self else { return }
            let state = updateStatusModel.state
            HomeTrace.record("homeVM.status", "old=\(previousState) new=\(state) same=\(previousState == state)")
            delegate?.update(state: state, animated: true)
            if previousState == .waitingForNetwork, state != .waitingForNetwork {
                refreshTransactions()
            }
            previousState = state
        }
    }

    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged(let accountId):
            if accountId == self.account.id {
                dataUpdated(reason: "balanceChanged")
            }
            break
        case .tokensChanged, .swapTokensChanged:
            dataUpdated(reason: HomeTrace.isEnabled ? event.homeTraceDescription ?? "tokens" : "")
            break
        case .baseCurrencyChanged:
            baseCurrencyChanged()
        case .accountChanged(_, let isNew):
            accountChanged(isNew: isNew)
            break
        case .accountNameChanged:
            dataUpdated(reason: "accountNameChanged")
            break
        case .assetsAndActivityDataUpdated:
            dataUpdated(reason: "assetsAndActivityDataUpdated")
        default:
            break
        }
    }

    // MARK: - Wallet Public Variables
    
    // while balances are not loaded, do not show anything!
    var balancesLoaded: Bool {
        !$account.balances.isEmpty
    }
    
    // MARK: - Init wallet info
    func initWalletInfo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            EarnVM.sharedTon.preload()
//            EarnVM.sharedMycoin.preload()
        }
    }
    
    // called on pull to refresh / selected slug change / after network reconnection / when retrying failed tries
    func refreshTransactions(slugChanged: Bool = false) {
        // init requests
        initWalletInfo()
    }

    func dataUpdated(transactions: Bool = true, reason: String = #function) {
        let cause = HomeTrace.cause
        HomeTrace.record("homeVM.tokens.queue", "account=\(account.id) reason=\(reason)")
        DispatchQueue.main.async { [self] in
            // make sure balances are loaded
            if !balancesLoaded {
                HomeTrace.$cause.withValue(cause) {
                    HomeTrace.record("homeVM.tokens.skip", "account=\(account.id) reason=balances-not-loaded")
                }
                log.info("Balances not loaded yet")
                return
            }
            DispatchQueue.main.async {
                HomeTrace.$cause.withValue(cause) {
                    HomeTrace.record("homeVM.tokens.deliver", "account=\(self.account.id) reason=\(reason)")
                    self.delegate?.tokensChanged()
                }
            }
        }
    }
    
    @MainActor func baseCurrencyChanged() {
        HomeTrace.record("homeVM.baseCurrency", "account=\(account.id)")
        // reload tableview to make it clear as the tokens are not up to date
        delegate?.tokensChanged()
    }

    @MainActor fileprivate func accountChanged(isNew: Bool) {
        guard isTrackingActiveAccount else { return }
        // reset load states, active network requests will also be ignored automatically
        delegate?.update(state: updateStatusModel.state, animated: true)

        Task {
            await delegate?.changeAccountTo(accountId: account.id, isNew: isNew)
        }
        // get all data again
        initWalletInfo()
    }
}
