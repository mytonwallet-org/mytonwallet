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

private let log = Log("HomeVM")

private let UPDATING_DELAY = 2

@MainActor protocol HomeVMDelegate: AnyObject {
    func update(state: UpdateStatusView.State, animated: Bool)
    func updateBalance(balance: Double?, balance24h: Double?, walletTokens: [MTokenBalance])
    func changeAccountTo(accountId: String, isNew: Bool) async
    func transactionsUpdated(accountChanged: Bool, isUpdateEvent: Bool)
    func tokensChanged()
    func forceReload()
    func scrollToTop(animated: Bool)
}

@MainActor class HomeVM {
    
    weak var homeVMDelegate: HomeVMDelegate?
    
    let reachability = try! Reachability()
    var waitingForNetwork: Bool? = nil
    private var loadSwapAssetsTask: Task<Void, Never>?
    
    private var prevUpdatingState: UpdateStatusView.State? = nil
    private var setUpdatingAfterDelayTask: Task<Void, Never>? = nil
    
    deinit {
        reachability.stopNotifier()
    }
    
    init(homeVMDelegate: HomeVMDelegate) {
        self.homeVMDelegate = homeVMDelegate
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

    @MainActor private func updateStatus() {
        guard waitingForNetwork == false else {
            homeVMDelegate?.update(state: .waitingForNetwork, animated: true)
            prevUpdatingState = .waitingForNetwork
            return
        }
        if AccountStore.updatingActivities || AccountStore.updatingBalance {
            if prevUpdatingState == .waitingForNetwork || prevUpdatingState == nil {
                log.info("updateStatus - network connected - updating", fileOnly: true)
                self.prevUpdatingState = .updating
                self.homeVMDelegate?.update(state: .updating, animated: true)
                setUpdatingAfterDelayTask?.cancel()
                return
            }
            if setUpdatingAfterDelayTask == nil || setUpdatingAfterDelayTask?.isCancelled == true {
                self.setUpdatingAfterDelayTask = Task { [self] in
                    do {
                        try await Task.sleep(for: .seconds(UPDATING_DELAY))
                        try Task.checkCancellation()
                        if AccountStore.updatingActivities || AccountStore.updatingBalance {
                            log.info("setUpdatingAfterDelayTask executing - \(UPDATING_DELAY)s passed", fileOnly: true)
                            self.prevUpdatingState = .updating
                            self.homeVMDelegate?.update(state: .updating, animated: true)
                        } else {
                            self.prevUpdatingState = .updated
                            self.homeVMDelegate?.update(state: .updated, animated: true)
                        }
                    } catch {
                        // canceled. no longer updating
                        log.info("setUpdatingAfterDelayTask is canceled", fileOnly: true)
                    }
                }
            }
        } else {
            log.info("updateStatus - updated", fileOnly: true)
            setUpdatingAfterDelayTask?.cancel()
            homeVMDelegate?.update(state: .updated, animated: true)
            prevUpdatingState = .updated
        }
    }
    
    // MARK: - Wallet Public Variables
    var account: MAccount? = nil
    
    // while balances are not loaded, do not show anything!
    var balancesLoaded: Bool {
        BalanceStore.currentAccountBalances.count > 0
    }
    
    var isGeneralDataAvailable: Bool {
        TokenStore.swapAssets != nil &&
        TokenStore.tokens.count > 1 &&
        balancesLoaded &&
        (BalanceStore.currentAccountBalances[TONCOIN_SLUG] != nil || BalanceStore.currentAccountBalances[TRX_SLUG] != nil)
    }
    
    // MARK: - Init wallet info
    func initWalletInfo() {
        // fetch all data
        let accountId = AccountStore.accountId!
        if let account = AccountStore.accountsById[accountId] {
            self.account = account
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else {return}
                initWalletInfo()
            }
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2) {
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
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let accountId = AccountStore.accountId else { return }
            // make sure balances are loaded
            if !balancesLoaded {
                log.info("Balances not loaded yet")
                return
            }
            // make sure default event for receiving toncoin is also called
            if BalanceStore.balancesEventCalledOnce[accountId] == nil {
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
            // update balance view
            let accountBalanceData = BalanceStore.currentAccountBalanceData
            let walletTokens = Array(accountBalanceData?.walletTokens ?? [])
            DispatchQueue.main.async { [weak self] in
                guard let self else {return}
                // reload balance
                homeVMDelegate?.updateBalance(balance: accountBalanceData?.totalBalance,
                                              balance24h: accountBalanceData?.totalBalanceYesterday,
                                              walletTokens: walletTokens)
                // reload transaction prices
                homeVMDelegate?.tokensChanged()
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
        homeVMDelegate?.tokensChanged()
        // make header empty like initialization view
        homeVMDelegate?.updateBalance(balance: nil,
                                      balance24h: nil,
                                      walletTokens: [])
    }

    @MainActor fileprivate func accountChanged(isNew: Bool) {
        // reset load states, active network requests will also be ignored automatically
        guard let account = AccountStore.account else { return }
        self.account = AccountStore.account
        self.setUpdatingAfterDelayTask?.cancel()
        self.setUpdatingAfterDelayTask = nil
        homeVMDelegate?.update(state: waitingForNetwork == true ? .waitingForNetwork : .updated, animated: false)
        
        let accountBalanceData = BalanceStore.currentAccountBalanceData
        if let walletTokens = BalanceStore.currentAccountBalanceData?.walletTokens, walletTokens.count > 0 {
            DispatchQueue.main.async { [self] in
                // reload transaction prices
                homeVMDelegate?.transactionsUpdated(accountChanged: true, isUpdateEvent: false)
                // reload balance
                homeVMDelegate?.updateBalance(balance: accountBalanceData?.totalBalance,
                                              balance24h: accountBalanceData?.totalBalanceYesterday,
                                              walletTokens: walletTokens)
            }
        } else {
            homeVMDelegate?.updateBalance(balance: nil, balance24h: nil, walletTokens: [])
        }
        Task {
            await homeVMDelegate?.changeAccountTo(accountId: account.id, isNew: isNew)
        }
        // get all data again
        initWalletInfo()
        
        // feel free to fix this monstrosity
        self.homeVMDelegate?.scrollToTop(animated: false)
        DispatchQueue.main.async {
            self.homeVMDelegate?.scrollToTop(animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            self.homeVMDelegate?.scrollToTop(animated: false)
        }
    }

}

extension HomeVM: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged(let isFirstUpdate):
            dataUpdated()
            if isFirstUpdate {
                homeVMDelegate?.transactionsUpdated(accountChanged: false, isUpdateEvent: false)
            }
            break
        case .tokensChanged, .swapTokensChanged:
            dataUpdated()
            homeVMDelegate?.forceReload()
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
            homeVMDelegate?.forceReload()
        case .updatingStatusChanged:
            updateStatus()
        default:
            break
        }
    }
}
