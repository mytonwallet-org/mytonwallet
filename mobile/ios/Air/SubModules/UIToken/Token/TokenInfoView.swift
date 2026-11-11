import SwiftUI
import UIKit
import Flow
import UIComponents
import WalletContext
import WalletCore

enum TokenInfoState: Equatable {
    case loading
    case details(ApiTokenDetails)
    case summary(AssetInfoSummary)
    case fallback(String)
    case error

    static func resolved(details: ApiTokenDetails?) -> Self {
        guard let details, details.hasPublicInformation else {
            return .fallback(lang("$token_info_fallback_description"))
        }
        return .details(details)
    }

    var details: ApiTokenDetails? {
        guard case .details(let details) = self else { return nil }
        return details
    }

    var description: String? {
        switch self {
        case .loading, .error:
            nil
        case .details(let details):
            details.displayDescriptionText ?? lang("$token_info_no_description")
        case .summary(let summary):
            summary.description ?? lang("$token_info_no_description")
        case .fallback(let description):
            description
        }
    }

    var canExpand: Bool {
        switch self {
        case .details(let details): details.hasPublicInformation
        case .summary: true
        case .loading, .fallback, .error: false
        }
    }

    /// The asset has its own description, which the market layout can show in full.
    var hasDescription: Bool {
        switch self {
        case .details(let details): details.displayDescriptionText != nil
        case .summary(let summary): summary.description != nil
        case .loading, .fallback, .error: false
        }
    }

    var hasContent: Bool {
        switch self {
        case .details, .summary: true
        case .loading, .fallback, .error: false
        }
    }

    var isLoading: Bool {
        self == .loading
    }
}

struct TokenInfoPresentationSnapshot: Equatable {
    let state: TokenInfoState
    let hasBalance: Bool
    let showsFullDescription: Bool
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
    static let collapsedHeight = AssetInfoExpansion.collapsedHeight
    static let initialExpandedHeight = CGFloat(368)
    static let animationDuration = AssetInfoExpansion.animationDuration
    static let crossfadeDuration = AssetInfoExpansion.crossfadeDuration

    @Published private(set) var state: TokenInfoState
    @Published private(set) var isExpanded: Bool
    @Published private(set) var expansionProgress: CGFloat
    @Published private(set) var contentOpacity: CGFloat
    @Published private(set) var presentationOverlay: TokenInfoPresentationOverlay?
    @Published private(set) var presentationOverlayOpacity: CGFloat
    @Published private(set) var layoutRevision = 0
    @Published private(set) var showsOriginalDescription = false
    @Published private(set) var hasBalance: Bool
    @Published private(set) var showsFullDescription = false

    var measuredExpandedHeight = initialExpandedHeight
    private(set) var pendingPresentationRevision: Int?
    private(set) var isConfiguringState = false

    var onToggleRequested: (() -> Void)?
    private var presentationTask: Task<Void, Never>?
    private var preferredExpansion: Bool

