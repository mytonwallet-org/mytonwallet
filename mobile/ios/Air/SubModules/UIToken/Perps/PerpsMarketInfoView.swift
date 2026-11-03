import SwiftUI
import UIKit
import UIComponents
import WalletContext
import WalletCore

/// As on the token page, content is measured at full size and UIKit animates its clipping viewport.
@MainActor
final class PerpsMarketInfoView: UIView {
    var onHeightChange: (() -> Void)?
    private let model: PerpsMarketInfoModel
    private var hostingView: HostingView!
    private var hostingHeight: NSLayoutConstraint!
    private var viewportHeight: NSLayoutConstraint!
    private var collapsedHeight = AssetInfoExpansion.collapsedHeight
    private var expandedHeight = AssetInfoExpansion.collapsedHeight
    private let headerButton = UIButton(type: .custom)
    private var headerButtonHeight: NSLayoutConstraint?
    private var measuredHeaderHeight = AssetInfoExpansion.collapsedHeight
    private var heightAnimator: ValueAnimator?

    init(data: PerpsMarketDisplayData, collapsesMetrics: Bool = false, isExpanded: Bool? = nil) {
        model = PerpsMarketInfoModel(data: data, collapsesMetrics: collapsesMetrics, isExpanded: isExpanded)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .air.groupedItem
        layer.cornerRadius = S.homeInsetSectionCornerRadius
        clipsToBounds = true
        accessibilityIdentifier = "Perps.Info"
        model.onToggle = { [weak self] in self?.toggleExpanded() }
        hostingView = HostingView { [weak self, model] in
            PerpsMarketInfoContent(model: model, onHeightChange: { [weak self] height, expanded in
                // Defer measurements so SwiftUI cannot invalidate Auto Layout during a sizing pass.
                Task { @MainActor [weak self] in
                    self?.updateMeasurement(height, expanded: expanded)
                }
            }, onHeaderHeightChange: { [weak self] height in
                Task { @MainActor [weak self] in
                    self?.measuredHeaderHeight = height
                    self?.updateHeaderButton()
                }
            })
        }
        addSubview(hostingView)
        hostingHeight = hostingView.heightAnchor.constraint(equalToConstant: expandedHeight)
        viewportHeight = heightAnchor.constraint(equalToConstant: collapsedHeight)
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingHeight, viewportHeight,
        ])
        if collapsesMetrics {
            headerButton.translatesAutoresizingMaskIntoConstraints = false
            headerButton.accessibilityIdentifier = "Perps.Info.ShowMore"
            headerButton.accessibilityLabel = lang("Info")
            headerButton.addAction(UIAction { [weak self] _ in self?.toggleExpanded() }, for: .touchUpInside)
            addSubview(headerButton)
            let height = headerButton.heightAnchor.constraint(equalToConstant: collapsedHeight)
            headerButtonHeight = height
            NSLayoutConstraint.activate([
                headerButton.topAnchor.constraint(equalTo: topAnchor),
                headerButton.leadingAnchor.constraint(equalTo: leadingAnchor),
                headerButton.trailingAnchor.constraint(equalTo: trailingAnchor),
                height,
            ])
            updateHeaderButton()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            heightAnimator?.invalidate()
            heightAnimator = nil
            setHeight(targetHeight, progress: model.isExpanded ? 1 : 0)
        }
    }

    func configure(data: PerpsMarketDisplayData) {
        let info = PerpsMarketInfoModel.Info(data)
        if model.info != info { model.info = info }
    }

    private var targetHeight: CGFloat { model.isExpanded ? expandedHeight : collapsedHeight }

    func toggleExpanded() {
        guard heightAnimator == nil else { return }
        model.isExpanded.toggle()
        AppStorageHelper.isTokenInfoExpanded = model.isExpanded
        updateHeight(animated: true)
    }

    private func updateMeasurement(_ height: CGFloat, expanded: Bool) {
        let height = max(AssetInfoExpansion.collapsedHeight, height)
        let previousTarget = targetHeight
        if expanded {
            expandedHeight = height
        } else if !model.collapsesMetrics {
            collapsedHeight = height
        }
        hostingHeight.constant = max(expandedHeight, collapsedHeight)
        guard abs(targetHeight - previousTarget) > 0.5 else { return }
        updateHeight(animated: heightAnimator != nil)
    }

    private func updateHeight(animated: Bool) {
        heightAnimator?.invalidate()
        heightAnimator = nil
        let targetProgress: CGFloat = model.isExpanded ? 1 : 0
        guard animated, window != nil, AppStorageHelper.animations, !UIAccessibility.isReduceMotionEnabled else {
            setHeight(targetHeight, progress: targetProgress)
            return
        }
        let startProgress = model.expansionProgress
        let finalHeight = targetHeight
        let animator = AssetInfoExpansion.animator(from: viewportHeight.constant, to: finalHeight)
        heightAnimator = animator
        animator.addUpdateBlock { [weak self] progress, height in
            self?.setHeight(height, progress: startProgress + (targetProgress - startProgress) * progress)
        }
        animator.addCompletionBlock { [weak self, weak animator] in
            guard let self, heightAnimator === animator else { return }
            setHeight(finalHeight, progress: targetProgress)
            heightAnimator = nil
        }
        animator.start()
    }

    private func setHeight(_ height: CGFloat, progress: CGFloat) {
        let changed = abs(viewportHeight.constant - height) > 0.01
        viewportHeight.constant = height
        model.expansionProgress = progress
        updateHeaderButton()
        if changed { onHeightChange?() }
    }

    private func updateHeaderButton() {
        headerButtonHeight?.constant = min(measuredHeaderHeight, viewportHeight.constant)
        headerButton.accessibilityValue = lang(model.isExpanded ? "Expanded" : "Collapsed")
        headerButton.accessibilityHint = lang(model.isExpanded ? "$token_info_collapse_hint" : "$token_info_expand_hint")
    }
}

