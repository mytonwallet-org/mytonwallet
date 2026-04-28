import Foundation
import Perception
import WalletCore
import WalletContext

@MainActor
@Perceptible
final class PortfolioVM: Sendable {
    @PerceptionIgnored
    @AccountContext private var account: MAccount

    let accountContext: AccountContext
    private(set) var response: ApiPortfolioHistoryResponse?
    private(set) var isLoading = false
    private(set) var isRefreshing = false
    private(set) var errorText: String?
    private(set) var chartDataToken = 0

    @PerceptionIgnored
    private var loadTask: Task<Void, Never>?
    @PerceptionIgnored
    private var historyRefreshTask: Task<Void, Never>?
    @PerceptionIgnored
    private var hasLoaded = false
    @PerceptionIgnored
    private var historyRefreshAttempts = 0
    private let localInsightChrome: PortfolioInsightCardChrome = .plainSecondaryBorder

    init(accountContext: AccountContext) {
        self.accountContext = accountContext
        self._account = accountContext
        WalletCoreData.add(eventObserver: self)
    }

    isolated deinit {
        loadTask?.cancel()
        historyRefreshTask?.cancel()
        WalletCoreData.remove(observer: self)
    }

    var localInsightCards: [PortfolioInsightCardModel] {
        var cards: [PortfolioInsightCardModel] = []

        if account.isMultichain {
            cards.append(makeChainSplitCard())
        }

        cards.append(makeAssetClassesCard())
        cards.append(makeStakedCard())

        return cards
    }