    init(state: TokenInfoState = .loading, isExpanded: Bool? = nil, hasBalance: Bool = true) {
        let preferredExpansion = isExpanded ?? AppStorageHelper.isTokenInfoExpanded
        let isExpanded = state.canExpand && (!hasBalance || preferredExpansion)
        self.preferredExpansion = preferredExpansion
        self.hasBalance = hasBalance
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
            hasBalance: hasBalance,
            showsFullDescription: showsFullDescription,
            showsOriginalDescription: showsOriginalDescription,
            expansionProgress: expansionProgress,
            expandedHeight: measuredExpandedHeight
        )
    }
    func configure(state: TokenInfoState, hasBalance: Bool? = nil) {
        let hasBalance = hasBalance ?? self.hasBalance
        let ownershipChanged = self.hasBalance != hasBalance
        guard self.state != state || ownershipChanged else { return }
        // New values for the same rows keep the layout, so they replace the content in place.
        if !ownershipChanged, case .summary(let current) = self.state, case .summary(let next) = state,
           current.description == next.description, current.fields.map(\.id) == next.fields.map(\.id) {
            self.state = state
            return
        }
        presentationTask?.cancel()
        presentationTask = nil

        if state.isLoading {
            isConfiguringState = true
            defer { isConfiguringState = false }
            withTransaction(Transaction(animation: nil)) {
                self.state = state
                self.hasBalance = hasBalance
                showsFullDescription = false
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
            self.hasBalance = hasBalance
            if ownershipChanged {
                showsFullDescription = false
            }
            showsOriginalDescription = false
            if !state.canExpand {
                isExpanded = false
            } else if shouldRestoreExpansion || ownershipChanged {
                isExpanded = !hasBalance || preferredExpansion
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

    func toggleDescription() {
        guard !hasBalance, state.hasDescription else { return }
        presentationTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            presentationOverlay = .content(currentPresentationSnapshot)
            presentationOverlayOpacity = 1
            contentOpacity = 0
            showsFullDescription.toggle()
            layoutRevision &+= 1
            pendingPresentationRevision = layoutRevision
        }
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
                hasBalance: model.hasBalance,
                showsFullDescription: model.showsFullDescription,
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
                hasBalance: model.hasBalance,
                showsFullDescription: false,
                showsOriginalDescription: false,
                expansionProgress: 0,
                showsSkeleton: true,
                isInteractive: false
            )
        case .content(let snapshot):
            contentLayer(
                state: snapshot.state,
                hasBalance: snapshot.hasBalance,
                showsFullDescription: snapshot.showsFullDescription,
                showsOriginalDescription: snapshot.showsOriginalDescription,
                expansionProgress: snapshot.expansionProgress,
                showsSkeleton: false,
                isInteractive: false
            )
        case nil:
            EmptyView()
        }
    }

    @ViewBuilder
    private func contentLayer(
        state: TokenInfoState,
        hasBalance: Bool,
        showsFullDescription: Bool,
        showsOriginalDescription: Bool,
        expansionProgress: CGFloat,
        showsSkeleton: Bool,
        isInteractive: Bool
    ) -> some View {
        if !hasBalance, state.hasContent {
            marketContent(state, showsOriginalDescription: showsOriginalDescription, showsFullDescription: showsFullDescription)
                .allowsHitTesting(isInteractive)
                .accessibilityHidden(!isInteractive)
        } else {
            VStack(spacing: 0) {
                header(
                    state: state,
                    showsOriginalDescription: showsOriginalDescription,
                    expansionProgress: expansionProgress,
                    showsSkeleton: showsSkeleton,
                    isInteractive: isInteractive
                )

                if state.hasContent {
                    detailsContent(state, showsOriginalDescription: showsOriginalDescription)
                        .opacity(expansionProgress)
                        .allowsHitTesting(isInteractive && model.isExpanded)
                        .accessibilityHidden(!isInteractive || !model.isExpanded)
                }
            }
            .allowsHitTesting(isInteractive)
            .accessibilityHidden(!isInteractive)
        }
    }

    private func marketContent(
        _ state: TokenInfoState,
        showsOriginalDescription: Bool,
        showsFullDescription: Bool
    ) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lang("Info"))
                    .textStyle(.supporting)
                    .tracking(-0.154)
                    .foregroundStyle(Color.air.secondaryLabel)
                    .frame(height: 18, alignment: .leading)
                if let text = displayedDescription(state, showsOriginalDescription: showsOriginalDescription) {
                    AssetInfoDescriptionView(
                        text: text,
                        color: state.hasDescription ? Color.air.primaryLabel : Color.air.secondaryLabel,
                        canToggle: state.hasDescription,
                        showsFullDescription: showsFullDescription
                    ) {
                        model.requestToggle()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)

            detailsContent(state, showsOriginalDescription: showsOriginalDescription)
        }
    }

    @ViewBuilder
    private func detailsContent(
        _ state: TokenInfoState,
        showsOriginalDescription: Bool
    ) -> some View {
        switch state {
        case .details(let details):
            tokenDetailsContent(details, showsOriginalDescription: showsOriginalDescription)
        case .summary(let summary):
            if !summary.fields.isEmpty {
                VStack(spacing: 0) {
                    divider
                    fieldRows(summary.fields, isStale: summary.isStale)
                }
            }
        case .loading, .fallback, .error:
            EmptyView()
        }
    }

    private func tokenDetailsContent(
        _ details: ApiTokenDetails,
        showsOriginalDescription: Bool
    ) -> some View {
        let linkKinds: [ApiTokenDetails.Link.Kind] = [.x, .telegram, .website]
        let tokenLinks = linkKinds.flatMap { kind in details.links?.filter { $0.kind == kind } ?? [] }
        let fields = tokenFields(details)

        return VStack(spacing: 0) {
            if isUsingLocalizedDescription(details, showsOriginalDescription: showsOriginalDescription) {
                translationAttribution
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !tokenLinks.isEmpty {
                links(tokenLinks)
            }

            if !fields.isEmpty || details.volume24h != nil {
                divider
            }

            fieldRows(fields)

            if let volume24h = details.volume24h {
                if !fields.isEmpty {
                    divider
                }
                volume(volume24h)
            }
        }
    }

    private func fieldRows(_ fields: [AssetInfoField], isStale: Bool = false) -> some View {
        ForEach(Array(fields.enumerated()), id: \.element.id) { index, field in
            if index > 0 {
                divider
            }
            AssetInfoMetricRow(title: field.title, info: field.info, value: field.value, isStale: isStale)
        }
    }

    private func tokenFields(_ details: ApiTokenDetails) -> [AssetInfoField] {
        var fields: [AssetInfoField] = []
        if let marketCap = details.marketCap {
            fields.append(.init(id: "marketCap", title: lang("Market Cap"), info: lang("$token_info_market_cap_hint"),
                                value: formatCompactCurrency(marketCap, currency: details.volume24h?.currency ?? .USD)))
        }
        if let supply = supplyDetails(details) {
            fields.append(.init(id: "supply", title: supply.title, info: supply.info, value: supply.value))
        }
        if let createdAt = details.createdAt {
            fields.append(.init(id: "created", title: lang("Created"),
                                value: createdAt.formatted(.localizedDateTime.month(.abbreviated).day().year())))
        }
        return fields
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
                AssetInfoExpansionChevron(expansionProgress: expansionProgress)
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
        .padding(.bottom, 12)
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
        case .summary(let summary):
            descriptionStack(
                summary.description ?? lang("$token_info_no_description"),
                color: summary.description == nil ? Color.air.secondaryLabel : Color.air.primaryLabel,
                expansionProgress: expansionProgress
            )
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
        AssetInfoExpandableDescription(text: text, color: color, expansionProgress: expansionProgress)
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

    private func displayedDescription(
        _ state: TokenInfoState,
        showsOriginalDescription: Bool
    ) -> String? {
        switch state {
        case .details(let details):
            displayedDescription(details, showsOriginalDescription: showsOriginalDescription)
        case .summary(let summary):
            summary.description ?? lang("$token_info_no_description")
        case .loading, .fallback, .error:
            nil
        }
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
        AssetInfoDescriptionText(text: description, color: color, lineLimit: lineLimit)
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
                    HStack(spacing: 1) {
                        linkIcon(link.kind)
                            .frame(width: 28, height: 28)
                            .offset(x: layoutDirection == .leftToRight ? 3 : -3)
                            .frame(width: 34, height: 32)
                        Text(verbatim: linkTitle(link))
                            .textStyle(.supportingEmphasized)
                            .frame(height: 20)
                    }
                    .foregroundStyle(Color.air.primaryLabel)
                    .padding(.trailing, 12)
                    .frame(height: 32)
                    .background(Color.air.secondaryLabel.opacity(0.12), in: .capsule)
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
                "\(formatCompactNumber(circulating)) / \(formatCompactNumber(total))"
            )
        case let (.some(circulating), .none):
            return (lang("Circulating Supply"), nil, formatCompactNumber(circulating))
        case let (.none, .some(total)):
            return (lang("Total Supply"), nil, formatCompactNumber(total))
        case (.none, .none):
            return nil
        }
    }

    @ViewBuilder
    private func linkIcon(_ kind: ApiTokenDetails.Link.Kind) -> some View {
        switch kind {
        case .x:
            Image.airBundle("inline.x")
                .font(.system(size: 17))
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

    private func volume(_ volume: ApiTokenDetails.Volume) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Text(lang("Volume · 24h"))
                        .foregroundStyle(Color.air.secondaryLabel)
                    infoButton(
                        title: lang("Volume · 24h"),
                        message: lang("$token_info_volume_hint")
                    )
                }

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    Text(verbatim: formatCompactCurrency(volume.total, currency: volume.currency))
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
        AssetInfoSplitBar(
            positiveValue: volume.buy,
            negativeValue: volume.sell,
            positiveLabel: formatCompactCurrency(volume.buy, currency: volume.currency),
            negativeLabel: formatCompactCurrency(volume.sell, currency: volume.currency)
        )
    }

    private func infoButton(title: String, message: String) -> some View {
        AssetInfoHelpButton(title: title, message: message)
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

    private func formatCompactCurrency(_ value: Double, currency: MBaseCurrency) -> String {
        formatCompactNumber(value, currency: currency.sign)
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
