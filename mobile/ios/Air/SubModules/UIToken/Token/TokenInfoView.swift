import SwiftUI
import UIKit
import Flow
import UIComponents
import WalletContext
import WalletCore

enum TokenInfoState: Equatable {
    case hidden
    case loading
    case details(ApiTokenDetails)
    case fallback(String)
    case error

    static func resolved(details: ApiTokenDetails?) -> Self {
        guard let details else { return .hidden }
        return details.hasPublicInformation
            ? .details(details)
            : .fallback(lang("$token_info_fallback_description"))
    }

    var details: ApiTokenDetails? {
        guard case .details(let details) = self else { return nil }
        return details
    }

    var description: String? {
        switch self {
        case .hidden, .loading, .error:
            nil
        case .details(let details):
            details.displayDescriptionText ?? lang("$token_info_no_description")
        case .fallback(let description):
            description
        }
    }

    var canExpand: Bool {
        guard case .details(let details) = self else { return false }
        return details.hasPublicInformation
    }

    var isLoading: Bool {
        self == .loading
    }

    var isSectionVisible: Bool {
        self != .hidden
    }
}

struct TokenInfoPresentationSnapshot: Equatable {
    let state: TokenInfoState
    let showsOriginalDescription: Bool
    let expansionProgress: CGFloat
    let expandedHeight: CGFloat
}

enum TokenInfoPresentationOverlay: Equatable {
    case skeleton
    case content(TokenInfoPresentationSnapshot)
}

@MainActor
final class TokenInfoModel: ObservableObject {
    static let collapsedHeight = CGFloat(64)
    static let initialExpandedHeight = CGFloat(368)
    static let animationDuration = TimeInterval(0.45)
    static let crossfadeDuration = TimeInterval(0.2)

    @Published private(set) var state: TokenInfoState
    @Published private(set) var isExpanded: Bool
    @Published private(set) var expansionProgress: CGFloat
    @Published private(set) var contentOpacity: CGFloat
    @Published private(set) var presentationOverlay: TokenInfoPresentationOverlay?
    @Published private(set) var presentationOverlayOpacity: CGFloat
    @Published private(set) var layoutRevision = 0
    @Published private(set) var showsOriginalDescription = false

    var measuredExpandedHeight = initialExpandedHeight
    private(set) var pendingPresentationRevision: Int?
    private(set) var isConfiguringState = false

    var onToggleRequested: (() -> Void)?
    private var presentationTask: Task<Void, Never>?
    private var preferredExpansion: Bool

    init(state: TokenInfoState = .loading, isExpanded: Bool? = nil) {
        let preferredExpansion = isExpanded ?? AppStorageHelper.isTokenInfoExpanded
        let isExpanded = state.canExpand ? preferredExpansion : false
        self.preferredExpansion = preferredExpansion
        self.state = state
        self.isExpanded = isExpanded
        self.expansionProgress = isExpanded ? 1 : 0
        self.contentOpacity = state.isLoading ? 0 : 1
        self.presentationOverlay = nil
        self.presentationOverlayOpacity = 0
    }

    var canExpand: Bool { state.canExpand }
    var targetExpansionProgress: CGFloat { isExpanded && canExpand ? 1 : 0 }
    var currentPresentationSnapshot: TokenInfoPresentationSnapshot {
        TokenInfoPresentationSnapshot(
            state: state,
            showsOriginalDescription: showsOriginalDescription,
            expansionProgress: expansionProgress,
            expandedHeight: measuredExpandedHeight
        )
    }
    func configure(state: TokenInfoState) {
        guard self.state != state else { return }
        presentationTask?.cancel()
        presentationTask = nil

        if state.isLoading {
            isConfiguringState = true
            defer { isConfiguringState = false }
            withTransaction(Transaction(animation: nil)) {
                self.state = state
                showsOriginalDescription = false
                isExpanded = false
                expansionProgress = 0
                contentOpacity = 0
                presentationOverlay = nil
                presentationOverlayOpacity = 0
                pendingPresentationRevision = nil
                layoutRevision &+= 1
            }
            return
        }

        let previousState = self.state
        let previousSnapshot = currentPresentationSnapshot
        let overlay: TokenInfoPresentationOverlay = previousState.isLoading
            ? .skeleton
            : .content(previousSnapshot)
        let shouldRestoreExpansion = !previousState.canExpand && state.canExpand
        let revision = layoutRevision &+ 1

        isConfiguringState = true
        defer { isConfiguringState = false }
        withTransaction(Transaction(animation: nil)) {
            presentationOverlay = overlay
            presentationOverlayOpacity = 1
            contentOpacity = 0
            self.state = state
            showsOriginalDescription = false
            if !state.canExpand {
                isExpanded = false
            } else if shouldRestoreExpansion {
                isExpanded = preferredExpansion
            }
            pendingPresentationRevision = revision
            layoutRevision = revision
        }
    }

