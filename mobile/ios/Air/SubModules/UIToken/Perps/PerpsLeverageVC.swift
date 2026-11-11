import Perception
import SwiftUI
import UIKit
import UIComponents
import WalletContext

/// A pending estimate keeps the last available price marked as loading
@Perceptible @MainActor
final class PerpsLeverageMetrics {
    var liquidationPrice: String?
    var isLoading = false
}

final class PerpsLeverageVC: TradeValueSheetVC {
    var loadEstimate: ((Int) async throws -> PerpsOrderDisplayData.LeverageEstimate)?
    var onDismiss: (() -> Void)?
    let metrics: PerpsLeverageMetrics
    private var estimates: [Int: PerpsOrderDisplayData.LeverageEstimate]
    private(set) var estimateTask: Task<Void, Never>?
    private var requestedLeverage: Int?

    init(data: PerpsOrderDisplayData, onCommit: @escaping (Int) -> Void) {
        let range = data.leverageRange
        let scale = TradeSliderScale(minimum: Double(range.lowerBound), maximum: Double(range.upperBound),
            presets: [1, 2, 5, 10, 20, 50].filter(range.contains).map(Double.init),
            roundValue: { min(max($0.rounded(), Double(range.lowerBound)), Double(range.upperBound)) },
            stepValue: { value, increasing in
                min(max(value.rounded() + (increasing ? 1 : -1), Double(range.lowerBound)), Double(range.upperBound))
            })
        let slider = TradePresetSlider(scale: scale, value: Double(data.input.leverage)) {
            Int($0).formatted(.number.locale(.forNumberFormatters)) + "x"
        }
        slider.tintColor = AirTintColor
        slider.isEnabled = range.count > 1
        slider.accessibilityLabel = lang("Leverage")
        slider.accessibilityIdentifier = "perps.leverage.slider"
        estimates = data.leverageEstimate.map { [$0.leverage: $0] } ?? [:]
        let metrics = PerpsLeverageMetrics()
        self.metrics = metrics
        let accessory = HostingView {
            PerpsLeverageMetricsView(tokenName: data.token.name, price: data.price, metrics: metrics)
        }
        accessory.accessibilityIdentifier = "perps.leverage.metrics"
        super.init(configuration: .init(
            title: lang("Leverage"), unit: "x", unitFont: .compactRounded(ofSize: 40, weight: .bold), fractionDigits: 0,
            range: BigInt(range.lowerBound)...BigInt(range.upperBound), description: lang("$perps_leverage_disclaimer"),
            inputAccessibilityLabel: lang("Leverage"), accessibilityPrefix: "perps.leverage"
        ), value: BigInt(data.input.leverage), slider: slider, accessory: accessory, onCommit: { onCommit(Int($0)) })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    private var draftLeverage: Int? {
        isDraftValid ? draft.flatMap { Int(exactly: $0) } : nil
    }

    override func draftDidChange() {
        guard let leverage = draftLeverage else {
            cancelEstimate()
            metrics.liquidationPrice = nil
            return
        }
        guard requestedLeverage != leverage else { return }
        cancelEstimate()
        if let estimate = estimates[leverage] {
            metrics.liquidationPrice = estimate.liquidationPrice
            return
        }
        guard let loadEstimate else {
            metrics.liquidationPrice = nil
            return
        }
        metrics.isLoading = true
        requestedLeverage = leverage
        estimateTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
                let estimate = try await loadEstimate(leverage)
                guard !Task.isCancelled, let self, draftLeverage == leverage else { return }
                estimates[leverage] = estimate
                metrics.liquidationPrice = estimate.liquidationPrice
                metrics.isLoading = false
                requestedLeverage = nil
                estimateTask = nil
            } catch {
                guard !Task.isCancelled, let self, draftLeverage == leverage else { return }
                metrics.liquidationPrice = nil
                metrics.isLoading = false
                requestedLeverage = nil
                estimateTask = nil
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        draftDidChange()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        cancelEstimate()
        onDismiss?()
    }

    private func cancelEstimate() {
        estimateTask?.cancel()
        estimateTask = nil
        requestedLeverage = nil
        metrics.isLoading = false
    }
}

private struct PerpsLeverageMetricsView: View {
    let tokenName: String
    let price: String
    let metrics: PerpsLeverageMetrics

    var body: some View {
        WithPerceptionTracking {
            InsetSection(dividersTrailingInset: 16, horizontalPadding: 0) {
                AssetInfoMetricRow(title: L10n.perpsAssetPrice(asset: tokenName), value: price)
                AssetInfoMetricRow(title: lang("Liquidation Price"), info: lang("$perps_liquidation_price_hint"),
                                   value: metrics.liquidationPrice ?? (metrics.isLoading ? "" : "—"),
                                   valueColor: metrics.isLoading ? .air.secondaryLabel : .air.primaryLabel,
                                   isStale: metrics.isLoading)
                    .overlay(alignment: .trailing) {
                        if metrics.isLoading, metrics.liquidationPrice == nil {
                            WUIActivityIndicator(size: 16)
                                .foregroundStyle(Color.air.secondaryLabel)
                                .padding(.trailing, 16)
                                .accessibilityLabel(lang("Loading..."))
                        }
                    }
                    .accessibilityValue(metrics.isLoading ? lang("Loading...") : metrics.liquidationPrice ?? lang("Unavailable"))
                    .accessibilityIdentifier("perps.leverage.liquidationPrice")
            }
        }
    }
}