@MainActor
private final class PerpsMarketInfoModel: ObservableObject {
    struct Info: Equatable {
        let description: String
        let fundingRate: String?
        let maxLeverage: String?
        let volume24h: String?
        let openInterest: String?
        let distribution: PerpsMarketDisplayData.InterestDistribution?
        let isStale: Bool

        init(_ data: PerpsMarketDisplayData) {
            description = data.description.trimmingCharacters(in: .whitespacesAndNewlines)
            fundingRate = data.fundingRate
            maxLeverage = data.maxLeverage
            volume24h = data.volume24h
            openInterest = data.openInterest
            distribution = data.distribution
            isStale = data.isStale
        }
    }

    @Published var info: Info
    @Published var isExpanded = false
    @Published var expansionProgress: CGFloat = 0
    let collapsesMetrics: Bool
    var onToggle: (() -> Void)?

    init(data: PerpsMarketDisplayData, collapsesMetrics: Bool, isExpanded: Bool?) {
        info = Info(data)
        self.collapsesMetrics = collapsesMetrics
        self.isExpanded = isExpanded ?? AppStorageHelper.isTokenInfoExpanded
        expansionProgress = self.isExpanded ? 1 : 0
    }
}

private struct PerpsMarketInfoContent: View {
    @ObservedObject var model: PerpsMarketInfoModel
    let onHeightChange: (CGFloat, Bool) -> Void
    let onHeaderHeightChange: (CGFloat) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if model.collapsesMetrics {
                VStack(spacing: 0) {
                    expandableHeader
                    metrics
                        .opacity(model.expansionProgress)
                        .allowsHitTesting(model.isExpanded)
                        .accessibilityHidden(!model.isExpanded)
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
                    onHeightChange($0, true)
                }
            } else {
                // Measure both descriptions before a tap. Neither layer reflows during the height animation.
                marketContent(expanded: false)
                    .opacity(1 - model.expansionProgress)
                marketContent(expanded: true)
                    .opacity(model.expansionProgress)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
    }

    private var expandableHeader: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                title
                AssetInfoExpandableDescription(text: descriptionText, color: descriptionColor,
                                               expansionProgress: model.expansionProgress)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            AssetInfoExpansionChevron(expansionProgress: model.expansionProgress)
        }
        .frame(minHeight: AssetInfoExpansion.collapsedHeight, alignment: .top)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }, action: onHeaderHeightChange)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func marketContent(expanded: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                title
                AssetInfoDescriptionView(
                    text: descriptionText, color: descriptionColor,
                    canToggle: !model.info.description.isEmpty, showsFullDescription: expanded,
                    accessibilityIdentifier: "Perps.Info.ShowMore"
                ) { model.onToggle?() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            metrics
        }
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) {
            onHeightChange($0, expanded)
        }
        .allowsHitTesting(expanded == model.isExpanded)
        .accessibilityHidden(expanded != model.isExpanded)
    }

    private var descriptionText: String {
        model.info.description.isEmpty ? lang("$token_info_no_description") : model.info.description
    }

    private var descriptionColor: Color {
        model.info.description.isEmpty ? .air.secondaryLabel : .air.primaryLabel
    }

    private var title: some View {
        Text(lang("Info"))
            .textStyle(.supporting)
            .tracking(-0.154)
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(height: 18, alignment: .leading)
    }

    private var metrics: some View {
        VStack(spacing: 0) {
            divider
            AssetInfoMetricRow(title: lang("Funding Rate"), info: lang("$perps_funding_rate_hint"),
                               value: model.info.fundingRate ?? "—", isStale: model.info.isStale)
            divider
            AssetInfoMetricRow(title: lang("Max Leverage"), info: lang("$perps_max_leverage_hint"),
                               value: model.info.maxLeverage ?? "—", isStale: model.info.isStale)
            divider
            AssetInfoMetricRow(title: lang("24h Volume"), info: lang("$perps_volume_24h_hint"),
                               value: model.info.volume24h ?? "—", isStale: model.info.isStale)
            divider
            AssetInfoMetricRow(title: lang("Open Interest"), info: lang("$perps_open_interest_hint"),
                               value: model.info.openInterest ?? "—", isStale: model.info.isStale)
            if let distribution = model.info.distribution {
                AssetInfoSplitBar(positiveValue: distribution.longValue, negativeValue: distribution.shortValue,
                                  positiveLabel: distribution.longLabel, negativeLabel: distribution.shortLabel)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
        }
    }

    private var divider: some View { Divider().padding(.horizontal, 16) }
}