    func beginPresentationTransition(revision: Int, animated: Bool) {
        guard pendingPresentationRevision == revision else { return }
        pendingPresentationRevision = nil
        presentationTask?.cancel()

        guard animated, presentationOverlay != nil else {
            finishPresentationTransition()
            return
        }

        withAnimation(.easeInOut(duration: Self.crossfadeDuration)) {
            presentationOverlayOpacity = 0
            contentOpacity = 1
        }
        presentationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.crossfadeDuration))
            guard !Task.isCancelled else { return }
            self?.finishPresentationTransition()
        }
    }

    private func finishPresentationTransition() {
        withTransaction(Transaction(animation: nil)) {
            contentOpacity = 1
            presentationOverlayOpacity = 0
            presentationOverlay = nil
        }
        presentationTask = nil
    }

    func requestToggle() {
        onToggleRequested?()
    }

    func showOriginalDescription() {
        showsOriginalDescription = true
    }

    func setExpanded(_ isExpanded: Bool) {
        self.isExpanded = isExpanded
        preferredExpansion = isExpanded
        AppStorageHelper.isTokenInfoExpanded = isExpanded
    }

    func setExpansionProgress(_ expansionProgress: CGFloat) {
        let expansionProgress = min(max(expansionProgress, 0), 1)
        guard abs(self.expansionProgress - expansionProgress) > 0.001 else { return }
        self.expansionProgress = expansionProgress
    }

    @discardableResult
    func updateMeasuredExpandedHeight(_ height: CGFloat) -> Bool {
        let height = max(height, Self.collapsedHeight)
        guard canExpand, abs(measuredExpandedHeight - height) > 0.5 else { return false }
        measuredExpandedHeight = height
        return true
    }
}

private struct TokenInfoLayoutMeasurement: Equatable {
    let height: CGFloat
    let revision: Int
}

