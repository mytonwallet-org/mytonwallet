import GRDB
import Testing
import UIKit
import UIComponents
@testable import UIToken
import WalletContext
@testable import WalletCore
import WalletResources

@MainActor
@Suite("Token Chart Loading", .serialized, .settingsStoreIsolation)
struct TokenChartLoadingTests {
    @Test
    func `reopening a stock-only cache shows loading until token history arrives`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let slug = "test-stock-only-loading-\(UUID())"
        let now = Date.now.timeIntervalSince1970
        let backfill = ApiPriceHistoryBackfill(symbol: "NVDA", points: [[now - 86400, 140], [now - 3600, 150]])
        let stockOnly = ApiPriceHistory(points: [], backfill: backfill)
        #expect(TokenStore.setPriceHistory(tokenSlug: slug, period: .all, history: stockOnly, baseCurrency: TokenStore.baseCurrency))
        let cached = TokenStore.cachedPriceHistory(tokenSlug: slug, period: .all)
        fixture.configure(cached?.points, backfill: cached?.backfill, isHistoryRestored: true)
        await waitUntil { fixture.spinner.alpha == 1 }
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)
        fixture.record("stock-cache-waiting-for-token-history.png")

        fixture.configure([[now - 1800, 155], [now, 160]], backfill: backfill)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)
        try await Task.sleep(for: .milliseconds(300))
        fixture.record("stock-and-token-history-loaded.png")
    }

    @Test
    func `first opening shows the spinner without a presentation delay`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure(nil)
        await waitUntil { fixture.spinner.alpha == 1 }
        #expect(fixture.spinner.presentationDelay == 0)
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.spinner.alpha == 1)
        #expect(fixture.emptyLabel.isHidden)
    }

    @Test(arguments: [true, false])
    func `empty history distinguishes refreshing failure retry and success`(isExpanded: Bool) async throws {
        let fixture = try await Fixture(isExpanded: isExpanded)
        defer { fixture.close() }
        var requestedPeriods: [ApiPriceHistoryPeriod] = []
        func configure(_ history: [[Double]]?, state: TokenHistoryLoadingState) {
            fixture.view.configure(token: .TONCOIN, historyData: history, backfill: nil,
                isHistoryRestored: true, historyLoadingState: state,
                onPeriodChange: { requestedPeriods.append($0) }, onAnalyze: nil)
        }
        configure([], state: .loading)
        await waitUntil { fixture.spinner.alpha == 1 }
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.retryButton.isHidden)

        configure([], state: .failed)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)
        #expect(!fixture.retryButton.isHidden)
        fixture.window.layoutIfNeeded()
        #expect(fixture.view.bounds.contains(fixture.retryButton.frame))
        fixture.record(isExpanded ? "chart-error-expanded.png" : "chart-error-collapsed.png")

        let action = try #require(fixture.retryButton.actions(forTarget: fixture.view, forControlEvent: .touchUpInside)?.first)
        fixture.view.perform(NSSelectorFromString(action))
        #expect(requestedPeriods.count == 1)
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.retryButton.isHidden)
        #expect(fixture.emptyLabel.isHidden)

        configure([[1, 1], [2, 2]], state: .loaded)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.retryButton.isHidden)
        #expect(fixture.emptyLabel.isHidden)
        configure([], state: .loaded)
        #expect(!fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.retryButton.isHidden)
    }

    @Test
    func `a failed refresh preserves the chart without covering it with an error`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.view.configure(token: .TONCOIN, historyData: [[1, 1], [2, 2]], backfill: nil,
            isHistoryRestored: true, historyLoadingState: .failed,
            onPeriodChange: { _ in }, onAnalyze: nil)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.retryButton.isHidden)
    }

    @Test(arguments: [true, false])
    func `dates fade near full expansion and stay above the period controls`(isExpanded: Bool) async throws {
        var sampleFrame: (() -> Void)?
        let fixture = try await Fixture(isExpanded: isExpanded, onHeightChange: { sampleFrame?() })
        defer {
            sampleFrame = nil
            fixture.close()
        }
        fixture.configure([[1, 1], [2, 2]])
        await waitUntil { fixture.axis.alpha == (isExpanded ? 1 : 0) }
        let initialHeight = fixture.view.height
        var samples: [(height: CGFloat, alpha: CGFloat, gap: CGFloat)] = []
        sampleFrame = {
            samples.append((fixture.view.height, fixture.axis.alpha, fixture.periods.frame.minY - fixture.axis.frame.maxY))
        }

        fixture.view.perform(NSSelectorFromString("handleToggleTap"))
        await waitUntil { AppStorageHelper.isTokenChartExpanded == !isExpanded }
        sampleFrame = nil

        let expandedHeight = max(initialHeight, fixture.view.height)
        let earlySamples = samples.filter {
            let expansion = ($0.height - TokenExpandableChartView.collapsedHeight)
                / (expandedHeight - TokenExpandableChartView.collapsedHeight)
            return expansion > 0.5 && expansion < 0.85
        }
        #expect(AppStorageHelper.isTokenChartExpanded == !isExpanded)
        #expect(!earlySamples.isEmpty)
        #expect(samples.contains { $0.alpha > 0 && $0.alpha < 1 })
        #expect(earlySamples.allSatisfy { $0.alpha == 0 })
        #expect(samples.filter { $0.alpha > 0 }.allSatisfy { $0.gap >= 5.5 })
        #expect(fixture.axis.alpha == (isExpanded ? 0 : 1))
    }

    @Test(arguments: [true, false])
    func `history refresh preserves the date fade during a toggle`(isExpanded: Bool) async throws {
        var sampleFrame: (() -> Void)?
        let fixture = try await Fixture(isExpanded: isExpanded, onHeightChange: { sampleFrame?() })
        defer {
            sampleFrame = nil
            fixture.close()
        }
        fixture.configure([[1, 1], [2, 2]])
        await waitUntil { fixture.axis.alpha == (isExpanded ? 1 : 0) }
        var refreshedAlpha: (before: CGFloat, after: CGFloat)?
        sampleFrame = {
            guard refreshedAlpha == nil, fixture.axis.alpha > 0, fixture.axis.alpha < 1 else { return }
            let before = fixture.axis.alpha
            fixture.configure([[1, 1], [2, 3]])
            refreshedAlpha = (before, fixture.axis.alpha)
        }

        fixture.view.perform(NSSelectorFromString("handleToggleTap"))
        await waitUntil { AppStorageHelper.isTokenChartExpanded == !isExpanded }
        sampleFrame = nil

        let alpha = try #require(refreshedAlpha)
        #expect(alpha.after == alpha.before)
        #expect(fixture.axis.alpha == (isExpanded ? 0 : 1))
    }

    @Test(arguments: [true, false])
    func `owned token chart expansion survives reopening`(isExpanded: Bool) async throws {
        let fixture = try await Fixture(isExpanded: isExpanded)
        defer { fixture.close() }
        fixture.configure([[1, 1], [2, 2]])
        try await Task.sleep(for: .milliseconds(100))
        await waitUntil { isChartExpanded(fixture.view) == isExpanded }
        #expect(isChartExpanded(fixture.view) == isExpanded)
        #expect((fixture.view.height > TokenExpandableChartView.collapsedHeight) == isExpanded)
        #expect(AppStorageHelper.isTokenChartExpanded == isExpanded)
        fixture.view.perform(NSSelectorFromString("handleToggleTap"))
        await waitUntil { AppStorageHelper.isTokenChartExpanded == !isExpanded }
        #expect(AppStorageHelper.isTokenChartExpanded == !isExpanded)

        let reopened = TokenExpandableChartView(onHeightChange: {})
        reopened.configure(token: .TONCOIN, historyData: [[1, 1], [2, 2]], backfill: nil,
                           isHistoryRestored: false, onPeriodChange: { _ in }, onAnalyze: nil)
        try await Task.sleep(for: .milliseconds(100))
        await waitUntil { isChartExpanded(reopened) == !isExpanded }
        #expect(isChartExpanded(reopened) == !isExpanded)
        #expect((reopened.height > TokenExpandableChartView.collapsedHeight) == !isExpanded)
    }

    @Test(arguments: [true, false])
    func `zero balance charts open expanded without changing the owned token preference`(isExpanded: Bool) async throws {
        let fixture = try await Fixture(isExpanded: isExpanded)
        defer { fixture.close() }
        fixture.configure([[1, 1], [2, 2]], showsTokenIcon: true)
        try await Task.sleep(for: .milliseconds(100))
        await waitUntil { fixture.view.height > TokenExpandableChartView.collapsedHeight }
        #expect(fixture.view.height > TokenExpandableChartView.collapsedHeight)
        #expect(AppStorageHelper.isTokenChartExpanded == isExpanded)

        let reopened = TokenExpandableChartView(onHeightChange: {})
        reopened.configure(token: .TONCOIN, showsTokenIcon: true, historyData: [[1, 1], [2, 2]], backfill: nil,
                           isHistoryRestored: false, onPeriodChange: { _ in }, onAnalyze: nil)
        try await Task.sleep(for: .milliseconds(100))
        await waitUntil { reopened.height > TokenExpandableChartView.collapsedHeight }
        #expect(reopened.height > TokenExpandableChartView.collapsedHeight)
        #expect(AppStorageHelper.isTokenChartExpanded == isExpanded)

        let owned = TokenExpandableChartView(onHeightChange: {})
        owned.configure(token: .TONCOIN, historyData: [[1, 1], [2, 2]], backfill: nil,
                        isHistoryRestored: false, onPeriodChange: { _ in }, onAnalyze: nil)
        try await Task.sleep(for: .milliseconds(100))
        await waitUntil { (owned.height > TokenExpandableChartView.collapsedHeight) == isExpanded }
        #expect((owned.height > TokenExpandableChartView.collapsedHeight) == isExpanded)
    }

    @Test(arguments: [true, false])
    func `stock history keeps its dates on instant expansion without a legend`(hasTokenHistory: Bool) async throws {
        let fixture = try await Fixture(isExpanded: false)
        defer { fixture.close() }
        let backfill = ApiPriceHistoryBackfill(symbol: "QQQ", points: [[1, 100], [2, 110]])
        fixture.configure(hasTokenHistory ? [[3, 120], [4, 130]] : [], backfill: backfill, showsTokenIcon: true)
        try await Task.sleep(for: .milliseconds(100))

        let timeAxis = try #require(fixture.view.subviews.compactMap { $0 as? UIStackView }.first {
            $0.arrangedSubviews.count == 4 && $0.arrangedSubviews.allSatisfy { $0 is UILabel }
        })
        #expect(fixture.view.height > TokenExpandableChartView.collapsedHeight)
        #expect(timeAxis.alpha == 1)
        #expect(timeAxis.arrangedSubviews.compactMap { ($0 as? UILabel)?.text }.allSatisfy { !$0.isEmpty })
        #expect(fixture.label(withText: L10n.underlyingStock(symbol: "QQQ")) == nil)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isHidden)
    }

    @Test
    func `supplied market quote and currency are independent of the token quote`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        var token = ApiToken.TONCOIN
        token.priceUsd = 1.5
        fixture.view.configure(
            token: token, price: 64_845, percentChange24h: 3.23,
            baseCurrency: .EUR, period: .day, historyData: [],
            onPeriodChange: { _ in }
        )
        let expectedPrice = BaseCurrencyAmount.fromDouble(64_845, .EUR)
            .formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        let priceLabel = try #require(fixture.label(withText: expectedPrice))
        let changeLabel = try #require(fixture.label(withText: formatPercent(0.0323)))

        fixture.view.configure(
            token: token, price: nil, percentChange24h: nil,
            baseCurrency: .EUR, period: .day, historyData: [],
            onPeriodChange: { _ in }
        )
        #expect(priceLabel.text?.isEmpty != false)
        #expect(changeLabel.text?.isEmpty != false)
    }

    @Test
    func `restored history keeps the live quote until a fresh response arrives`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        try fixture.selectPeriod(0)
        let history = [[1.0, 50.0], [2.0, 95.0]]
        fixture.configure(history)
        let historyPrice = BaseCurrencyAmount.fromDouble(95, TokenStore.baseCurrency).formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        let livePrice = BaseCurrencyAmount.fromDouble(1.5, TokenStore.baseCurrency).formatted(.baseCurrencyEquivalent, roundHalfUp: true)
        let priceLabel = try #require(fixture.label(withText: historyPrice))
        let changeLabel = try #require(fixture.label(withText: formatPercent(0.9)))

        fixture.configure(history, isHistoryRestored: true)
        #expect(priceLabel.text == livePrice)
        #expect(changeLabel.text?.isEmpty != false)
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)

        fixture.view.rangeChanged(0.25...0.75)
        #expect(priceLabel.text == livePrice)
        #expect(changeLabel.text?.isEmpty != false)

        fixture.configure(history)
        #expect(priceLabel.text == historyPrice)
        #expect(changeLabel.text == formatPercent(0.9))
    }

    @Test
    func `switching from empty history hides the label while the next period loads`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        #expect(fixture.emptyLabel.isHidden == false)

        try fixture.selectPeriod(0)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isAnimating)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.spinner.isAnimating)
    }

    @Test
    func `stale chart shines without dimming period controls or changing layout`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        let history = [[1.0, 50.0], [2.0, 95.0]]
        fixture.configure(history)
        fixture.window.layoutIfNeeded()
        let height = fixture.view.height
        let quote = try #require(fixture.view.subviews.first { $0.accessibilityIdentifier == "Token.Chart.QuoteShine" } as? TradeShineView)
        let plot = try #require(fixture.view.subviews.first { $0.accessibilityIdentifier == "Token.Chart.PlotShine" } as? TradeShineView)
        let animation = try #require(fixture.view.subviews.first { $0.accessibilityIdentifier == "Token.Chart.AnimationShine" } as? TradeShineView)
        let quoteFrame = quote.frame
        let plotFrame = plot.frame

        fixture.view.configure(token: .TONCOIN, price: 1.5, percentChange24h: 2,
            baseCurrency: .USD, historyData: history, isHistoryRestored: true,
            isHistoryStale: true, isValueStale: true, onPeriodChange: { _ in })
        try await Task.sleep(for: .milliseconds(300))
        fixture.window.layoutIfNeeded()
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)
        #expect(fixture.view.height == height)
        #expect(plot.frame == plotFrame)
        #expect(quote.frame.origin == quoteFrame.origin)
        #expect(quote.content.alpha < 1)
        #expect(plot.content.alpha < 1)
        #expect(!animation.isUserInteractionEnabled)
        #expect(fixture.periods.alpha == 1)
        #expect(!fixture.periods.isDescendant(of: quote))
        #expect(!fixture.periods.isDescendant(of: plot))
        if TradeMotion.enabled {
            #expect(plot.layer.mask != nil)
        }

        fixture.configure(history)
        try await Task.sleep(for: .milliseconds(300))
        #expect(quote.content.alpha == 1)
        #expect(plot.layer.mask == nil)
    }

    @Test
    func `switching periods with an already visible spinner stays pending`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        try fixture.selectPeriod(0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.spinner.alpha == 1)

        try fixture.selectPeriod(1)
        try await Task.sleep(for: .milliseconds(400))
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)

        fixture.record("loading-after-period-switch.png")
        fixture.configure([])
        fixture.record("empty-response.png")
        #expect(fixture.spinner.isHidden)
        #expect(fixture.spinner.isAnimating == false)
        #expect(fixture.emptyLabel.isHidden == false)
    }

    @Test
    func `reconfiguration distinguishes pending empty and populated history`() async throws {
        let fixture = try await Fixture()
        defer { fixture.close() }
        fixture.configure([])
        fixture.configure(nil)
        #expect(fixture.spinner.isAnimating)
        #expect(fixture.emptyLabel.isHidden)

        fixture.configure([[1, 1], [2, 2]])
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden)

        fixture.configure(nil)
        try await Task.sleep(for: .milliseconds(400))
        fixture.configure([])
        #expect(fixture.spinner.isHidden)
        #expect(fixture.emptyLabel.isHidden == false)
    }

    @MainActor
    private final class Fixture {
        let view: TokenExpandableChartView
        let window: UIWindow
        let spinner: WActivityIndicator
        let emptyLabel: UILabel
        let periods: WChartSegmentedControl
        let axis: UIStackView
        let retryButton: UIButton

        init(isExpanded: Bool = true, onHeightChange: @escaping () -> Void = {}) async throws {
            _ = WalletResourcesBundle.bundle.load()
            let db = try DatabaseQueue()
            try makeMigrator().migrate(db)
            SettingsStore.liveValue.use(db: db)
            AppStorageHelper.isTokenChartExpanded = isExpanded
            view = TokenExpandableChartView(onHeightChange: onHeightChange)
            spinner = try #require(view.subviews.compactMap { $0 as? WActivityIndicator }.first)
            emptyLabel = try #require(view.subviews.compactMap { $0 as? UILabel }.first)
            periods = try #require(view.subviews.compactMap { $0 as? WChartSegmentedControl }.first)
            axis = try #require(view.subviews.compactMap { $0 as? UIStackView }.first)
            retryButton = try #require(view.subviews.first { $0.accessibilityIdentifier == "Token.Chart.Retry" } as? UIButton)

            window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            let controller = UIViewController()
            window.rootViewController = controller
            window.isHidden = false
            controller.view.addSubview(view)
            NSLayoutConstraint.activate([
                view.topAnchor.constraint(equalTo: controller.view.topAnchor, constant: 100),
                view.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 16),
                view.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
            ])
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }

        func configure(_ history: [[Double]]?, backfill: ApiPriceHistoryBackfill? = nil, isHistoryRestored: Bool = false, showsTokenIcon: Bool = false) {
            var token = ApiToken.TONCOIN
            token.priceUsd = 1.5
            view.configure(token: token, showsTokenIcon: showsTokenIcon, historyData: history, backfill: backfill, isHistoryRestored: isHistoryRestored, onPeriodChange: { _ in }, onAnalyze: nil)
        }

        func label(withText text: String) -> UILabel? {
            func find(in view: UIView) -> UILabel? {
                if let label = view as? UILabel, label.text == text { return label }
                return view.subviews.lazy.compactMap { find(in: $0) }.first
            }
            return find(in: view)
        }

        func selectPeriod(_ index: Int) throws {
            periods.selectedSegmentIndex = index
            // These package tests have no UIApplication to dispatch UIControl actions.
            let action = try #require(periods.actions(forTarget: view, forControlEvent: .valueChanged)?.first)
            view.perform(NSSelectorFromString(action), with: periods)
        }

        func record(_ name: String) {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: view.bounds).image { context in
                view.layer.render(in: context.cgContext)
            }
            if let data = image.pngData() {
                Attachment.record(data, named: name)
            }
        }

        func close() {
            spinner.stopAnimating(animated: false)
            window.isHidden = true
            SettingsStore.liveValue.clean()
        }
    }
}

/// The chart's own expanded state, which only the asynchronous restoration sets. The height alone does not show it:
/// the view takes the height from the saved preference before restoration runs.
@MainActor
private func isChartExpanded(_ view: TokenExpandableChartView) -> Bool? {
    Mirror(reflecting: view).descendant("isExpanded") as? Bool
}

/// Waits until `condition` holds or the timeout passes, then returns either way for the caller to assert. The timeout
/// counts 16 ms samples rather than wall time: the chart restores and toggles through a background queue and a 0.55 s
/// animation, which a busy machine stalls, and that time is not the chart's to spend. Ten times the timeout in wall time
/// still ends a wait whose samples keep stalling.
@MainActor
private func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let sampleInterval = Duration.milliseconds(16)
    var remainingSamples = Int((timeout / sampleInterval).rounded(.up))
    let deadline = ContinuousClock.now + timeout * 10
    while !condition(), remainingSamples > 0, ContinuousClock.now < deadline {
        remainingSamples -= 1
        try? await Task.sleep(for: sampleInterval)
    }
}
