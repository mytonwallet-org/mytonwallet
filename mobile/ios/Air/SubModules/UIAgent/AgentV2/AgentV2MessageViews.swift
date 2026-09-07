import Foundation
import GraphKit
import UIKit
import WalletContext
import WalletCore

enum AgentV2WalletQueryPresentation {
    static func accountAccessMode(_ mode: ApiAgentV2WalletQueryAccountRow.AccessMode) -> String {
        lang(mode == .viewOnly ? "$agent_semantic_access_view_only" : "$agent_semantic_access_regular")
    }

    static func accountNotices(
        outcome _: ApiAgentV2WalletQueryContent.Outcome,
        rows: [ApiAgentV2WalletQueryAccountRow]
    ) -> [String] {
        let unpricedCount = rows.reduce(0) { $0 + ($1.portfolioTotal?.unpricedCount ?? 0) }
        let hasUnavailable = rows.contains { $0.portfolioTotalStatus == .unavailable }
        var notices: [String] = []
        if unpricedCount > 0 {
            notices.append(L10n.agentSemanticWalletsUnpriced(amount: unpricedCount))
        }
        if hasUnavailable { notices.append(lang("$agent_semantic_wallets_unavailable")) }
        return notices
    }

    static func title(
        queryKind: String,
        policySummary: ApiAgentV2WalletQueryPolicySummary?
    ) -> String {
        if policySummary?.presentation == .hiddenReview {
            return lang("$agent_semantic_hidden_assets")
        }
        let isQuarantine = policySummary?.presentation == .quarantine
        if queryKind == "transactions" {
            return lang(isQuarantine ? "$agent_semantic_spam_transactions" : "$agent_semantic_transactions")
        }
        return lang(isQuarantine ? "$agent_semantic_spam_assets" : "$agent_semantic_positions")
    }

    static func warning(policySummary: ApiAgentV2WalletQueryPolicySummary?) -> String? {
        switch policySummary?.presentation {
        case .quarantine: return lang("$agent_semantic_quarantine_warning")
        case .hiddenReview: return lang("$agent_semantic_hidden_assets_warning")
        default: return nil
        }
    }

    static func assetLabel(name: String? = nil, symbol: String?, isRedacted: Bool) -> String? {
        if isRedacted { return lang("$agent_semantic_redacted_asset") }
        guard let name, !name.isEmpty else { return symbol }
        guard let symbol, !symbol.isEmpty, name.caseInsensitiveCompare(symbol) != .orderedSame else {
            return name
        }
        return "\(name) (\(symbol))"
    }

    static func counterTexts(_ summary: ApiAgentV2WalletQueryPolicySummary?) -> [String] {
        guard let summary else { return [] }
        let revealsSuspiciousNames = summary.presentation == .hiddenReview
        return [
            counterText(
                summary.omittedSpam,
                exact: L10n.agentSemanticOmittedSpam,
                lowerBound: L10n.agentSemanticOmittedSpamMinimum
            ),
            counterText(
                summary.omittedHidden,
                exact: L10n.agentSemanticOmittedHidden,
                lowerBound: L10n.agentSemanticOmittedHiddenMinimum
            ),
            counterText(
                summary.suspicious,
                exact: revealsSuspiciousNames
                    ? L10n.agentSemanticSuspiciousShown
                    : L10n.agentSemanticSuspicious,
                lowerBound: revealsSuspiciousNames
                    ? L10n.agentSemanticSuspiciousShownMinimum
                    : L10n.agentSemanticSuspiciousMinimum
            )
        ].compactMap { $0 }
    }

    static func omittedRowsText(_ counter: ApiAgentV2WalletPolicyCounter?) -> String? {
        counterText(
            counter,
            exact: L10n.agentSemanticOmittedRows,
            lowerBound: L10n.agentSemanticOmittedRowsMinimum
        )
    }

    private static func counterText(
        _ counter: ApiAgentV2WalletPolicyCounter?,
        exact: (Int) -> String,
        lowerBound: (Int) -> String
    ) -> String? {
        guard let counter, counter.count > 0 else { return nil }
        let localize = counter.accuracy == .exact ? exact : lowerBound
        return localize(counter.count)
    }
}

enum AgentV2AssetSearchPresentation {
    static func status(_ content: ApiAgentV2AssetSearchContent) -> String? {
        switch content.outcome {
        case .completeAbsent: lang("$agent_semantic_no_results")
        case .incompleteUnconfirmed: lang("$agent_notice_wallet_unavailable")
        case .scopeDenied:
            content.reason == "consent_required"
                ? lang("$agent_notice_consent_required")
                : lang("$agent_notice_tool_unavailable")
        case .completeMatches, .partialMatches, .ambiguous: nil
        }
    }
}

enum AgentV2MessagePresentation {
    struct Bubble: Equatable {
        let text: String
        let rendersMarkdown: Bool
    }

    static func bubble(for message: AgentV2NativeMessage) -> Bubble? {
        if message.contentKind == .markdown {
            return message.text.isEmpty ? nil : Bubble(text: message.text, rendersMarkdown: true)
        }
        guard let content = message.semanticContent,
              case .notice(let notice) = content,
              notice.code == .marketQuote
        else { return nil }
        let text = AgentV2Copy.notice(notice)
        return text.isEmpty ? nil : Bubble(text: text, rendersMarkdown: false)
    }
}