struct TokenInfoView: View {
    @ObservedObject var model: TokenInfoModel
    var onHeightChange: (CGFloat, Int) -> Void = { _, _ in }
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let layoutRevision = model.layoutRevision
        let isStaticLoading = model.state.isLoading && model.pendingPresentationRevision == nil
        return ZStack(alignment: .top) {
            contentLayer(
                state: model.state,
                showsOriginalDescription: model.showsOriginalDescription,
                expansionProgress: model.expansionProgress,
                showsSkeleton: isStaticLoading,
                isInteractive: model.presentationOverlay == nil
            )
            .opacity(isStaticLoading ? 1 : model.contentOpacity)
            .onGeometryChange(for: TokenInfoLayoutMeasurement.self, of: { proxy in
                TokenInfoLayoutMeasurement(
                    height: proxy.size.height,
                    revision: layoutRevision
                )
            }) { measurement in
                onHeightChange(measurement.height, measurement.revision)
            }

            // Measure the incoming layer directly. The outgoing layer may remain at its old
            // height during the crossfade without changing the target reported to UIKit.
            presentationOverlay
                .opacity(model.presentationOverlayOpacity)
        }
        .background(Color.air.groupedItem)
        .fixedSize(horizontal: false, vertical: true)
        // The UIKit host can still have the previous height while the new content is measured.
        .frame(minHeight: 0, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var presentationOverlay: some View {
        switch model.presentationOverlay {
        case .skeleton:
            contentLayer(
                state: .loading,
                showsOriginalDescription: false,
                expansionProgress: 0,
                showsSkeleton: true,
                isInteractive: false
            )
        case .content(let snapshot):
            contentLayer(
                state: snapshot.state,
                showsOriginalDescription: snapshot.showsOriginalDescription,
                expansionProgress: snapshot.expansionProgress,
                showsSkeleton: false,
                isInteractive: false
            )
        case nil:
            EmptyView()
        }
    }

    private func contentLayer(
        state: TokenInfoState,
        showsOriginalDescription: Bool,
        expansionProgress: CGFloat,
        showsSkeleton: Bool,
        isInteractive: Bool
    ) -> some View {
        VStack(spacing: 0) {
            header(
                state: state,
                showsOriginalDescription: showsOriginalDescription,
                expansionProgress: expansionProgress,
                showsSkeleton: showsSkeleton,
                isInteractive: isInteractive
            )

            if let details = state.details {
                detailsContent(details, showsOriginalDescription: showsOriginalDescription)
                    .opacity(expansionProgress)
                    .allowsHitTesting(isInteractive && model.isExpanded)
                    .accessibilityHidden(!isInteractive || !model.isExpanded)
            }
        }
        .allowsHitTesting(isInteractive)
        .accessibilityHidden(!isInteractive)
    }

    @ViewBuilder
    private func detailsContent(
        _ details: ApiTokenDetails,
        showsOriginalDescription: Bool
    ) -> some View {
        let tokenLinks = details.links?.filter { ![.documentation, .sourceCode].contains($0.kind) } ?? []
        let supply = supplyDetails(details)
        let hasMetrics = details.marketCap != nil || supply != nil || details.createdAt != nil || details.volume24h != nil

        VStack(spacing: 0) {
            if isUsingLocalizedDescription(details, showsOriginalDescription: showsOriginalDescription) {
                translationAttribution
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !tokenLinks.isEmpty {
                links(tokenLinks)
            }

            if hasMetrics {
                divider
            }

            if let marketCap = details.marketCap {
                detailRow(
                    title: lang("Market Cap"),
                    info: lang("$token_info_market_cap_hint"),
                    value: compactCurrency(marketCap, currency: details.volume24h?.currency ?? .USD)
                )
            }

            if let supply {
                if details.marketCap != nil {
                    divider
                }
                detailRow(title: supply.title, info: supply.info, value: supply.value)
            }

            if let createdAt = details.createdAt {
                if details.marketCap != nil || supply != nil {
                    divider
                }
                detailRow(
                    title: lang("Created"),
                    value: createdAt.formatted(.dateTime.month(.abbreviated).day().year())
                )
            }

            if let volume24h = details.volume24h {
                if details.marketCap != nil || supply != nil || details.createdAt != nil {
                    divider
                }
                volume(volume24h)
            }
        }
    }

    private func header(
        state: TokenInfoState,
        showsOriginalDescription: Bool,
        expansionProgress: CGFloat,
        showsSkeleton: Bool,
        isInteractive: Bool
    ) -> some View {
        let canExpand = state.canExpand
        return ZStack(alignment: .topTrailing) {
            headerLabels(
                state: state,
                showsOriginalDescription: showsOriginalDescription,
                expansionProgress: expansionProgress,
                showsSkeleton: showsSkeleton
            )
            if canExpand {
                chevron(expansionProgress: expansionProgress)
                    .transition(.opacity)
            }
        }
        .frame(minHeight: TokenInfoModel.collapsedHeight, alignment: .top)
        .contentShape(.rect)
        .onTapGesture {
            if isInteractive, canExpand {
                model.requestToggle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(canExpand ? .isButton : [])
        .accessibilityLabel(lang("Info"))
        .accessibilityValue(canExpand ? (model.isExpanded ? lang("Expanded") : lang("Collapsed")) : "")
        .accessibilityHint(canExpand ? (model.isExpanded ? lang("$token_info_collapse_hint") : lang("$token_info_expand_hint")) : "")
    }

    private func headerLabels(
        state: TokenInfoState,
        showsOriginalDescription: Bool,
        expansionProgress: CGFloat,
        showsSkeleton: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(lang("Info"))
                .textStyle(.supporting)
                .tracking(-0.154)
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(height: 18, alignment: .topLeading)

            ZStack(alignment: .topLeading) {
                if showsSkeleton {
                    loadingPlaceholder
                        .skeletonContainer(
                            isActive: true,
                            shimmerReferenceHeight: TokenInfoModel.collapsedHeight
                        )
                }

                statePresentation(
                    state: state,
                    showsOriginalDescription: showsOriginalDescription,
                    expansionProgress: expansionProgress
                )
                .opacity(showsSkeleton ? 0 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, 12)
        .padding(.bottom, 15)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var loadingPlaceholder: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.air.groupedBackground.opacity(0.5))
            .frame(width: 184, height: 13)
            .frame(height: 19)
            .skeleton(cornerRadius: 4)
    }

    @ViewBuilder
    private func statePresentation(
        state: TokenInfoState,
        showsOriginalDescription: Bool,
        expansionProgress: CGFloat
    ) -> some View {
        switch state {
        case .hidden:
            EmptyView()
        case .loading:
            Color.clear.frame(height: 19)
        case .details(let details):
            if let description = displayedDescription(
                details,
                showsOriginalDescription: showsOriginalDescription
            ) {
                descriptionStack(
                    description,
                    color: details.displayDescriptionText == nil ? Color.air.secondaryLabel : Color.air.primaryLabel,
                    expansionProgress: expansionProgress
                )
            }
        case .fallback(let text):
            description(text, lineLimit: 1, color: Color.air.secondaryLabel)
        case .error:
            description(lang("No Data"), lineLimit: 1, color: Color.air.secondaryLabel)
        }
    }

    private func descriptionStack(
        _ text: String,
        color: Color,
        expansionProgress: CGFloat
    ) -> some View {
        ZStack(alignment: .topLeading) {
            description(text, lineLimit: nil, color: color)
                .opacity(expansionProgress)

            description(text, lineLimit: 1, color: color)
                .opacity(1 - expansionProgress)
        }
        .padding(.trailing, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var translationAttribution: some View {
        HStack(spacing: 4) {
            Text(lang("Translated from English"))
                .foregroundStyle(Color.air.secondaryLabel)
            Button(lang("Show Original")) {
                model.showOriginalDescription()
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(uiColor: .tintColor))
        }
        .textStyle(.footnote)
    }

    private func chevron(expansionProgress: CGFloat) -> some View {
        Image(systemName: "chevron.down")
            .textStyle(.badgeBold, content: .technical)
            .foregroundStyle(Color.air.primaryLabel.opacity(0.3))
            .frame(width: 24, height: 24)
            .rotationEffect(.degrees(chevronRotation(expansionProgress: expansionProgress)))
            .padding(.top, 20)
            .padding(.trailing, 12)
    }

    private func chevronRotation(expansionProgress: CGFloat) -> Double {
        let direction = layoutDirection == .leftToRight ? -1.0 : 1.0
        return direction * 180 * Double(expansionProgress)
    }

    private func displayedDescription(
        _ details: ApiTokenDetails,
        showsOriginalDescription: Bool
    ) -> String? {
        showsOriginalDescription
            ? details.originalDescriptionText ?? lang("$token_info_no_description")
            : details.displayDescriptionText ?? lang("$token_info_no_description")
    }

    private func isUsingLocalizedDescription(
        _ details: ApiTokenDetails,
        showsOriginalDescription: Bool
    ) -> Bool {
        !showsOriginalDescription
            && details.localizedDescriptionText != nil
            && details.originalDescriptionText != nil
    }

    private func description(
        _ description: String,
        lineLimit: Int?,
        color: Color = Color.air.primaryLabel
    ) -> some View {
        Text(verbatim: description)
            .textStyle(.callout)
            .tracking(-0.12)
            .lineSpacing(3)
            .foregroundStyle(color)
            .lineLimit(lineLimit)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func links(_ links: [ApiTokenDetails.Link]) -> some View {
        HFlow(
            alignment: .center,
            itemSpacing: 8,
            rowSpacing: 8,
            justified: false,
            distributeItemsEvenly: false
        ) {
            ForEach(links) { link in
                Button {
                    AppActions.openInBrowser(link.url)
                } label: {
                    HStack(spacing: 4) {
                        linkIcon(link.kind)
                        Text(verbatim: linkTitle(link))
                            .textStyle(.supportingEmphasized)
                    }
                    .foregroundStyle(Color.air.primaryLabel)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.air.secondaryFill, in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityHint(lang("$token_info_open_in_browser_hint"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func supplyDetails(_ details: ApiTokenDetails) -> (title: String, info: String?, value: String)? {
        let info = lang("$token_info_supply_hint")
        switch (details.circulatingSupply, details.totalSupply) {
        case let (.some(circulating), .some(total)):
            return (
                lang("Circulating / Total Supply"),
                info,
                "\(compactNumber(circulating)) / \(compactNumber(total))"
            )
        case let (.some(circulating), .none):
            return (lang("Circulating Supply"), nil, compactNumber(circulating))
        case let (.none, .some(total)):
            return (lang("Total Supply"), nil, compactNumber(total))
        case (.none, .none):
            return nil
        }
    }

    @ViewBuilder
    private func linkIcon(_ kind: ApiTokenDetails.Link.Kind) -> some View {
        switch kind {
        case .x:
            Image.airBundle("inline.x")
                .font(.system(size: 20))
                .imageScale(.medium)
                .foregroundStyle(Color.air.primaryLabel)
        case .telegram:
            Image.airBundle("inline.telegram")
                .font(.system(size: 20))
                .imageScale(.medium)
                .foregroundStyle(Color.air.primaryLabel)
        case .website, .documentation, .sourceCode, .aggregator:
            Image(systemName: "globe")
                .textStyle(.body, content: .technical)
                .imageScale(.medium)
        }
    }

    private func linkTitle(_ link: ApiTokenDetails.Link) -> String {
        switch link.kind {
        case .x, .telegram, .aggregator:
            link.title
        case .website:
            lang("Website")
        case .documentation:
            lang("Documentation")
        case .sourceCode:
            lang("Source Code")
        }
    }

    private func detailRow(title: String, info: String? = nil, value: String) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(verbatim: title)
                    .textStyle(.body)
                    .foregroundStyle(Color.air.secondaryLabel)

                if let info {
                    InfoButton(title: title, message: info, offset: .zero)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Text(verbatim: value)
                .textStyle(.body, content: .technical)
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private func volume(_ volume: ApiTokenDetails.Volume) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(lang("Volume · 24h"))
                        .foregroundStyle(Color.air.secondaryLabel)
                    InfoButton(
                        title: lang("Volume · 24h"),
                        message: lang("$token_info_volume_hint"),
                        offset: .zero
                    )
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Text(verbatim: compactCurrency(volume.total, currency: volume.currency))
                        .textStyle(.body, content: .technical)
                        .foregroundStyle(Color.air.primaryLabel)
                    if let change = volume.change {
                        Text(verbatim: formatPercent(change))
                            .textStyle(.supporting, content: .technical)
                            .foregroundStyle(change >= 0 ? Color.air.positiveAmount : Color.air.negativeAmount)
                    }
                }
            }
            .textStyle(.body)
            .padding(.horizontal, 16)
            .frame(height: 48)

            volumeBar(volume)
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
        }
        .frame(height: 90)
    }

    private func volumeBar(_ volume: ApiTokenDetails.Volume) -> some View {
        GeometryReader { proxy in
            let buyValue = compactCurrency(volume.buy, currency: volume.currency)
            let sellValue = compactCurrency(volume.sell, currency: volume.currency)
            let layout = TokenInfoVolumeBarLayout.resolve(
                buy: volume.buy,
                sell: volume.sell,
                width: proxy.size.width,
                buyLabelWidth: volumeLabelWidth(buyValue),
                sellLabelWidth: volumeLabelWidth(sellValue)
            )

            HStack(spacing: layout.spacing) {
                if let buyWidth = layout.buyWidth {
                    barSegment(
                        value: buyValue,
                        color: Color.air.positiveAmount,
                        width: buyWidth,
                        isLeading: true,
                        isStandalone: layout.sellWidth == nil
                    )
                }
                if let sellWidth = layout.sellWidth {
                    barSegment(
                        value: sellValue,
                        color: Color.air.negativeAmount,
                        width: sellWidth,
                        isLeading: false,
                        isStandalone: layout.buyWidth == nil
                    )
                }
            }
        }
        .frame(height: 26)
    }

    private func volumeLabelWidth(_ value: String) -> CGFloat {
        ceil((value as NSString).size(withAttributes: [
            .font: WTypography.uiFont(.footnoteEmphasized, content: .technical),
        ]).width)
    }

    private func barSegment(
        value: String,
        color: Color,
        width: CGFloat,
        isLeading: Bool,
        isStandalone: Bool
    ) -> some View {
        ZStack(alignment: isLeading ? .leading : .trailing) {
            color
            LinearGradient(
                colors: [.white.opacity(0.15), .white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(verbatim: value)
                .textStyle(.footnoteEmphasized, content: .technical)
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, TokenInfoVolumeBarLayout.labelHorizontalPadding)
        }
        .frame(width: width, height: 26)
        .clipShape(TokenInfoVolumeSegmentShape(
            isLeading: isLeading,
            isStandalone: isStandalone,
            layoutDirection: layoutDirection
        ))
    }

    private var divider: some View {
        Color.clear
            .frame(height: 0)
            .overlay {
                Rectangle()
                    .fill(Color(uiColor: .separator))
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }
    }

    private func compactCurrency(_ value: Double, currency: MBaseCurrency) -> String {
        let number = compactNumber(value)
        return currency.sign.count == 1 && currency.sign != "₽"
            ? "\(currency.sign)\(number)"
            : "\(number) \(currency.sign)"
    }

    private func compactNumber(_ value: Double) -> String {
        let magnitude = abs(value)
        let (scaled, suffix): (Double, String) = if magnitude >= 1_000_000_000 {
            (value / 1_000_000_000, "B")
        } else if magnitude >= 1_000_000 {
            (value / 1_000_000, "M")
        } else if magnitude >= 1_000 {
            (value / 1_000, "K")
        } else {
            (value, "")
        }

        return scaled.formatted(
            .number
                .locale(LocalizationSupport.shared.locale)
                .precision(.fractionLength(0...2))
        ) + suffix
    }
}

extension ApiTokenDetails {
    var originalDescriptionText: String? {
        description?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var localizedDescriptionText: String? {
        localizedDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    var displayDescriptionText: String? {
        localizedDescriptionText ?? originalDescriptionText
    }

    var hasPublicInformation: Bool {
        displayDescriptionText != nil
            || links?.isEmpty == false
            || marketCap != nil
            || circulatingSupply != nil
            || totalSupply != nil
            || createdAt != nil
            || volume24h != nil
    }
}

struct TokenInfoVolumeBarLayout: Equatable {
    static let segmentSpacing = CGFloat(4)
    static let labelHorizontalPadding = CGFloat(8)

    let buyWidth: CGFloat?
    let sellWidth: CGFloat?
    let spacing: CGFloat

    static func resolve(
        buy: Double,
        sell: Double,
        width: CGFloat,
        buyLabelWidth: CGFloat,
        sellLabelWidth: CGFloat
    ) -> Self {
        let buy = max(0, buy)
        let sell = max(0, sell)
        let width = max(0, width)

        if buy == 0, sell > 0 {
            return Self(buyWidth: nil, sellWidth: width, spacing: 0)
        }
        if sell == 0, buy > 0 {
            return Self(buyWidth: width, sellWidth: nil, spacing: 0)
        }

        let availableWidth = max(0, width - segmentSpacing)
        if buy == 0, sell == 0 {
            return Self(
                buyWidth: availableWidth / 2,
                sellWidth: availableWidth / 2,
                spacing: segmentSpacing
            )
        }

        let rawBuyWidth = availableWidth * buy / (buy + sell)
        let buyMinimumWidth = buyLabelWidth + 2 * labelHorizontalPadding
        let sellMinimumWidth = sellLabelWidth + 2 * labelHorizontalPadding
        let buyWidth: CGFloat
        if buyMinimumWidth + sellMinimumWidth <= availableWidth {
            buyWidth = min(
                max(rawBuyWidth, buyMinimumWidth),
                availableWidth - sellMinimumWidth
            )
        } else {
            buyWidth = availableWidth * buyMinimumWidth / (buyMinimumWidth + sellMinimumWidth)
        }

        return Self(
            buyWidth: buyWidth,
            sellWidth: availableWidth - buyWidth,
            spacing: segmentSpacing
        )
    }
}

private struct TokenInfoVolumeSegmentShape: Shape {
    let isLeading: Bool
    let isStandalone: Bool
    let layoutDirection: LayoutDirection

    func path(in rect: CGRect) -> Path {
        let outerRadius = rect.height / 2
        let innerRadius = min(CGFloat(3), outerRadius)
        let isOuterOnLeft = isLeading == (layoutDirection == .leftToRight)
        let leftRadius = isStandalone || isOuterOnLeft ? outerRadius : innerRadius
        let rightRadius = isStandalone || !isOuterOnLeft ? outerRadius : innerRadius

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + leftRadius, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - rightRadius, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rightRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rightRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - rightRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + leftRadius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - leftRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + leftRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + leftRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

#if DEBUG
#Preview("Expanded") {
    let model = TokenInfoModel(isExpanded: true)
    return TokenInfoView(model: model)
        .padding(.vertical, 16)
        .background(Color.air.groupedBackground)
        .task {
            if let details = try? await Api.fetchTokenDetails(asset: "mock", slug: "mock") {
                model.configure(state: .details(details))
            }
        }
}
#endif
