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
import Perception

public let HISTORY_LIMIT = 100
private let log = Log("EarnVM")
private let STAKING_HISTORY_RETRY_DELAY_WHEN_VISIBLE: TimeInterval = 2
private let STAKING_HISTORY_RETRY_DELAY_WHEN_HIDDEN: TimeInterval = 20
private let MAX_EMPTY_STAKING_HISTORY_RETRIES = 3
private let ACCOUNT_CHANGE_RESET_DELAY_WHEN_HIDDEN: Duration = .seconds(1)


@MainActor
protocol EarnMVDelegate: WViewController {
    func stakingStateUpdated()
    func newPageLoaded(animateChanges: Bool)
}


@MainActor
@Perceptible
public final class EarnVM: WalletCoreData.EventsObserver {
    
    public static let sharedTon = EarnVM(config: .ton, accountContext: AccountContext(source: .current))
    public static let sharedMycoin = EarnVM(config: .mycoin, accountContext: AccountContext(source: .current))
    public static let sharedEthena = EarnVM(config: .ethena, accountContext: AccountContext(source: .current))
    
    @PerceptionIgnored
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
    var stakingState: ApiStakingState? { config.stakingState(stakingData: $account.stakingData) }

    @PerceptionIgnored
    @AccountContext private var account: MAccount
    var accountContext: AccountContext { $account }

    @PerceptionIgnored
    private var currentAccountId: String = DUMMY_ACCOUNT.id
    @PerceptionIgnored
    private var isLoadingStakingHistoryPage: Int? = nil
    @PerceptionIgnored
    private var isLoadedAllHistoryItems = false
    @PerceptionIgnored
    private var lastLoadedPage = 0
    @PerceptionIgnored
    private var emptyStakingHistoryRetryCount = 0
    // set current last staking item timestamp to paginate
    @PerceptionIgnored
    var lastStakingItem: Int64? = nil
    @PerceptionIgnored
    var historyItems: [MStakingHistoryItem]? = nil
    @PerceptionIgnored
    private var shownListOnce: Bool = false
    @PerceptionIgnored
    private var isScreenVisible = false
    @PerceptionIgnored
    private var pendingAccountResetTask: Task<Void, Never>?
    @PerceptionIgnored
    private var pendingAccountId: String?

    // unstake
    @PerceptionIgnored
    private(set) var lastUnstakeActivityItem: (String, Int64)? = nil
    @PerceptionIgnored
    private var isLoadedAllUnstakeActivityItems = false
    @PerceptionIgnored
    private var isLoadingUnstakeActivities = false

    // stake
    @PerceptionIgnored
    private(set) var lastActivityItem: (String, Int64)? = nil
    @PerceptionIgnored
    private var isLoadedAllActivityItems = false
    @PerceptionIgnored
    private var isLoadingActivities = false

    init(config: StakingConfig, accountContext: AccountContext) {
        self.config = config
        self._account = accountContext
        self.currentAccountId = accountContext.accountId
        WalletCoreData.add(eventObserver: self)
    }
    
    public func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged(let accountId, _):
            guard $account.source == .current else { return }
            if accountId != self.currentAccountId {
                handleAccountChanged(to: accountId)
            }
        
        case .stakingAccountData(let data):
            if data.accountId == self.currentAccountId {
                delegate?.stakingStateUpdated()
            }
            
        case .newActivities(let newActivitiesEvent):
            if newActivitiesEvent.accountId == self.currentAccountId {
                Task {
                    await merger(newTransactions: newActivitiesEvent.activities)
                }
            }

