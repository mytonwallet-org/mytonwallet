//
//  EarnVM.swift
//  MyTonWallet
//
//  Created by Sina on 5/13/24.
//

import Foundation
import UIComponents
import WalletCore
import WalletContext

public let HISTORY_LIMIT = 100
private let log = Log("EarnVM")


@MainActor
protocol EarnMVDelegate: WViewController {
    func stakingStateUpdated()
    func newPageLoaded(animateChanges: Bool)
}


public final class EarnVM: ObservableObject, WalletCoreData.EventsObserver {
    
    public static let sharedTon = EarnVM(config: .ton)
    public static let sharedMycoin = EarnVM(config: .mycoin)
    public static let sharedEthena = EarnVM(config: .ethena)
    
    weak var delegate: EarnMVDelegate? = nil {
        didSet {
            shownListOnce = false
        }
    }
    
    public let config: StakingConfig
    var tokenSlug: String { config.baseTokenSlug }
    var stakedTokenSlug: String { config.stakedTokenSlug }
    var token: ApiToken { config.baseToken }
    var stakedToken: ApiToken { config.stakedToken }
    var stakingState: ApiStakingState? { config.stakingState }

    private var accountId: String? = nil
    private var isLoadingStakingHistoryPage: Int? = nil
    private var isLoadedAllHistoryItems = false
    private var lastLoadedPage = 0
    // set current last staking item timestamp to paginate
    var lastStakingItem: Int64? = nil
    var historyItems: [MStakingHistoryItem]? = nil
    private var shownListOnce: Bool = false

    // unstake
    private(set) var lastUnstakeActivityItem: (String, Int64)? = nil
    private var isLoadedAllUnstakeActivityItems = false
    private var isLoadingUnstakeActivities = false

    // stake
    private(set) var lastActivityItem: (String, Int64)? = nil
    private var isLoadedAllActivityItems = false
    private var isLoadingActivities = false

