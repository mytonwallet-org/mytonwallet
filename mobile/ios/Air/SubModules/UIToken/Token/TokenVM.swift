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

private let PRICE_HISTORY_REFRESH_INTERVAL: Duration = .seconds(15)

enum TokenHistoryLoadingState: Equatable {
    case loading
    case loaded
    case failed
}

@MainActor protocol TokenVMDelegate: AnyObject {
    func dataUpdated()
    func priceDataUpdated()
    func tokenDetailsUpdated()
    func accountChanged()
}

@MainActor final class TokenVM: Sendable {

    let reachability = Reachability()
    var waitingForNetwork: Bool? = nil
    
    isolated deinit {
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
    
    private(set) var historyData: [[Double]]?
    private(set) var isHistoryRestored = true
    private(set) var backfill: ApiPriceHistoryBackfill?
    private(set) var historyLoadingState: TokenHistoryLoadingState = .loading
    private let fetchPriceHistory: @MainActor (ApiToken, ApiPriceHistoryPeriod, MBaseCurrency) async throws -> ApiPriceHistory
    private var loadHistoryTask: Task<Void, Never>?
    private var loadTokenDetailsTask: Task<Void, Never>?
    private var lastRequestedTokenInfoPreset: DebugTokenInfoMock.Preset?
    private(set) var tokenInfoState: TokenInfoState
    
    init(accountId: String, selectedToken: ApiToken, tokenVMDelegate: TokenVMDelegate,
         fetchPriceHistory: @escaping @MainActor (ApiToken, ApiPriceHistoryPeriod, MBaseCurrency) async throws -> ApiPriceHistory = Api.fetchPriceHistory) {
        self.accountId = accountId
        self.selectedToken = selectedToken
        self.tokenVMDelegate = tokenVMDelegate
        self.fetchPriceHistory = fetchPriceHistory
        if DebugTokenInfoMock.preset == .disabled,
           let cached = TokenStore.cachedTokenDetails(tokenSlug: selectedToken.slug) {
            self.tokenInfoState = Self.tokenInfoState(details: cached.details)
        } else {
            self.tokenInfoState = .loading
        }
        
        let cachedHistory = TokenStore.cachedPriceHistory(tokenSlug: selectedToken.slug, period: selectedPeriod)
        self.historyData = cachedHistory?.points
        self.backfill = cachedHistory?.backfill
        WalletCoreData.add(eventObserver: self)
        
        // Listen for network connection events
        reachability.whenReachable = { [weak self] _ in
            guard let self else {return}
            if waitingForNetwork == true {
                waitingForNetwork = false
                refreshTransactions()
            } else {
                waitingForNetwork = false
            }
        }
        reachability.whenUnreachable = { [weak self] _ in
            self?.waitingForNetwork = true
        }
        reachability.startNotifier()
    }
    
    func stopAllObservers() {
        loadTokenDetailsTask?.cancel()
        loadHistoryTask?.cancel()
    }
    
    internal func refreshTransactions() {
        if selectedToken.type != .lp_token {
            loadPriceHistory(period: selectedPeriod)
        }
        refreshTokenDetails()
    }

    func refreshTokenDetails() {
        loadTokenDetailsTask?.cancel()
        let preset = DebugTokenInfoMock.preset
        let presetDidChange = preset != lastRequestedTokenInfoPreset
        lastRequestedTokenInfoPreset = preset

        // Config updates can arrive periodically. Keep the current presentation and expansion
        // state while refreshing the same source; only a genuinely new preset starts loading.
        if presetDidChange {
            if preset == .disabled,
               let cached = TokenStore.cachedTokenDetails(tokenSlug: selectedToken.slug) {
                setTokenInfoState(Self.tokenInfoState(details: cached.details))
            } else {
                setTokenInfoState(.loading)
            }
        }
        let slug = selectedToken.slug
        let asset = selectedToken.swapIdentifier
        let accountId = accountId
        let selectedToken = selectedToken
        loadTokenDetailsTask = Task { [weak self] in
            do {
                let details: ApiTokenDetails?
                if preset == .disabled {
                    details = try await TokenStore.refreshTokenDetails(
                        accountId: accountId,
                        token: selectedToken
                    )
                } else {
                    details = try await Api.fetchTokenDetails(asset: asset, slug: slug)
                }
                guard let self, !Task.isCancelled else { return }
                setTokenInfoState(Self.tokenInfoState(details: details))
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                if preset != .disabled || TokenStore.cachedTokenDetails(tokenSlug: slug) == nil {
                    setTokenInfoState(.error)
                }
            }
        }
    }

    private static func tokenInfoState(details: ApiTokenDetails?) -> TokenInfoState {
        .resolved(details: details)
    }

    private func setTokenInfoState(_ state: TokenInfoState) {
        guard tokenInfoState != state else { return }
        tokenInfoState = state
        tokenVMDelegate?.tokenDetailsUpdated()
    }
    
    func loadPriceHistory(period: ApiPriceHistoryPeriod, useCache: Bool = true) {
        loadHistoryTask?.cancel()
        let cachedHistory = useCache ? TokenStore.cachedPriceHistory(tokenSlug: selectedToken.slug, period: period) : nil
        historyData = cachedHistory?.points
        backfill = cachedHistory?.backfill
        isHistoryRestored = true
        historyLoadingState = .loading
        let slug = selectedToken.slug
        let token = selectedToken
        let currency = TokenStore.baseCurrency
        let fetchPriceHistory = fetchPriceHistory
        loadHistoryTask = Task { [weak self] in
            self?.tokenVMDelegate?.priceDataUpdated()
            while !Task.isCancelled {
                let previousLoadingState = self?.historyLoadingState
                if let self, historyLoadingState != .loading {
                    historyLoadingState = .loading
                    if historyData?.isEmpty != false {
                        tokenVMDelegate?.priceDataUpdated()
                    }
                }
                do {
                    let response = try await fetchPriceHistory(token, period, currency)
                    guard let self, !Task.isCancelled else { return }
                    let history = response.points
                    guard TokenStore.setPriceHistory(tokenSlug: slug, period: period, history: response, baseCurrency: currency) else { return }
                    let shouldUpdatePriceData = isHistoryRestored || historyData != history || backfill != response.backfill
                        || historyData?.isEmpty != false || previousLoadingState != .loaded
                    historyData = history
                    backfill = response.backfill
                    isHistoryRestored = false
                    historyLoadingState = .loaded
                    if shouldUpdatePriceData {
                        tokenVMDelegate?.priceDataUpdated()
                    }
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    historyLoadingState = .failed
                    tokenVMDelegate?.priceDataUpdated()
                }
                try? await Task.sleep(for: PRICE_HISTORY_REFRESH_INTERVAL)
            }
        }
    }
}

extension TokenVM: WalletCoreData.EventsObserver {
    @MainActor func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .rawBalancesChanged(let accountId):
            if accountId == self.accountId {
                tokenVMDelegate?.dataUpdated()
            }
        case .baseCurrencyChanged:
            loadPriceHistory(period: selectedPeriod, useCache: false)
            tokenVMDelegate?.dataUpdated()
        case .tokensChanged:
            tokenVMDelegate?.dataUpdated()
        case .accountChanged:
            tokenVMDelegate?.accountChanged()
        default:
            break
        }
    }
}
