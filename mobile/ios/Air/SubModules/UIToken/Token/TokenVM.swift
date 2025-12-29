//
//  TokenVM.swift
//  UIToken
//
//  Created by Sina on 11/1/24.
//

import Foundation
import WalletCore
import WalletContext
import WReachability

@MainActor protocol TokenVMDelegate: AnyObject {
    func dataUpdated(isUpdateEvent: Bool)
    func priceDataUpdated()
    func stateChanged()
    func accountChanged()
}

class TokenVM: @unchecked Sendable {

    let reachability = try! Reachability()
    var waitingForNetwork: Bool? = nil
    
    deinit {
        stopAllObservers()
        reachability.stopNotifier()
    }

    // MARK: - Initializer
    private weak var tokenVMDelegate: TokenVMDelegate?
    private let accountId: String
    private let selectedToken: ApiToken
    var selectedPeriod = ApiPriceHistoryPeriod(rawValue: AppStorageHelper.selectedCurrentTokenPeriod()) ?? .day {
        didSet {
            AppStorageHelper.save(currentTokenPeriod: selectedPeriod.rawValue)
            loadPriceHistory(period: selectedPeriod)
        }
    }
    
    var historyData: [[Double]]? { allHistoryData.withLock { $0[selectedPeriod] ?? nil } }
    private var allHistoryData: UnfairLock<[ApiPriceHistoryPeriod: [[Double]]?]> = .init(initialState: [:])
    private var loadHistoryTask: UnfairLock<[ApiPriceHistoryPeriod: Task<Void, Never>]> = .init(initialState: [:])
    
    init(accountId: String, selectedToken: ApiToken, tokenVMDelegate: TokenVMDelegate) {
        self.accountId = accountId
        self.selectedToken = selectedToken
        self.tokenVMDelegate = tokenVMDelegate
        
        if let cached = TokenStore.historyData(tokenSlug: selectedToken.slug) {
            self.allHistoryData.withLock { $0 = cached.data }
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
            }
            DispatchQueue.main.async {
                self.tokenVMDelegate?.stateChanged()
            }
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
            DispatchQueue.main.async {
                self?.tokenVMDelegate?.stateChanged()
            }
        }
        do {
            try reachability.startNotifier()
        } catch {
        }
    }
    
    func stopAllObservers() {
        loadHistoryTask.withLock { tasks in
            for task in tasks.values {
                task.cancel()
            }
        }
    }
    
    internal func refreshTransactions() {
        loadPriceHistory(period: selectedPeriod)
    }
    
    func loadPriceHistory(period: ApiPriceHistoryPeriod) {
        if let task = loadHistoryTask.withLock({ $0[period] }), !task.isCancelled {
            Task { [weak self] in await self?.tokenVMDelegate?.priceDataUpdated() }
            return
        }
        let task = Task { [weak self] in
            _ = await self?._loadPriceHistory(period: period)
        }
        self.loadHistoryTask.withLock { $0[period] = task }
    }
    
    private func _loadPriceHistory(period: ApiPriceHistoryPeriod, retriesLeft: Int = 3) async {
        if allHistoryData.withLock({ $0[period] }) != nil && period == selectedPeriod {
            await tokenVMDelegate?.priceDataUpdated()
        }
        do {
            let historyData = try await Api.fetchPriceHistory(slug: selectedToken.slug, period: period, baseCurrency: TokenStore.baseCurrency)
            self.allHistoryData.withLock { $0[period] = historyData }
            let allHistoryData = self.allHistoryData.withLock { $0 }
            TokenStore.setHistoryData(tokenSlug: selectedToken.slug, data: allHistoryData)
            if period == selectedPeriod {
                await tokenVMDelegate?.priceDataUpdated()
            }
        } catch {
            if retriesLeft > 0 {
                try? await Task.sleep(for: .seconds(0.5))
                await _loadPriceHistory(period: period, retriesLeft: retriesLeft - 1)
                return
            } else if !Task.isCancelled {
                self.loadHistoryTask.withLock { $0[period] = nil }
                return
            }
        }
        try? await Task.sleep(for: .seconds(15))
        if !Task.isCancelled {
            await _loadPriceHistory(period: period, retriesLeft: retriesLeft)
        }
    }
}

extension TokenVM: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .balanceChanged, .tokensChanged, .baseCurrencyChanged, .hideTinyTransfersChanged:
            DispatchQueue.main.async {
                self.tokenVMDelegate?.dataUpdated(isUpdateEvent: false)
            }
        case .accountChanged:
            DispatchQueue.main.async {
                self.tokenVMDelegate?.accountChanged()
            }
        default:
            break
        }
    }
}