enum AgentV2PortfolioChartAdapter {
    private static let palette = [
        "#0A84FF", "#30D158", "#FFD60A", "#FF453A",
        "#BF5AF2", "#64D2FF", "#FF9F0A", "#8E8E93"
    ]

    static func makeJSON(_ payload: ApiAgentV2PortfolioAnalysisPayload) -> String? {
        guard let chart = payload.performance?.chart,
              chart.kind == "stacked_net_worth",
              !chart.timestamps.isEmpty,
              chart.timestamps.count <= 32,
              !chart.series.isEmpty,
              chart.series.count <= 8 else { return nil }

        var columns: [[Any]] = []
        var x: [Any] = ["x"]
        x.append(contentsOf: chart.timestamps.map { timestamp in
            Int64((timestamp > 10_000_000_000 ? timestamp : timestamp * 1_000).rounded())
        })
        columns.append(x)

        var types = ["x": "x"]
        var names: [String: String] = [:]
        var colors: [String: String] = [:]
        for (index, series) in chart.series.enumerated() {
            guard series.values.count == chart.timestamps.count else { return nil }
            let values = series.values.compactMap(Double.init)
            guard values.count == series.values.count, values.allSatisfy({ $0 >= 0 && $0.isFinite }) else { return nil }
            let id = "y\(index)"
            columns.append([id] + values.map { $0 as Any })
            types[id] = "area"
            names[id] = series.asset.symbol
            colors[id] = palette[index]
        }

        let payload: [String: Any] = [
            "columns": columns,
            "types": types,
            "names": names,
            "colors": colors,
            "stacked": true,
            "percentage": false
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

enum AgentV2MarketCopy {
    static func localized(
        _ key: String,
        fallback: String,
        lookup: (String) -> String = { lang($0) }
    ) -> String {
        let value = lookup(key)
        return value.isEmpty || value == key ? fallback : value
    }
}

struct AgentV2FearGreedRegimePresentation: Equatable {
    struct Row: Equatable {
        let primary: String
        let secondary: String?
        let value: String
    }

    let title: String
    let rows: [Row]
    let attribution: String

    init(
        _ regime: ApiAgentV2MarketFearGreedRegime,
        localize: @escaping (String) -> String = { lang($0) }
    ) {
        let copy = { (key: String, fallback: String) in
            AgentV2MarketCopy.localized(key, fallback: fallback, lookup: localize)
        }
        title = copy(
            "$agent_market_fear_greed_sentiment",
            "Bitcoin-based market sentiment"
        )
        let closedDailyCandle = copy(
            "$agent_market_closed_1d",
            "Latest closed 1D candle"
        )
        rows = [
            Row(
                primary: copy(
                    "$agent_market_fear_greed_index",
                    "Fear & Greed index (0–100)"
                ),
                secondary: "Bitcoin · \(closedDailyCandle)",
                value: localizedIntegerString(regime.latestValue)
            ),
            Row(
                primary: copy("$agent_market_fear_greed_sma_30", "SMA 30"),
                secondary: nil,
                value: Self.formatValue(regime.sma30)
            ),
            Row(
                primary: copy("$agent_market_fear_greed_sma_365", "SMA 365"),
                secondary: nil,
                value: Self.formatValue(regime.sma365)
            ),
            Row(
                primary: copy("$agent_market_fear_greed_regime", "Market regime"),
                secondary: nil,
                value: Self.formatRegime(regime.regime, localize: localize)
            ),
            Row(
                primary: copy("$agent_market_as_of", "As of"),
                secondary: nil,
                value: Self.formatDate(regime.asOfDate)
            )
        ]
        attribution = "\(copy("$agent_market_fear_greed_source", "Source")): \(regime.source.attributionLabel)"
    }

    private static func formatValue(_ raw: String) -> String {
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LocalizationSupport.shared.locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? raw
    }

    private static func formatRegime(
        _ regime: ApiAgentV2MarketFearGreedRegime.Regime,
        localize: (String) -> String
    ) -> String {
        switch regime {
        case .riskOn:
            AgentV2MarketCopy.localized(
                "$agent_market_fear_greed_risk_on",
                fallback: "Risk-on sentiment",
                lookup: localize
            )
        case .riskOff:
            AgentV2MarketCopy.localized(
                "$agent_market_fear_greed_risk_off",
                fallback: "Risk-off sentiment",
                lookup: localize
            )
        case .neutral:
            AgentV2MarketCopy.localized(
                "$agent_market_fear_greed_neutral",
                fallback: "Neutral sentiment",
                lookup: localize
            )
        }
    }

    private static func formatDate(_ raw: String) -> String {
        let inputFormatter = DateFormatter()
        inputFormatter.calendar = Calendar(identifier: .gregorian)
        inputFormatter.locale = Locale(identifier: "en_US_POSIX")
        inputFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        inputFormatter.dateFormat = "yyyy-MM-dd"
        inputFormatter.isLenient = false
        guard let date = inputFormatter.date(from: raw) else { return raw }

        let outputFormatter = DateFormatter()
        outputFormatter.dateStyle = .medium
        outputFormatter.timeStyle = .none
        outputFormatter.locale = LocalizationSupport.shared.locale
        outputFormatter.timeZone = inputFormatter.timeZone
        return outputFormatter.string(from: date)
    }
}

@MainActor
final class AgentV2SemanticContentView: UIView {
    private let stack = UIStackView()
    private var chartView: ChartContainerView?

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        clipsToBounds = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        applyTheme()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        guard traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) else { return }
        applyTheme()
        chartView?.apply(animated: false)
    }

    func configure(content: ApiAgentV2SemanticContent) {
        resetContent()

        switch content {
        case .notice(let notice): configureNotice(notice)
        case .walletQuery(let query): configureWalletQuery(query)
        case .portfolio(let portfolio): configurePortfolio(portfolio)
        case .market(let market): configureMarket(market)
        case .assetSearch(let search): configureAssetSearch(search)
        case .webDigest(let digest): configureWebDigest(digest)
        case .clientUnsupported:
            stack.addArrangedSubview(makeLabel(lang("$agent_semantic_update_required"), style: .body))
        }
    }

    private func resetContent() {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        chartView = nil
    }

    private func configurePortfolio(_ content: ApiAgentV2PortfolioContent) {
        switch content {
        case .analysis(let outcome, let payload, let narrativeMarkdown):
            configureAnalysis(outcome: outcome, payload: payload, narrativeMarkdown: narrativeMarkdown)
        case .positions(_, let payload): configurePositions(payload)
        case .networkActivity(_, let payload): configureActivity(payload)
        }
    }

    private func configureAnalysis(
        outcome: ApiAgentV2PortfolioContent.Outcome,
        payload: ApiAgentV2PortfolioAnalysisPayload,
        narrativeMarkdown: String?
    ) {
        stack.addArrangedSubview(makeLabel(lang("$agent_portfolio_analysis"), style: .headline))

        if let json = AgentV2PortfolioChartAdapter.makeJSON(payload),
           let controller = createChartController(json, type: .absoluteArea) {
            let chart = ChartContainerView()
            chart.translatesAutoresizingMaskIntoConstraints = false
            chart.isUserInteractionEnabled = false
            chart.apply(animated: false)
            chart.setup(controller: controller, noInitialZoom: true, showsRangeSelector: false)
            chart.expandRange(animated: false)
            chart.heightAnchor.constraint(equalToConstant: 310).isActive = true
            chart.accessibilityElementsHidden = true
            stack.addArrangedSubview(chart)
            chartView = chart
        }

        let total = payload.totalValue
        stack.addArrangedSubview(makeLabel(
            "\(lang("$agent_portfolio_value_is")) \(formatMoney(total.value, currency: total.currency)).",
            style: .title3
        ))

        if let change = payload.rangeChange {
            let amount = change.amount.map { formatMoney($0, currency: total.currency) }
            let percent = change.percent.map { formatPercent($0) }
            let text = [amount, percent].compactMap { $0 }.joined(separator: " ")
            if !text.isEmpty {
                let label = makeLabel("\(lang("$agent_portfolio_24h_change")): \(text)", style: .headline)
                label.textColor = change.direction == "down" ? .systemRed : change.direction == "up" ? .systemGreen : .label
                stack.addArrangedSubview(label)
            }
        }

        if let contributor = payload.performance?.topContributor {
            stack.addArrangedSubview(makeLabel(
                "\(lang("$agent_portfolio_top_contributor")): \(contributor.asset.symbol)",
                style: .body
            ))
        }

        if outcome != .complete {
            stack.addArrangedSubview(makeLabel(
                lang("$agent_portfolio_partial"),
                style: .footnote
            ))
        }

        if let narrativeMarkdown, !narrativeMarkdown.isEmpty {
            stack.addArrangedSubview(makeMarkdownLabel(narrativeMarkdown))
        }
        accessibilityLabel = [lang("$agent_portfolio_analysis"), formatMoney(total.value, currency: total.currency)]
            .joined(separator: ". ")
    }

    private func configurePositions(_ payload: ApiAgentV2PortfolioPositionsPayload) {
        let title = lang("$agent_portfolio_largest_positions")
        stack.addArrangedSubview(makeLabel(title, style: .headline))
        for row in payload.positions.prefix(5) {
            stack.addArrangedSubview(makeValueRow(
                primary: row.asset.symbol,
                secondary: networkName(row.asset.chain),
                value: formatMoney(row.amount.value, currency: row.amount.currency)
            ))
        }
        if !payload.unpriced.isEmpty {
            stack.addArrangedSubview(makeLabel(lang("$agent_portfolio_unpriced"), style: .footnote))
            for row in payload.unpriced.prefix(3) {
                stack.addArrangedSubview(makeValueRow(
                    primary: row.asset.symbol,
                    secondary: networkName(row.asset.chain),
                    value: lang("$agent_portfolio_unpriced_value")
                ))
            }
            if payload.omittedUnpricedAssetCount > 0 {
                stack.addArrangedSubview(makeLabel(
                    L10n.agentPortfolioMorePositions(count: payload.omittedUnpricedAssetCount),
                    style: .footnote
                ))
            }
        }
        if payload.dataQuality.coverage == "partial" {
            stack.addArrangedSubview(makeLabel(lang("$agent_portfolio_partial"), style: .footnote))
        }
        accessibilityLabel = [
            title,
            payload.positions.prefix(5).map {
                "\($0.asset.symbol), \(networkName($0.asset.chain)), \(formatMoney($0.amount.value, currency: $0.amount.currency))"
            }.joined(separator: ". ")
        ].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    private func configureActivity(_ payload: ApiAgentV2NetworkActivityPayload) {
        let title = L10n.agentPortfolioHistoryOn(network: networkName(payload.chain))
        stack.addArrangedSubview(makeLabel(title, style: .headline))
        if payload.rows.isEmpty {
            stack.addArrangedSubview(makeLabel(lang("$agent_portfolio_no_activity"), style: .body))
        } else {
            for row in payload.rows.prefix(10) {
                stack.addArrangedSubview(makeValueRow(
                    primary: row.asset?.symbol ?? AgentV2Copy.semanticRow(row.kind.rawValue),
                    secondary: row.safeDescription ?? formatActivityDate(row.timestamp),
                    value: row.amount.map { formatTokenAmount($0) }
                ))
            }
        }
        if payload.status == "partial" {
            stack.addArrangedSubview(makeLabel(lang("$agent_portfolio_partial"), style: .footnote))
        }
        accessibilityLabel = [title, payload.rows.isEmpty ? lang("$agent_portfolio_no_activity") : nil]
            .compactMap { $0 }
            .joined(separator: ". ")
    }

    private func configureNotice(_ notice: ApiAgentV2NoticeContent) {
        let text = AgentV2Copy.notice(notice)
        stack.addArrangedSubview(makeLabel(text, style: .body))
        accessibilityLabel = text
    }

    private func configureWalletQuery(_ content: ApiAgentV2WalletQueryContent) {
        switch content {
        case .accounts(let outcome, _, let omittedRows, let rows):
            let title = lang("$agent_semantic_wallets")
            stack.addArrangedSubview(makeLabel(title, style: .headline))
            if rows.isEmpty {
                stack.addArrangedSubview(makeLabel(lang("$agent_semantic_no_results"), style: .body))
            }
            for row in rows {
                let accessMode = AgentV2WalletQueryPresentation.accountAccessMode(row.accessMode)
                let value = row.portfolioTotal.map {
                    formatMoney($0.value, currency: $0.baseCurrency)
                } ?? lang("$agent_semantic_balance_unavailable")
                let view = makeValueRow(primary: row.accountLabel, secondary: accessMode, value: value)
                view.isAccessibilityElement = true
                view.accessibilityLabel = [row.accountLabel, value, accessMode].joined(separator: ". ")
                stack.addArrangedSubview(view)
            }
            configureOmittedRows(omittedRows)
            for notice in AgentV2WalletQueryPresentation.accountNotices(outcome: outcome, rows: rows) {
                stack.addArrangedSubview(makeLabel(notice, style: .footnote))
            }
            accessibilityLabel = title
        case .transactions(_, _, let omittedRows, let policySummary, let rows):
            let title = AgentV2WalletQueryPresentation.title(
                queryKind: "transactions",
                policySummary: policySummary
            )
            stack.addArrangedSubview(makeLabel(title, style: .headline))
            configureWalletPolicyWarning(policySummary)
            if rows.isEmpty {
                stack.addArrangedSubview(makeLabel(lang("$agent_semantic_no_results"), style: .body))
            }
            for row in rows {
                let date = formatActivityDate(row.timestamp)
                let asset = AgentV2WalletQueryPresentation.assetLabel(
                    symbol: row.assetSymbol,
                    isRedacted: row.assetLabelStatus == .redactedUnsafe
                )
                let quantity = [row.quantity, asset].compactMap { $0 }.joined(separator: " ")
                let view = makeValueRow(
                    primary: date,
                    secondary: AgentV2Copy.semanticRow(row.status.rawValue),
                    value: quantity.isEmpty ? nil : quantity
                )
                view.isAccessibilityElement = true
                view.accessibilityLabel = [date, AgentV2Copy.semanticRow(row.status.rawValue), quantity]
                    .filter { !$0.isEmpty }
                    .joined(separator: ". ")
                stack.addArrangedSubview(view)
            }
            configureOmittedRows(omittedRows)
            configureWalletPolicySummary(policySummary)
            accessibilityLabel = title
        case .positions(_, _, let omittedRows, let policySummary, let rows):
            let title = AgentV2WalletQueryPresentation.title(
                queryKind: "positions",
                policySummary: policySummary
            )
            stack.addArrangedSubview(makeLabel(title, style: .headline))
            configureWalletPolicyWarning(policySummary)
            if rows.isEmpty {
                stack.addArrangedSubview(makeLabel(lang("$agent_semantic_no_results"), style: .body))
            }
            for row in rows {
                let kind = AgentV2Copy.semanticRow(row.positionKind.rawValue)
                let status = row.status.map { AgentV2Copy.semanticRow($0.rawValue) } ?? kind
                let asset = AgentV2WalletQueryPresentation.assetLabel(
                    name: row.assetName,
                    symbol: row.assetSymbol,
                    isRedacted: row.assetLabelStatus == .redactedUnsafe
                ) ?? kind
                let secondary = policySummary?.presentation == .hiddenReview
                    ? "\(row.chain.uppercased()) · \(status)"
                    : status
                let view = makeValueRow(primary: asset, secondary: secondary, value: row.quantity)
                view.isAccessibilityElement = true
                view.accessibilityLabel = [asset, secondary, row.quantity]
                    .compactMap { $0 }
                    .joined(separator: ". ")
                stack.addArrangedSubview(view)
            }
            configureOmittedRows(omittedRows)
            configureWalletPolicySummary(policySummary)
            accessibilityLabel = title
        }
    }

    private func configureOmittedRows(_ counter: ApiAgentV2WalletPolicyCounter?) {
        guard let text = AgentV2WalletQueryPresentation.omittedRowsText(counter) else { return }
        stack.addArrangedSubview(makeLabel(text, style: .footnote))
    }

    private func configureWalletPolicyWarning(_ summary: ApiAgentV2WalletQueryPolicySummary?) {
        guard let text = AgentV2WalletQueryPresentation.warning(policySummary: summary) else { return }
        let warning = makeLabel(text, style: .footnote)
        warning.textColor = .systemOrange
        stack.addArrangedSubview(warning)
    }

    private func configureWalletPolicySummary(_ summary: ApiAgentV2WalletQueryPolicySummary?) {
        for text in AgentV2WalletQueryPresentation.counterTexts(summary) {
            stack.addArrangedSubview(makeLabel(text, style: .footnote))
        }
    }

    private func configureMarket(_ content: ApiAgentV2MarketContent) {
        let title = lang("$agent_semantic_market")
        stack.addArrangedSubview(makeLabel(title, style: .headline))
        switch content {
        case .overview(let outcome, let evidence, let narrativeMarkdown):
            for item in evidence.assets {
                stack.addArrangedSubview(makeValueRow(
                    primary: item.asset.symbol,
                    secondary: formatMoney(item.quote.price, currency: item.quote.quoteCurrency),
                    value: formatPercent(item.change.percent)
                ))
            }
            if let narrativeMarkdown, !narrativeMarkdown.isEmpty {
                stack.addArrangedSubview(makeMarkdownLabel(narrativeMarkdown))
            }
            if outcome == .partial {
                stack.addArrangedSubview(makeLabel(lang("$agent_semantic_partial"), style: .footnote))
            }
        case .analysis(let outcome, _, let analysis, let fearGreedRegime):
            if let summary = analysis?.summary, !summary.isEmpty {
                stack.addArrangedSubview(makeMarkdownLabel(summary))
            }
            if let fearGreedRegime {
                configureFearGreedRegime(fearGreedRegime)
            }
            if outcome == .partial {
                stack.addArrangedSubview(makeLabel(lang("$agent_semantic_partial"), style: .footnote))
            }
        }
        accessibilityLabel = title
    }

    private func configureFearGreedRegime(_ regime: ApiAgentV2MarketFearGreedRegime) {
        let presentation = AgentV2FearGreedRegimePresentation(regime)
        stack.addArrangedSubview(makeLabel(presentation.title, style: .headline))
        for row in presentation.rows {
            stack.addArrangedSubview(makeValueRow(
                primary: row.primary,
                secondary: row.secondary,
                value: row.value
            ))
        }
        stack.addArrangedSubview(makeLabel(presentation.attribution, style: .footnote))
    }

    private func configureAssetSearch(_ content: ApiAgentV2AssetSearchContent) {
        let title = lang("$agent_semantic_asset_search")
        stack.addArrangedSubview(makeLabel(title, style: .headline))
        let assets: [ApiAgentV2SemanticAsset] = switch content.outcome {
        case .ambiguous: content.candidates ?? []
        case .completeMatches, .partialMatches: content.asset.map { [$0] } ?? []
        case .completeAbsent, .incompleteUnconfirmed, .scopeDenied: []
        }
        let status = AgentV2AssetSearchPresentation.status(content)
        if let status {
            stack.addArrangedSubview(makeLabel(status, style: .body))
        }
        for asset in assets {
            stack.addArrangedSubview(makeValueRow(
                primary: asset.name ?? asset.symbol,
                secondary: networkName(asset.chain),
                value: asset.symbol
            ))
        }
        for holding in content.holdings ?? [] {
            stack.addArrangedSubview(makeLabel(holding.accountLabel, style: .footnote))
        }
        accessibilityLabel = [title, status].compactMap { $0 }.joined(separator: ". ")
    }

    private func configureWebDigest(_ content: ApiAgentV2WebDigestContent) {
        let title = lang("$agent_semantic_web_digest")
        stack.addArrangedSubview(makeLabel(title, style: .headline))
        if let summary = content.summary, !summary.isEmpty {
            stack.addArrangedSubview(makeLabel(summary, style: .body))
        }
        if content.items.isEmpty {
            stack.addArrangedSubview(makeLabel(lang("$agent_semantic_no_results"), style: .body))
        }
        for item in content.items {
            stack.addArrangedSubview(makeValueRow(primary: item.headline, secondary: item.summary, value: nil))
        }
        accessibilityLabel = title
    }

    private func makeValueRow(primary: String, secondary: String?, value: String?) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12

        let labels = UIStackView()
        labels.axis = .vertical
        labels.spacing = 2
        labels.addArrangedSubview(makeLabel(primary, style: .body))
        if let secondary, !secondary.isEmpty {
            let secondaryLabel = makeLabel(secondary, style: .caption1)
            secondaryLabel.textColor = .secondaryLabel
            labels.addArrangedSubview(secondaryLabel)
        }
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(UIView())
        if let value {
            let valueLabel = makeLabel(value, style: .body)
            valueLabel.textAlignment = .natural
            valueLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(valueLabel)
        }
        return row
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .label
        label.numberOfLines = 0
        label.text = text
        return label
    }

    private func makeMarkdownLabel(_ text: String) -> UILabel {
        let label = makeLabel("", style: .body)
        let attributed = AgentMessageTextRenderer.makeAttributedText(
            text,
            textColor: label.textColor,
            rendersMarkdown: true,
            detectsLinks: false,
            markdownProfile: .agentMarkdownV1,
            baseFont: label.font
        )
        label.attributedText = attributed
        label.accessibilityLabel = attributed.string
        return label
    }

    private func applyTheme() {
        backgroundColor = .air.secondaryFill
    }

    private func formatMoney(_ raw: String, currency: String) -> String {
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = LocalizationSupport.shared.locale
        return formatter.string(from: value as NSDecimalNumber) ?? raw
    }

    private func formatPercent(_ raw: String) -> String {
        guard let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return raw }
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value / 100)) ?? "\(raw)%"
    }

    private func formatTokenAmount(_ money: ApiAgentV2Money) -> String {
        guard let value = Decimal(string: money.value, locale: Locale(identifier: "en_US_POSIX")) else {
            return "\(money.value) \(money.symbol)"
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LocalizationSupport.shared.locale
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = min(money.decimals, 18)
        let amount = formatter.string(from: value as NSDecimalNumber) ?? money.value
        return "\(amount) \(money.symbol)"
    }

    private func networkName(_ raw: String) -> String {
        switch raw {
        case "ton": return "TON"
        case "ethereum": return "Ethereum"
        case "tron": return "TRON"
        case "solana": return "Solana"
        default: return raw
        }
    }

    private func formatActivityDate(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LocalizationSupport.shared.locale
        return formatter.string(from: AgentV2DateParser.date(raw))
    }

}

