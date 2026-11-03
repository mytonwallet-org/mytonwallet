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

    nonisolated deinit {
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
        refreshIfNeeded()
    }

    func scrollToTop() {
        scrollToTopRequest += 1
    }

    func reloadTokens() {
        guard hasStarted else { return }
        rebuildSections()
        refreshIfNeeded()
    }

    func refreshIfNeeded() {
        guard hasStarted, fetchTask == nil else { return }
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
    let pagingTint: WPagingBackgroundTint
    let onScrollOffsetChange: (CGFloat) -> Void
    let onSeeAll: (MarketSection) -> Void
    let onSelectToken: (MarketToken) -> Void

    @Environment(\.horizontalContentMargins) private var contentMargins
    @Namespace private var scrollCoordinateSpace

    var body: some View {
        GeometryReader { geometry in
            let columnCount = MarketGridLayout.columnCount(
                availableWidth: geometry.size.width - contentMargins.leading - contentMargins.trailing
            )
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(model.sections) { section in
                            MarketSectionView(
                                section: section.presentation(columnCount: columnCount),
                                columnCount: columnCount,
                                onSeeAll: { onSeeAll(section) },
                                onSelectToken: { item in
                                    if let token = section.tokens.first(where: { $0.id == item.id }) { onSelectToken(token) }
                                }
                            )
                            .id(section.id)
                        }
                    }
                    .padding(.top, 14)
                    .padding(.bottom, 32)
                    .scrollPosition(ns: scrollCoordinateSpace, callback: onScrollOffsetChange)
                }
                .backportScrollClipDisabled()
                .coordinateSpace(name: scrollCoordinateSpace)
                .background(WPagingBackground(tint: pagingTint, base: Color.air.groupedBackground))
                .onChange(of: model.scrollToTopRequest) { _ in
                    guard let firstSection = model.sections.first else { return }
                    withAnimation {
                        proxy.scrollTo(firstSection.id, anchor: .top)
                    }
                }
            }
        }
        .background(WPagingBackground(tint: pagingTint, base: Color.air.groupedBackground))
    }
}

/// The Market screen and Futures use the same UIKit section renderer.
struct MarketSectionView: UIViewRepresentable {
    @Environment(\.horizontalContentMargins) private var contentMargins
    let section: MarketSectionDisplayData
    var columnCount = 4
    let onSeeAll: () -> Void
    let onSelectToken: (MarketItemDisplayData) -> Void

    func makeUIView(context: Context) -> MarketSectionContentView { MarketSectionContentView() }
    func updateUIView(_ view: MarketSectionContentView, context: Context) {
        view.configure(section, columnCount: columnCount, insets: .init(top: 0, leading: contentMargins.leading, bottom: 0, trailing: contentMargins.trailing),
                       onSeeAll: onSeeAll, onSelect: onSelectToken)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: MarketSectionContentView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 402, height: MarketSectionContentView.height(for: section, columnCount: columnCount))
    }
}
