import SwiftUI
import UIComponents
import UIKit
import WalletContext
import WalletCore

@MainActor
final class MarketScreenModel: ObservableObject {
    typealias FetchAssets = @Sendable (String) async throws -> ApiMarketAssetsResponse
    typealias LoadCachedAssets = @Sendable (String) async -> ApiMarketAssetsResponse?

    private static let refreshInterval: TimeInterval = 5 * 60

    @Published private(set) var scrollToTopRequest = 0
    @Published private(set) var sections: [MarketSection] = []

    private let langCode: String
    private let fetchAssets: FetchAssets
    private let loadCachedAssets: LoadCachedAssets
    private let now: @Sendable () -> Date
    private var marketResponse: ApiMarketAssetsResponse?
    private var initialContentTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var buildTask: Task<Void, Never>?
    private var lastFetchedAt: Date?
    private var hasStarted = false

    init(
        langCode: String = LocalizationSupport.shared.langCode,
        fetchAssets: @escaping FetchAssets = { try await Api.fetchMarketAssets(langCode: $0) },
        loadCachedAssets: @escaping LoadCachedAssets = { await Api.cachedMarketAssets(langCode: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.langCode = langCode
        self.fetchAssets = fetchAssets
        self.loadCachedAssets = loadCachedAssets
        self.now = now
    }

    isolated deinit {
        initialContentTask?.cancel()
        fetchTask?.cancel()
        buildTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        initialContentTask = Task { [weak self, langCode, loadCachedAssets] in
            let cachedResponse = await loadCachedAssets(langCode)
            guard !Task.isCancelled, let self else { return }

            if self.marketResponse == nil {
                self.marketResponse = cachedResponse
                self.rebuildSections()
            }
            self.initialContentTask = nil
        }
        fetchIfNeeded()
    }

    func scrollToTop() {
        scrollToTopRequest += 1
    }

    func reloadTokens() {
        guard hasStarted else { return }
        rebuildSections()
        fetchIfNeeded()
    }

    private func fetchIfNeeded() {
        guard fetchTask == nil else { return }
        if let lastFetchedAt,
           now().timeIntervalSince(lastFetchedAt) < Self.refreshInterval {
            return
        }

        fetchTask = Task { [weak self, fetchAssets, langCode] in
            do {
                let response = try await fetchAssets(langCode)
                guard !Task.isCancelled, let self else { return }
                self.lastFetchedAt = self.now()
                self.marketResponse = response
                self.rebuildSections()
            } catch {
                // Keep the cached response, or the initial samples before the first response.
            }
            self?.fetchTask = nil
        }
    }

    private func rebuildSections() {
        buildTask?.cancel()
        let response = marketResponse
        buildTask = Task { [weak self] in
            let sections = if let response {
                await MarketSectionBuilder.build(from: response)
            } else {
                await MarketSection.samples()
            }
            guard !Task.isCancelled, let self else { return }
            self.sections = sections
            self.buildTask = nil
        }
    }
}

struct MarketScreen: View {
    @ObservedObject var model: MarketScreenModel
    let onScrollOffsetChange: (CGFloat) -> Void
    let onSeeAll: (MarketSection) -> Void
    let onSelectToken: (MarketToken) -> Void

    @Namespace private var scrollCoordinateSpace

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(model.sections) { section in
                        MarketSectionView(
                            section: section,
                            onSeeAll: { onSeeAll(section) },
                            onSelectToken: onSelectToken
                        )
                        .id(section.id)
                    }

                    Color.clear.frame(height: 86)
                }
                .padding(.top, 14)
                .scrollPosition(ns: scrollCoordinateSpace, callback: onScrollOffsetChange)
            }
            .coordinateSpace(name: scrollCoordinateSpace)
            .background(Color.air.groupedBackground)
            .onChange(of: model.scrollToTopRequest) { _ in
                guard let firstSection = model.sections.first else { return }
                withAnimation {
                    proxy.scrollTo(firstSection.id, anchor: .top)
                }
            }
        }
        .background(Color.air.groupedBackground)
    }
}

private struct MarketSectionView: View {
    let section: MarketSection
    let onSeeAll: () -> Void
    let onSelectToken: (MarketToken) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MarketSectionHeader(
                title: section.title,
                showsSeeAll: section.showsSeeAll,
                onSeeAll: onSeeAll
            )