        default:
            break
        }
    }
        
    public func preload() {
    }

    func setScreenVisible(_ isVisible: Bool) {
        let wasVisible = isScreenVisible
        isScreenVisible = isVisible
        if isVisible, !wasVisible {
            applyPendingAccountResetIfNeeded()
            delegate?.stakingStateUpdated()
            if historyItems != nil || allLoadedOnce {
                delegate?.newPageLoaded(animateChanges: false)
            }
        }
    }
        
    var allLoadedOnce: Bool {
        return lastLoadedPage > 0 &&
            (lastUnstakeActivityItem != nil || isLoadedAllUnstakeActivityItems) &&
            (lastActivityItem != nil || isLoadedAllActivityItems)
    }
    
    func loadInitialHistory() {
        fetchTokenActivities()
        fetchUnstakeTokenActivities()
        loadStakingHistory(page: 1)
    }

    private func handleAccountChanged(to accountId: String) {
        pendingAccountId = accountId
        pendingAccountResetTask?.cancel()

        if isScreenVisible {
            applyPendingAccountResetIfNeeded()
            return
        }

        pendingAccountResetTask = Task { [weak self] in
            do {
                try await Task.sleep(for: ACCOUNT_CHANGE_RESET_DELAY_WHEN_HIDDEN)
            } catch {
                return
            }
            await MainActor.run {
                self?.applyPendingAccountResetIfNeeded()
            }
        }
    }

    private func applyPendingAccountResetIfNeeded() {
        guard let pendingAccountId, pendingAccountId != currentAccountId else {
            self.pendingAccountId = nil
            pendingAccountResetTask = nil
            return
        }

        self.pendingAccountId = nil
        pendingAccountResetTask = nil
        resetStateForAccountChange(to: pendingAccountId)
    }

    private func resetStateForAccountChange(to accountId: String) {
        currentAccountId = accountId
        isLoadingStakingHistoryPage = nil
        isLoadedAllHistoryItems = false
        lastLoadedPage = 0
        emptyStakingHistoryRetryCount = 0
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
        if isScreenVisible {
            delegate?.newPageLoaded(animateChanges: false)
            delegate?.stakingStateUpdated()
        }
    }

    private func scheduleStakingHistoryRetry(page: Int, accountId: String) {
        let retryDelay = delegate != nil
            ? STAKING_HISTORY_RETRY_DELAY_WHEN_VISIBLE
            : STAKING_HISTORY_RETRY_DELAY_WHEN_HIDDEN

        DispatchQueue.main.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, self.currentAccountId == accountId else { return }
            self.loadStakingHistory(page: page)
        }
    }

    private func shouldRetryEmptyTonStakingHistory(
        accountId: String,
        page: Int,
        newHistoryItems: [MStakingHistoryItem]
    ) -> Bool {
        guard page == 1,
              tokenSlug == TONCOIN_SLUG,
              newHistoryItems.isEmpty,
              currentAccountId == accountId,
              emptyStakingHistoryRetryCount < MAX_EMPTY_STAKING_HISTORY_RETRIES,
              historyItems?.contains(where: { $0.type == .profit }) != true,
              ($account.stakingData?.totalProfit ?? 0) > 0 else {
            return false
        }

        return true
    }
    
    func loadStakingHistory(page: Int) {
        let accountId = currentAccountId
        guard isLoadingStakingHistoryPage == nil else {
            return
        }
        isLoadingStakingHistoryPage = page
        Task {
            do {
                //let offset = max(0, (page - 1) * HISTORY_LIMIT)
                let items = try await Api.getStakingHistory(accountId: accountId) //, limit: HISTORY_LIMIT, offset: offset)
                isLoadingStakingHistoryPage = nil
                let historyItems = items.map(MStakingHistoryItem.init(stakingHistory:))
                guard accountId == self.currentAccountId else {
                    return
                }

                if tokenSlug == TONCOIN_SLUG {
                    if historyItems.count > 0 {
                        emptyStakingHistoryRetryCount = 0
                        lastStakingItem = historyItems.last!.timestamp
                        isLoadedAllHistoryItems = true
                    } else if shouldRetryEmptyTonStakingHistory(
                        accountId: accountId,
                        page: page,
                        newHistoryItems: historyItems
                    ) {
                        emptyStakingHistoryRetryCount += 1
                        lastLoadedPage = page
                        isLoadedAllHistoryItems = false
                        log.info("retrying empty staking profit history accountId=\(accountId, .public) attempt=\(emptyStakingHistoryRetryCount)")
                        await merger(newHistoryItems: historyItems)
                        scheduleStakingHistoryRetry(page: page, accountId: accountId)
                        return
                    } else {
                        emptyStakingHistoryRetryCount = 0
                        isLoadedAllHistoryItems = true
                    }
                    lastLoadedPage = page
                    await merger(newHistoryItems: historyItems)
                    /*if !historyItems.isEmpty {
                        loadStakingHistory(page: page + 1)
                    }*/
                } else {
                    isLoadedAllHistoryItems = true
                    lastLoadedPage = page
                    await merger(newHistoryItems: [])
                }
            } catch {
                isLoadingStakingHistoryPage = nil
                guard accountId == self.currentAccountId else {
                    return
                }

                log.error("loadStakingHistory failed accountId=\(accountId, .public) page=\(page, .public) error=\(error, .public)")

                if page == 1 {
                    scheduleStakingHistoryRetry(page: 1, accountId: accountId)
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
                let result = try await Api.fetchPastActivities(
                    accountId: self.currentAccountId,
                    limit: 50,
                    tokenSlug: tokenSlug,
                    toTimestamp: toTimestamp
                )
                let newTransactions = result.activities
                isLoadingUnstakeActivities = false
                if newTransactions.count > 0 {
                    lastUnstakeActivityItem = (newTransactions.last!.id, newTransactions.last!.timestamp)
                }
                if !result.hasMore {
                    isLoadedAllUnstakeActivityItems = true
                }
                await merger(newTransactions: newTransactions)
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
                let result = try await Api.fetchPastActivities(
                    accountId: self.currentAccountId,
                    limit: 50,
                    tokenSlug: stakedTokenSlug,
                    toTimestamp: toTimestamp
                )
                let newTransactions = result.activities
                isLoadingActivities = false
                if newTransactions.count > 0 {
                    lastActivityItem = (newTransactions.last!.id, newTransactions.last!.timestamp)
                }
                if !result.hasMore {
                    isLoadedAllActivityItems = true
                }
                await merger(newTransactions: newTransactions)
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
    @concurrent func merger(newTransactions: [ApiActivity]) async {
        let oldHistoryItems = await self.historyItems ?? []
        var historyItems = oldHistoryItems
        for transaction in newTransactions {
            if let item = await MStakingHistoryItem(tokenSlug: tokenSlug, stakedTokenSlug: stakedTokenSlug, transaction: transaction) {
                if !historyItems.contains(item) {
                    historyItems.append(item)
                }
                if item.isLocal == false, let localIdx = historyItems.firstIndex(where: { $0.isLocal && $0.amount == item.amount && $0.type == item.type }) {
                    historyItems.remove(at: localIdx)
                }
            }
        }
        historyItems.sort(by: { $0.timestamp > $1.timestamp })
        await MainActor.run { [historyItems] in
            self.historyItems = historyItems

            if shownListOnce {
                self.delegate?.newPageLoaded(animateChanges: true)
            } else if allLoadedOnce, let delegate {
                shownListOnce = true
                delegate.newPageLoaded(animateChanges: false) // it's first time, should show all using reload data with no diff!
            }
        }
    }
    
    @concurrent func merger(newHistoryItems: [MStakingHistoryItem]) async {
        let oldHistoryItems = await self.historyItems ?? []
        var historyItems = oldHistoryItems
        for item in newHistoryItems {
            if !historyItems.contains(item) {
                historyItems.append(item)
            }
        }
        historyItems.sort(by: { $0.timestamp > $1.timestamp })
        await MainActor.run { [historyItems] in
            self.historyItems = historyItems
            
            if shownListOnce {
                self.delegate?.newPageLoaded(animateChanges: true)
            } else if allLoadedOnce, let delegate {
                shownListOnce = true
                delegate.newPageLoaded(animateChanges: false) // it's first time, should show all using reload data with no diff!
            }
        }
    }
}
