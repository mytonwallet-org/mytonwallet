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
import WReachability
import UIEarn
import Perception
import Dependencies

private let log = Log("HomeVM")

private let UPDATING_DELAY = 2

@MainActor protocol HomeVMDelegate: AnyObject {
    func update(state: UpdateStatusView.State, animated: Bool)
    func changeAccountTo(accountId: String, isNew: Bool) async
    func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool)
    func tokensChanged()
    func scrollToTop(animated: Bool)
    func removeSelfFromStack()
}

@Perceptible
@MainActor final class HomeViewModel: WalletCoreData.EventsObserver {
    
    @PerceptionIgnored
    weak var delegate: HomeVMDelegate?
    
    @PerceptionIgnored
    let reachability = try! Reachability()
    @PerceptionIgnored
    var waitingForNetwork: Bool? = nil
    @PerceptionIgnored
    private var loadSwapAssetsTask: Task<Void, Never>?
    
    @PerceptionIgnored
    private var prevUpdatingState: UpdateStatusView.State? = nil
    @PerceptionIgnored
    private var setUpdatingAfterDelayTask: Task<Void, any Error>? = nil
    
    @PerceptionIgnored
    @Dependency(\.accountStore) private var accountStore
    
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

        // Listen for network connection events
        reachability.whenReachable = { [weak self] reachability in
            guard let self else {return}
            if waitingForNetwork == true {
                waitingForNetwork = false
                refreshTransactions()
            } else {
                waitingForNetwork = false
                updateStatus()
            }
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
            self?.updateStatus()
        }
        do {
            try reachability.startNotifier()
        } catch {
        }
    }
    
    deinit {
        reachability.stopNotifier()
    }
    
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged(let accountId, let isFirstUpdate):
            if accountId == self.account.id {
                dataUpdated()
                if isFirstUpdate {
                    delegate?.transactionsUpdated(accountChanged: false, isUpdateEvent: false)
                }
            }
            break
        case .tokensChanged, .swapTokensChanged:
            dataUpdated()
            break
        case .baseCurrencyChanged:
            baseCurrencyChanged()
        case .accountChanged(_, let isNew):
            accountChanged(isNew: isNew)
            break
        case .accountNameChanged:
            dataUpdated()
            break
        case .assetsAndActivityDataUpdated:
            dataUpdated()
        case .updatingStatusChanged:
            updateStatus()
        default:
            break
        }
    }

    @MainActor private func updateStatus() {
        guard waitingForNetwork == false else {
            delegate?.update(state: .waitingForNetwork, animated: true)
            prevUpdatingState = .waitingForNetwork
            return
        }
        if accountStore.updatingActivities || accountStore.updatingBalance {
            if prevUpdatingState == .waitingForNetwork || prevUpdatingState == nil {
                log.info("updateStatus - network connected - updating", fileOnly: true)
                self.prevUpdatingState = .updating
                self.delegate?.update(state: .updating, animated: true)
                setUpdatingAfterDelayTask?.cancel()
                return
            }
            if setUpdatingAfterDelayTask == nil || setUpdatingAfterDelayTask?.isCancelled == true {
                self.setUpdatingAfterDelayTask = Task { [self] in
                    try await Task.sleep(for: .seconds(UPDATING_DELAY))
                    if accountStore.updatingActivities || accountStore.updatingBalance {
                        self.prevUpdatingState = .updating
                        self.delegate?.update(state: .updating, animated: true)
                    } else {
                        self.prevUpdatingState = .updated
                        self.delegate?.update(state: .updated, animated: true)
                    }
                }
            }
        } else {
            setUpdatingAfterDelayTask?.cancel()
            delegate?.update(state: .updated, animated: true)
            prevUpdatingState = .updated
        }
    }
    
    // MARK: - Wallet Public Variables
    
    // while balances are not loaded, do not show anything!
    var balancesLoaded: Bool {
        !$account.balances.isEmpty
    }
    
    var isGeneralDataAvailable: Bool {
        TokenStore.swapAssets != nil &&
        TokenStore.tokens.count > 1 &&
        balancesLoaded &&
        ($account.balances[TONCOIN_SLUG] != nil || $account.balances[TRX_SLUG] != nil)
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

    func dataUpdated(transactions: Bool = true) {
        DispatchQueue.main.async { [self] in
            // make sure balances are loaded
            if !balancesLoaded {
                log.info("Balances not loaded yet")
                return
            }
            // make sure default event for receiving toncoin is also called
            if BalanceStore.balancesEventCalledOnce[account.id] == nil {
                log.info("balancesEventCalledOnce not loaded yet")
                return
            }
            // make sure assets are loaded
            if TokenStore.swapAssets == nil {
                log.info("swap assets are not loaded yet")
                DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: { [weak self] in
                    self?.loadSwapAssetsIfNeeded()
                })
            }
            DispatchQueue.main.async {
                self.delegate?.tokensChanged()
            }
        }
    }
    
    private func loadSwapAssetsIfNeeded() {
        if TokenStore.swapAssets == nil && self.loadSwapAssetsTask == nil {
            self.loadSwapAssetsTask = Task { [weak self] in
                do {
                    _ = try await TokenStore.updateSwapAssets()
                } catch {
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled {
                        self?.loadSwapAssetsTask = nil
                        self?.loadSwapAssetsIfNeeded()
                    }
                }
            }
        }
    }
    
    @MainActor func baseCurrencyChanged() {
        // reload tableview to make it clear as the tokens are not up to date
        delegate?.tokensChanged()
    }

    @MainActor fileprivate func accountChanged(isNew: Bool) {
        guard isTrackingActiveAccount else { return }
        // reset load states, active network requests will also be ignored automatically
        self.setUpdatingAfterDelayTask?.cancel()
        self.setUpdatingAfterDelayTask = nil
        delegate?.update(state: waitingForNetwork == true ? .waitingForNetwork : .updated, animated: true)
        
        Task {
            await delegate?.changeAccountTo(accountId: account.id, isNew: isNew)
        }
        // get all data again
        initWalletInfo()
        
        // feel free to fix this monstrosity
        self.delegate?.scrollToTop(animated: false)
        DispatchQueue.main.async {
            self.delegate?.scrollToTop(animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.delegate?.scrollToTop(animated: false)
        }
    }
}