@MainActor
final class AgentV2MessageCell: UITableViewCell {
    var onAction: ((AgentV2NativeAction) -> Void)?
    var onFollowUp: ((ApiAgentV2FollowUp) -> Void)?
    var onInputContinuation: ((ApiAgentV2InputContinuation) -> Void)?
    var onWalletControl: ((ApiAgentV2WalletConversationControls.ScopeChoice) -> Void)?
    var onPreferredHeightChanged: (() -> Void)?
    var onStreamingRevealCompleted: (() -> Void)?
    var messageId: String? { configuredMessageId }

    var isStreamingRevealActive: Bool {
        configuredRevealPhase.isActive
    }

    private let outerStack = UIStackView()
    private let streamingTextView = AgentStreamingTextView()
    private var configuredMessage: AgentV2NativeMessage?
    private var configuredMessageId: String?
    private var configuredRevealPhase = AgentV2MessageRevealPhase.staticContent
    private var lastTextLayoutMaxWidth: CGFloat = 0
    private var isConfiguring = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        outerStack.translatesAutoresizingMaskIntoConstraints = false
        outerStack.axis = .vertical
        outerStack.spacing = 8
        contentView.addSubview(outerStack)
        NSLayoutConstraint.activate([
            outerStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            outerStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            outerStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            outerStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        removeContent()
        streamingTextView.prepareForReuse()
        configuredMessage = nil
        configuredMessageId = nil
        configuredRevealPhase = .staticContent
        lastTextLayoutMaxWidth = 0
        onAction = nil
        onFollowUp = nil
        onInputContinuation = nil
        onWalletControl = nil
        onPreferredHeightChanged = nil
        onStreamingRevealCompleted = nil
    }

    func configure(
        message: AgentV2NativeMessage,
        revealPhase: AgentV2MessageRevealPhase = .staticContent
    ) {
        isConfiguring = true
        defer { isConfiguring = false }

        if updateStreamingMessage(message, revealPhase: revealPhase) {
            return
        }

        let isSameMessage = configuredMessageId == message.id
        if !isSameMessage {
            streamingTextView.prepareForReuse()
        }
        configuredMessage = message
        configuredMessageId = message.id
        configuredRevealPhase = revealPhase
        removeContent()

        let isUser = message.role == .user
        let bubblePresentation = AgentV2MessagePresentation.bubble(for: message)
        let isMarkdownAssistant = !isUser && message.contentKind == .markdown
        let hasStreaming = isMarkdownAssistant
            && revealPhase == .streaming
            && bubblePresentation != nil
        let hadStreaming = isMarkdownAssistant
            && revealPhase == .finishing
            && bubblePresentation != nil
        if let bubblePresentation {
            let row = UIView()
            let bubble = UIStackView()
            bubble.translatesAutoresizingMaskIntoConstraints = false
            bubble.axis = .vertical
            bubble.alignment = .fill
            bubble.spacing = 0
            bubble.isLayoutMarginsRelativeArrangement = true
            bubble.backgroundColor = isUser ? .tintColor : .air.secondaryFill
            bubble.layer.cornerRadius = 20
            bubble.layer.cornerCurve = .continuous
            bubble.clipsToBounds = true
            bubble.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
            let blocks = isMarkdownAssistant && !hasStreaming && !hadStreaming
                ? AgentMessageBlockParser.parse(bubblePresentation.text)
                : []
            let containsTable = blocks.contains {
                if case .table = $0 { return true }
                return false
            }
            if containsTable {
                let richMessageView = AgentRichMessageView()
                richMessageView.accessibilityIdentifier = "agent-v2-answer"
                richMessageView.configure(
                    blocks: blocks,
                    textColor: .label,
                    maximumContentWidth: AgentContentLayout.maxContentWidth - 54,
                    detectsLinks: false,
                    markdownProfile: .agentMarkdownV1,
                    onURLTap: nil
                )
                bubble.addArrangedSubview(richMessageView)
            } else if isMarkdownAssistant {
                configureStreamingText(
                    bubblePresentation,
                    messageId: message.id,
                    hasStreaming: hasStreaming,
                    hadStreaming: hadStreaming
                )
                bubble.addArrangedSubview(streamingTextView)
            } else {
                let label = UILabel()
                label.numberOfLines = 0
                label.font = .preferredFont(forTextStyle: .body)
                label.adjustsFontForContentSizeCategory = true
                label.textColor = isUser ? UIColor.tintColor.foregroundForTintedBackground : .label
                label.accessibilityIdentifier = "agent-v2-answer"
                if isUser {
                    label.text = bubblePresentation.text
                } else {
                    let attributedText = AgentMessageTextRenderer.makeAttributedText(
                        bubblePresentation.text,
                        textColor: label.textColor,
                        rendersMarkdown: bubblePresentation.rendersMarkdown,
                        detectsLinks: false,
                        markdownProfile: .agentMarkdownV1,
                        baseFont: label.font
                    )
                    label.attributedText = attributedText
                    label.accessibilityLabel = attributedText.string
                }
                bubble.addArrangedSubview(label)
            }
            row.addSubview(bubble)
            let leading = bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor)
            let trailing = bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor)
            NSLayoutConstraint.activate([
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.widthAnchor.constraint(lessThanOrEqualTo: row.widthAnchor, multiplier: 0.86),
                isUser ? bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor) : bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                leading,
                trailing
            ])
            outerStack.addArrangedSubview(row)
        }

        if let content = message.semanticContent, bubblePresentation == nil {
            let semanticView = AgentV2SemanticContentView()
            semanticView.configure(content: content)
            outerStack.addArrangedSubview(semanticView)
        }

        let shouldDeferSupplementaryContent = hasStreaming || hadStreaming
        if let error = message.error, !shouldDeferSupplementaryContent {
            let label = makeBodyLabel(AgentV2Copy.error(error.code))
            label.textColor = .systemRed
            outerStack.addArrangedSubview(label)
        }

        if !shouldDeferSupplementaryContent {
            for action in message.actions {
                outerStack.addArrangedSubview(makeActionCard(action))
            }
        }

        if !shouldDeferSupplementaryContent,
           message.walletControls != nil || !message.followups.isEmpty || !message.inputContinuations.isEmpty {
            let scrollView = UIScrollView()
            scrollView.showsHorizontalScrollIndicator = false
            scrollView.alwaysBounceHorizontal = true
            scrollView.isDirectionalLockEnabled = true
            scrollView.accessibilityIdentifier = "agent-v2-followup-row"
            let promptStack = UIStackView()
            promptStack.translatesAutoresizingMaskIntoConstraints = false
            promptStack.axis = .horizontal
            promptStack.spacing = 6
            scrollView.addSubview(promptStack)

            let rowHeight = max(44, UIFont.preferredFont(forTextStyle: .body).lineHeight + 20)
            NSLayoutConstraint.activate([
                promptStack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                promptStack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                promptStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                promptStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                promptStack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
                scrollView.heightAnchor.constraint(equalToConstant: rowHeight)
            ])

            for choice in message.walletControls?.scopeChoices ?? [] {
                promptStack.addArrangedSubview(makePromptButton(title: choice.label) { [weak self] in
                    self?.onWalletControl?(choice)
                })
            }
            for continuation in message.inputContinuations {
                promptStack.addArrangedSubview(makePromptButton(title: AgentV2Copy.inputContinuation(continuation.code)) { [weak self] in
                    self?.onInputContinuation?(continuation)
                })
            }
            for followup in message.followups {
                promptStack.addArrangedSubview(makePromptButton(title: followup.text) { [weak self] in
                    self?.onFollowUp?(followup)
                })
            }
            outerStack.addArrangedSubview(scrollView)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let message = configuredMessage,
              message.role == .assistant,
              message.contentKind == .markdown,
              streamingTextView.superview != nil,
              let bubblePresentation = AgentV2MessagePresentation.bubble(for: message) else { return }
        let layoutMaxWidth = currentTextLayoutMaxWidth()
        guard abs(layoutMaxWidth - lastTextLayoutMaxWidth) > 0.5 else { return }

        let hasStreaming = configuredRevealPhase == .streaming
        let hadStreaming = configuredRevealPhase == .finishing
        isConfiguring = true
        configureStreamingText(
            bubblePresentation,
            messageId: message.id,
            hasStreaming: hasStreaming,
            hadStreaming: hadStreaming
        )
        isConfiguring = false
    }

    private func removeContent() {
        outerStack.arrangedSubviews.forEach { view in
            outerStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
    }

    private func updateStreamingMessage(
        _ message: AgentV2NativeMessage,
        revealPhase: AgentV2MessageRevealPhase
    ) -> Bool {
        guard configuredMessageId == message.id,
              message.role == .assistant,
              message.contentKind == .markdown,
              streamingTextView.superview != nil,
              let bubblePresentation = AgentV2MessagePresentation.bubble(for: message) else { return false }

        let hasStreaming = revealPhase == .streaming
        let hadStreaming = revealPhase == .finishing
        guard hasStreaming || hadStreaming else { return false }

        configuredMessage = message
        configuredRevealPhase = revealPhase
        configureStreamingText(
            bubblePresentation,
            messageId: message.id,
            hasStreaming: hasStreaming,
            hadStreaming: hadStreaming
        )
        return true
    }

    private func configureStreamingText(
        _ presentation: AgentV2MessagePresentation.Bubble,
        messageId: String,
        hasStreaming: Bool,
        hadStreaming: Bool
    ) {
        let font = UIFont.preferredFont(forTextStyle: .body)
        let layoutMaxWidth = currentTextLayoutMaxWidth()
        lastTextLayoutMaxWidth = layoutMaxWidth
        streamingTextView.isAccessibilityElement = true
        streamingTextView.accessibilityIdentifier = "agent-v2-answer"
        streamingTextView.onPreferredHeightChanged = { [weak self] _ in
            guard let self, !self.isConfiguring else { return }
            self.onPreferredHeightChanged?()
        }
        streamingTextView.onRevealCompleted = { [weak self] in
            guard let self, let message = self.configuredMessage else { return }
            self.configuredRevealPhase = .staticContent
            self.onStreamingRevealCompleted?()
            guard self.configuredMessageId == message.id else { return }
            self.configure(message: message, revealPhase: .staticContent)
            self.onPreferredHeightChanged?()
        }
        streamingTextView.configure(
            text: presentation.text,
            textColor: .label,
            isStreaming: hasStreaming,
            hadStreaming: hadStreaming,
            rendersMarkdown: presentation.rendersMarkdown,
            markdownProfile: .agentMarkdownV1,
            baseFont: font,
            allowsLinks: false,
            layoutMaxWidth: layoutMaxWidth,
            streamingIdentity: messageId
        )
        streamingTextView.accessibilityLabel = streamingTextView.displayText
    }

    private func currentTextLayoutMaxWidth() -> CGFloat {
        let fallbackWidth = min(
            UIScreen.main.bounds.width - 32,
            AgentContentLayout.maxContentWidth - 32
        )
        let contentWidth = outerStack.bounds.width >= 200
            ? outerStack.bounds.width
            : fallbackWidth
        return max(120, contentWidth * 0.86 - 28)
    }

    private func makePromptButton(title: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.cornerStyle = .large
        configuration.titleLineBreakMode = .byTruncatingTail
        let button = UIButton(configuration: configuration)
        button.accessibilityLabel = title
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.widthAnchor.constraint(lessThanOrEqualToConstant: 288).isActive = true
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        return button
    }

    private func makeActionCard(_ action: AgentV2NativeAction) -> UIView {
        let container = UIStackView()
        container.axis = .vertical
        container.spacing = 8
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        container.isLayoutMarginsRelativeArrangement = true
        container.backgroundColor = .air.secondaryFill
        container.layer.cornerRadius = 18
        container.layer.cornerCurve = .continuous

        let title = UILabel()
        title.font = .preferredFont(forTextStyle: .headline)
        title.numberOfLines = 0
        title.text = AgentV2Copy.action(action.labelCode)
        container.addArrangedSubview(title)

        var configuration = UIButton.Configuration.filled()
        configuration.title = AgentV2Copy.action(action.labelCode)
        configuration.cornerStyle = .large
        let button = UIButton(configuration: configuration)
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        if action.kind == .send && action.labelCode != .openSend {
            button.isEnabled = action.presentation?.kind == .send && action.presentation?.status == .active
        }
        button.addAction(UIAction { [weak self] _ in self?.onAction?(action) }, for: .touchUpInside)
        container.addArrangedSubview(button)
        return container
    }

    private func makeBodyLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.text = text
        return label
    }
}