    func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        reload(resetHistoryRefreshAttempts: true)
    }

    func reload(resetHistoryRefreshAttempts: Bool) {
        loadTask?.cancel()
        historyRefreshTask?.cancel()

        if resetHistoryRefreshAttempts {
            historyRefreshAttempts = 0
        }

        let wallets = portfolioWallets
        guard !wallets.isEmpty else {
            response = nil
            isLoading = false
            isRefreshing = false
            errorText = lang("Unavailable")
            chartDataToken &+= 1
            return
        }

        beginLoading()

        loadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await Api.fetchPortfolioNetWorthHistory(
                    wallets: wallets,
                    baseCurrency: TokenStore.baseCurrency
                )
                guard !Task.isCancelled else { return }

                apply(response: response, resetHistoryRefreshAttempts: resetHistoryRefreshAttempts)
            } catch {
                guard !Task.isCancelled else { return }
                handleLoadError(error)
            }
        }
    }

    private var portfolioWallets: [String] {
        guard account.network == .mainnet else { return [] }

        return backendSupportedPortfolioChains
            .compactMap { chain in
                guard let address = account.getAddress(chain: chain)?.nilIfEmpty else {
                    return nil
                }
                return "\(chain.rawValue):\(address)"
            }
    }

    private var backendSupportedPortfolioChains: [ApiChain] {
        ApiChain.allCases.filter { chain in
            chain.isNetWorthSupported
                && account.supports(chain: chain)
                && account.getAddress(chain: chain)?.nilIfEmpty != nil
        }
    }

    private var localSupportedChains: [ApiChain] {
        ApiChain.allCases.filter { chain in
            account.supports(chain: chain)
                && account.getAddress(chain: chain)?.nilIfEmpty != nil
        }
    }

    private func makeChainSplitCard() -> PortfolioInsightCardModel {
        let segments = localSupportedChains
            .compactMap { chain -> PortfolioInsightSegment? in
                let value = max(0, ($account.balanceUsdByChain?[chain] ?? 0) * TokenStore.baseCurrencyRate)

                return PortfolioInsightSegment(
                    id: chain.rawValue,
                    title: chain.title,
                    value: value,
                    valueText: formatBaseValue(value),
                    colorHex: PortfolioPalette.chainColor(for: chain)
                )
            }
            .sorted { $0.value > $1.value }

        let visibleSegments = segments.filter { $0.value > 0 }

        return PortfolioInsightCardModel(
            id: .chainSplit,
            title: lang("By Chain"),
            segments: visibleSegments,
            emptyText: lang("No chain balances"),
            action: fundAction,
            chrome: localInsightChrome
        )
    }

    private func makeAssetClassesCard() -> PortfolioInsightCardModel {
        enum AssetClass: CaseIterable {
            case native
            case stablecoins
            case altcoins

            var id: String {
                switch self {
                case .native:
                    return "native"
                case .stablecoins:
                    return "stablecoins"
                case .altcoins:
                    return "altcoins"
                }
            }

            var title: String {
                switch self {
                case .native:
                    return lang("Native")
                case .stablecoins:
                    return lang("Stablecoins")
                case .altcoins:
                    return lang("Altcoins")
                }
            }

            var colorHex: String {
                switch self {
                case .native:
                    return PortfolioPalette.native
                case .stablecoins:
                    return PortfolioPalette.stable
                case .altcoins:
                    return PortfolioPalette.altcoins
                }
            }
        }

        var totals = Dictionary(uniqueKeysWithValues: AssetClass.allCases.map { ($0, Double.zero) })

        for tokenBalance in $account.walletTokens ?? [] {
            let value = max(0, tokenBalance.toBaseCurrency ?? 0)
            guard value > 0 else {
                continue
            }

            let assetClass: AssetClass
            if tokenBalance.token?.isNative == true {
                assetClass = .native
            } else if isStablecoin(tokenBalance.token) {
                assetClass = .stablecoins
            } else {
                assetClass = .altcoins
            }

            totals[assetClass, default: 0] += value
        }

        let segments = AssetClass.allCases.compactMap { assetClass -> PortfolioInsightSegment? in
            let value = totals[assetClass, default: 0]
            guard value > 0 else {
                return nil
            }

            return PortfolioInsightSegment(
                id: assetClass.id,
                title: assetClass.title,
                value: value,
                valueText: formatBaseValue(value),
                colorHex: assetClass.colorHex
            )
        }

        return PortfolioInsightCardModel(
            id: .assetClasses,
            title: lang("Asset Mix"),
            segments: segments,
            emptyText: lang("No asset balances"),
            action: swapAction,
            chrome: localInsightChrome
        )
    }

    private func makeStakedCard() -> PortfolioInsightCardModel {
        let stakedValue = ($account.walletStaked ?? [])
            .reduce(0) { partialResult, tokenBalance in
                partialResult + max(0, tokenBalance.toBaseCurrency ?? 0)
            }
        let unstakedValue = ($account.walletTokens ?? [])
            .reduce(0) { partialResult, tokenBalance in
                partialResult + max(0, tokenBalance.toBaseCurrency ?? 0)
            }

        let segments = [
            PortfolioInsightSegment(
                id: "staked",
                title: lang("Staked"),
                value: stakedValue,
                valueText: formatBaseValue(stakedValue),
                colorHex: PortfolioPalette.stable
            ),
            PortfolioInsightSegment(
                id: "unstaked",
                title: lang("Not staked"),
                value: unstakedValue,
                valueText: formatBaseValue(unstakedValue),
                colorHex: PortfolioPalette.native
            ),
        ]
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }

        return PortfolioInsightCardModel(
            id: .staked,
            title: lang("Staked"),
            segments: segments,
            emptyText: lang("No staked assets"),
            action: earnAction,
            chrome: localInsightChrome
        )
    }

    private var fundAction: PortfolioInsightCardModel.Action? {
        guard !account.isView else {
            return nil
        }

        return .init(kind: .fund, title: lang("Fund"))
    }

    private var swapAction: PortfolioInsightCardModel.Action? {
        guard account.supportsSwap else {
            return nil
        }

        return .init(kind: .swap, title: lang("Swap"))
    }

    private var earnAction: PortfolioInsightCardModel.Action? {
        guard account.supportsEarn else {
            return nil
        }

        return .init(kind: .earn, title: lang("Earn"))
    }

    private func formatBaseValue(_ value: Double) -> String {
        BaseCurrencyAmount.fromDouble(value, TokenStore.baseCurrency)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
    }

    private func isStablecoin(_ token: ApiToken?) -> Bool {
        guard let token else {
            return false
        }

        let symbol = token.symbol
            .uppercased()
            .replacingOccurrences(of: "₮", with: "T")

        if symbol.contains("USD") {
            return true
        }

        if let priceUsd = token.priceUsd,
           (0.95...1.05).contains(priceUsd)
        {
            return true
        }

        return false
    }

    private func beginLoading() {
        if response == nil {
            isLoading = true
            errorText = nil
        } else {
            isRefreshing = true
        }
    }

    private func apply(response: ApiPortfolioHistoryResponse, resetHistoryRefreshAttempts: Bool) {
        let normalizedResponse = response.normalizedForPortfolioDisplay()
        self.response = normalizedResponse
        isLoading = false
        isRefreshing = false
        errorText = nil
        chartDataToken &+= 1

        if resetHistoryRefreshAttempts {
            historyRefreshAttempts = 0
        }

        scheduleHistoryRefreshIfNeeded()
    }

    private func handleLoadError(_ error: Error) {
        isLoading = false
        isRefreshing = false

        if response == nil {
            errorText = (error as? DisplayError)?.text ?? error.localizedDescription
        }
    }

    private func scheduleHistoryRefreshIfNeeded() {
        historyRefreshTask?.cancel()

        guard response?.historyScanCursor != nil,
              historyRefreshAttempts < 6
        else {
            return
        }

        historyRefreshAttempts += 1

        historyRefreshTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            reload(resetHistoryRefreshAttempts: false)
        }
    }
}

extension PortfolioVM: WalletCoreData.EventsObserver {
    func walletCore(event: WalletCoreData.Event) {
        switch event {
        case .accountChanged:
            if $account.source == .current {
                reload(resetHistoryRefreshAttempts: true)
            }
        case .rawBalancesChanged(let accountId):
            if accountId == $account.accountId {
                reload(resetHistoryRefreshAttempts: true)
            }
        case .baseCurrencyChanged:
            reload(resetHistoryRefreshAttempts: true)
        default:
            break
        }
    }
}