            switch section.layout {
            case .largeHorizontal:
                MarketMoverCarousel(tokens: section.visibleTokens, onSelectToken: onSelectToken)

            case .grid:
                MarketGrid(tokens: section.visibleTokens, onSelectToken: onSelectToken)
                    .padding(.horizontal, 16)

            case .rows:
                MarketRows(tokens: section.visibleTokens, onSelectToken: onSelectToken)
                    .padding(.horizontal, 16)
            }
        }
    }
}

private struct MarketMoverCarousel: View {
    let tokens: [MarketToken]
    let onSelectToken: (MarketToken) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            if IOS_26_MODE_ENABLED, #available(iOS 26, iOSApplicationExtension 26, *) {
                GlassEffectContainer(spacing: 16) {
                    cards(usesLiquidGlass: true)
                }
            } else {
                cards(usesLiquidGlass: false)
            }
        }
        .backportScrollClipDisabled()
    }

    private func cards(usesLiquidGlass: Bool) -> some View {
        LazyHStack(spacing: 16) {
            ForEach(tokens) { token in
                Button {
                    onSelectToken(token)
                } label: {
                    MarketMoverCard(token: token, usesLiquidGlass: usesLiquidGlass)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct MarketSectionHeader: View {
    let title: String
    let showsSeeAll: Bool
    let onSeeAll: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .textStyle(.bodyStrong, scaling: .dynamic)
                .foregroundStyle(Color.air.secondaryLabel)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)

            if showsSeeAll {
                Button(action: onSeeAll) {
                    Text(lang("See All"))
                        .textStyle(.supporting, scaling: .dynamic)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.air.tint)
            }
        }
        .padding(.horizontal, 32)
        .frame(minHeight: 39)
    }
}

private struct MarketMoverCard: View {
    let token: MarketToken
    let usesLiquidGlass: Bool

    var body: some View {
        Group {
            if usesLiquidGlass, #available(iOS 26, iOSApplicationExtension 26, *) {
                content
                    .clipShape(.rect(cornerRadius: 32))
                    .glassEffect(.regular.interactive(true), in: .rect(cornerRadius: 32))
            } else {
                content
                    .background(Color.air.groupedItem)
                    .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.air.separator.opacity(0.55), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.02), radius: 7.5, y: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(token.name), \(token.priceText ?? ""), \(token.changeText)")
    }

    private var content: some View {
        ZStack(alignment: .top) {
            if let chart = token.chart {
                Color(rgb: chart.tint)
                    .opacity(0.06)

                VStack(spacing: 0) {
                    Spacer()
                    chartView(chart)
                }
            }

            VStack(spacing: 0) {
                MarketTokenIcon(token: token.token, size: 44, shouldShowChain: true)
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .padding(.top, 16)

                Text(token.name)
                    .textStyle(.calloutStrong, scaling: .dynamic)
                    .foregroundStyle(Color.air.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: 144)
                    .padding(.top, 8)

                HStack(spacing: 4) {
                    if let price = token.priceText {
                        Text(price)
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                    Text(token.changeText)
                        .foregroundStyle(token.isPositive ? Color.air.positiveAmount : Color.air.negativeAmount)
                }
                .textStyle(.supporting, content: .technical, scaling: .dynamic)
                .padding(.top, 1)
            }
        }
        .frame(width: 160, height: 160)
    }

    @ViewBuilder
    private func chartView(_ chart: MarketToken.Chart) -> some View {
        switch chart {
        case .bundled(let fillImageName, let lineImageName, _):
            ZStack(alignment: .top) {
                Image.airBundle(fillImageName)
                    .resizable()
                    .frame(width: 160, height: 40)
                Image.airBundle(lineImageName)
                    .resizable()
                    .frame(width: 161.5, height: 24.5)
            }
            .frame(width: 160, height: 40, alignment: .top)
            .clipped()

        case .sparkline(let points, let tint):
            MarketSparkline(points: points, tint: Color(rgb: tint))
                .frame(width: 160, height: 42)
        }
    }
}

private struct MarketSparkline: View {
    let points: [Double]
    let tint: Color

    var body: some View {
        ZStack {
            MarketSparklineShape(points: points, closesToBottom: true)
                .fill(tint.opacity(0.09))
            MarketSparklineShape(points: points, closesToBottom: false)
                .stroke(
                    tint,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )
        }
    }
}

private struct MarketSparklineShape: Shape {
    let points: [Double]
    let closesToBottom: Bool

    func path(in rect: CGRect) -> Path {
        guard points.count >= 2 else { return Path() }

        var path = Path()
        for (index, point) in points.enumerated() {
            let progress = CGFloat(index) / CGFloat(points.count - 1)
            let normalizedPoint = CGFloat(min(max(point, 0), 1))
            let chartHeight = max(0, rect.height - 4)
            let chartPoint = CGPoint(
                x: rect.minX + progress * rect.width,
                y: rect.minY + 2 + normalizedPoint * chartHeight
            )
            if index == 0 {
                path.move(to: chartPoint)
            } else {
                path.addLine(to: chartPoint)
            }
        }

        if closesToBottom {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

private struct MarketGrid: View {
    let tokens: [MarketToken]
    let onSelectToken: (MarketToken) -> Void

    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 64), spacing: 0, alignment: .top),
        count: 4
    )

    var body: some View {
        LazyVGrid(columns: columns, alignment: .center, spacing: 16) {
            ForEach(tokens) { token in
                Button {
                    onSelectToken(token)
                } label: {
                    MarketGridItem(token: token)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 20)
        .background(Color.air.groupedItem)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct MarketGridItem: View {
    let token: MarketToken

    var body: some View {
        VStack(spacing: 0) {
            MarketTokenIcon(token: token.token, size: 56, shouldShowChain: true, chainGeometry: .forIcon56)
                .frame(width: 56, height: 56)
                .allowsHitTesting(false)

            Text(token.name)
                .textStyle(.supportingEmphasized, scaling: .dynamic)
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: 88)
                .padding(.top, 6)

            Text(token.changeText)
                .textStyle(.supporting, content: .technical, scaling: .dynamic)
                .foregroundStyle(token.isPositive ? Color.air.positiveAmount : Color.air.negativeAmount)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 98, alignment: .top)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(token.name), \(token.changeText)")
    }
}

private struct MarketRows: View {
    let tokens: [MarketToken]
    let onSelectToken: (MarketToken) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(tokens.enumerated()), id: \.element.id) { index, token in
                MarketRowButton(token: token) {
                    onSelectToken(token)
                }

                if index < tokens.count - 1 {
                    Divider()
                        .padding(.leading, 62)
                }
            }
        }
        .background(Color.air.groupedItem)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

private struct MarketRowButton: View {
    let token: MarketToken
    let action: () -> Void

    @State private var isTouching = false

    var body: some View {
        Button(action: action) {
            MarketTokenRow(token: token, showsChevron: true)
        }
        .buttonStyle(.plain)
        .background {
            CellBackgroundHighlight(isHighlighted: isTouching)
        }
        .touchGesture($isTouching)
    }
}

struct MarketTokenRow: View {
    let token: MarketToken
    let showsChevron: Bool

    var body: some View {
        HStack(spacing: 10) {
            MarketTokenIcon(token: token.token, size: 40, shouldShowChain: true)
                .frame(width: 40, height: 40)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(token.token.symbol)
                        .textStyle(.calloutEmphasized, content: .technical, scaling: .dynamic)
                        .foregroundStyle(Color.air.primaryLabel)

                    if let badge = token.token.label?.nilIfEmpty {
                        Text(badge)
                            .textStyle(.badge, scaling: .dynamic)
                            .foregroundStyle(Color(red: 0.87, green: 0.55, blue: 0))
                            .padding(.horizontal, 3)
                            .frame(minHeight: 14)
                            .background(Color(red: 0.87, green: 0.55, blue: 0).opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }

                HStack(spacing: 4) {
                    if let price = token.priceText {
                        Text(price)
                            .foregroundStyle(Color.air.secondaryLabel)
                    }
                    Text(token.changeText)
                        .foregroundStyle(token.isPositive ? Color.air.positiveAmount : Color.air.negativeAmount)
                }
                .textStyle(.supporting, content: .technical, scaling: .dynamic)
            }

            Spacer(minLength: 8)

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color(UIColor.tertiaryLabel))
                    .frame(width: 16)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(token.token.symbol), \(token.name), \(token.priceText ?? ""), \(token.changeText)")
    }
}

private struct MarketTokenIcon: UIViewRepresentable {
    let token: ApiToken
    let size: CGFloat
    let shouldShowChain: Bool
    var chainGeometry: IconAccessoryView.LayoutGeometry? = nil

    func makeUIView(context: Context) -> IconView {
        let iconView = IconView(size: size, accessoryGeometry: chainGeometry)
        iconView.isUserInteractionEnabled = false
        return iconView
    }

    func updateUIView(_ iconView: IconView, context: Context) {
        iconView.setSize(size)
        iconView.config(with: token, shouldShowChain: shouldShowChain)
    }
}