    private init(config: StakingConfig) {
        self.config = config
        self.accountId = AccountStore.accountId
        WalletCoreData.add(eventObserver: self)
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(let accountId, _):
            if accountId != self.accountId {
                self.accountId = accountId
                isLoadingStakingHistoryPage = nil
                isLoadedAllHistoryItems = false
                lastLoadedPage = 0
                lastStakingItem = nil
                historyItems = nil
                shownListOnce = false
                lastUnstakeActivityItem = nil
                isLoadedAllUnstakeActivityItems = false
                isLoadingUnstakeActivities = false
                lastActivityItem = nil
                isLoadedAllActivityItems = false
                isLoadingActivities = false
                
                loadInitialHistory()
                delegate?.newPageLoaded(animateChanges: false)
                delegate?.stakingStateUpdated()
            }
        
        case .stakingAccountData(let data):
            if data.accountId == self.accountId {
                delegate?.stakingStateUpdated()
            }
            
        case .newActivities(let newActivitiesEvent):
            if newActivitiesEvent.accountId == AccountStore.accountId {
                merger(newTransactions: newActivitiesEvent.activities)
            }

        default:
            break
        }
    }
        
    public func preload() {
    }
        
    var allLoadedOnce: Bool {
        return lastLoadedPage > 0 &&
            (lastUnstakeActivityItem != nil || isLoadedAllUnstakeActivityItems) &&
            (lastActivityItem != nil || isLoadedAllActivityItems)
    }
    
    func loadStakingData() {
        DispatchQueue.main.async {
            self.delegate?.stakingStateUpdated()
        }
    }
    
    func loadInitialHistory() {
        fetchTokenActivities()
        fetchUnstakeTokenActivities()
        loadStakingHistory(page: 1)
    }
    
    func loadStakingHistory(page: Int) {
        guard let accountId = AccountStore.accountId, isLoadingStakingHistoryPage == nil else {
            return
        }
        isLoadingStakingHistoryPage = page
        Task {
            do {
                //let offset = max(0, (page - 1) * HISTORY_LIMIT)
                let items = try await Api.getStakingHistory(accountId: accountId) //, limit: HISTORY_LIMIT, offset: offset)
                isLoadingStakingHistoryPage = nil
                let historyItems = items.map(MStakingHistoryItem.init(stakingHistory:))
                if tokenSlug == TONCOIN_SLUG {
                    if historyItems.count > 0 {
                        lastStakingItem = historyItems.last!.timestamp
                    }
                    //isLoadedAllHistoryItems = historyItems.isEmpty
                    isLoadedAllHistoryItems = true
                    lastLoadedPage = page
                    merger(newHistoryItems: historyItems)
                    /*if !historyItems.isEmpty {
                        loadStakingHistory(page: page + 1)
                    }*/
                } else {
                    isLoadedAllHistoryItems = true
                    lastLoadedPage = page
                    merger(newHistoryItems: [])
                }
            } catch {
                isLoadingStakingHistoryPage = nil
                if page == 1 {
                    loadStakingHistory(page: 1)
                }
            }
        }
    }
    
    func loadMoreStakingHistory() {
        if isLoadedAllHistoryItems {
            return
        }
        loadStakingHistory(page: lastLoadedPage + 1)
    }
    
    // MARK: - Unstaked activities
    
    func fetchUnstakeTokenActivities(toTimestamp: Int64? = nil) {
        if isLoadingUnstakeActivities {
            return
        }
        isLoadingUnstakeActivities = true
        Task {
            do {
                log.info("fetchActivitySlice \(tokenSlug)")
                let newTransactions = try await Api.fetchPastActivities(
                    accountId: AccountStore.accountId!,
                    limit: 50,
                    tokenSlug: tokenSlug,
                    toTimestamp: toTimestamp
                )
                DispatchQueue.main.async { [self] in
                    isLoadingUnstakeActivities = false
                    if newTransactions.count > 0 {
                        lastUnstakeActivityItem = (newTransactions.last!.id, newTransactions.last!.timestamp)
                    } else if newTransactions.count == 0 {
                        isLoadedAllUnstakeActivityItems = true
                    }
                    merger(newTransactions: newTransactions)
                }
            } catch {
                DispatchQueue.main.asyncAfter(deadline: .now() + (delegate != nil ? 2 : 20)) { [weak self] in
                    guard let self else {return}
                    fetchUnstakeTokenActivities(toTimestamp: toTimestamp)
                }
            }
        }
    }
    
    func loadMoreUnstakeActivityItems() {
        if isLoadedAllActivityItems {
            return
        }
        guard let lastActivityItem = lastActivityItem?.1 else {
            return
        }
        fetchUnstakeTokenActivities(toTimestamp: lastActivityItem)
    }
    
    // MARK: - STAKED token activities
    
    func fetchTokenActivities(toTimestamp: Int64? = nil) {
        if isLoadingActivities {
            return
        }
        isLoadingActivities = true
        Task {
            do {
                log.info("fetchActivitySlice \(tokenSlug)")
                let newTransactions = try await Api.fetchPastActivities(
                    accountId: AccountStore.accountId!,
                    limit: 50,
                    tokenSlug: stakedTokenSlug,
                    toTimestamp: toTimestamp
                )
                DispatchQueue.main.async { [self] in
                    isLoadingActivities = false
                    if newTransactions.count > 0 {
                        lastActivityItem = (newTransactions.last!.id, newTransactions.last!.timestamp)
                    } else if newTransactions.count == 0 {
                        isLoadedAllActivityItems = true
                    }
                    merger(newTransactions: newTransactions)
                }
            } catch {
                DispatchQueue.main.asyncAfter(deadline: .now() + (delegate != nil ? 2 : 20)) { [weak self] in
                    guard let self else {return}
                    fetchTokenActivities(toTimestamp: toTimestamp)
                }
            }
        }
    }
    
    func loadMoreActivityItems() {
        if isLoadedAllActivityItems {
            return
        }
        guard let lastActivityItem = lastActivityItem?.1 else {
            return
        }
        fetchTokenActivities(toTimestamp: lastActivityItem)
    }
    
    // MARK: - MERGERS to merge activity items and staking history items
    func merger(newTransactions: [ApiActivity]) {
        let oldHistoryItems = self.historyItems ?? []
        var historyItems = oldHistoryItems
        for transaction in newTransactions {
            if let item = MStakingHistoryItem(tokenSlug: tokenSlug, stakedTokenSlug: stakedTokenSlug, transaction: transaction) {
                if !historyItems.contains(item) {
                    historyItems.append(item)
                }
                if item.isLocal == false, let localIdx = historyItems.firstIndex(where: { $0.isLocal && $0.amount == item.amount && $0.type == item.type }) {
                    historyItems.remove(at: localIdx)
                }
            }
        }
        historyItems.sort(by: { $0.timestamp > $1.timestamp })
        self.historyItems = historyItems
        
        if shownListOnce {
            DispatchQueue.main.async {
                self.delegate?.newPageLoaded(animateChanges: true)
            }
        } else if allLoadedOnce, let delegate {
            shownListOnce = true
            DispatchQueue.main.async {
                delegate.newPageLoaded(animateChanges: false) // it's first time, should show all using reload data with no diff!
            }
        }
    }
    
    func merger(newHistoryItems: [MStakingHistoryItem]) {
        let oldHistoryItems = self.historyItems ?? []
        var historyItems = oldHistoryItems
        for item in newHistoryItems {
            if !historyItems.contains(item) {
                historyItems.append(item)
            }
        }
        historyItems.sort(by: { $0.timestamp > $1.timestamp })
        self.historyItems = historyItems

        if shownListOnce {
            DispatchQueue.main.async {
                self.delegate?.newPageLoaded(animateChanges: true)
            }
        } else if allLoadedOnce, let delegate {
            shownListOnce = true
            DispatchQueue.main.async {
                delegate.newPageLoaded(animateChanges: false) // it's first time, should show all using reload data with no diff!
            }
        }
    }
}
