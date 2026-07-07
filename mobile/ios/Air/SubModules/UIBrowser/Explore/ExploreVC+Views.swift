import Combine
import Kingfisher
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import UIInAppBrowser

extension ExploreVC {
    @MainActor struct ViewOutput {
        let connectedDappDidTap = PassthroughSubject<String, Never>()
        let connectedDappSettingsDidTap = PassthroughSubject<Void, Never>()

        let trendingDappDidTap = PassthroughSubject<ApiSite, Never>()
        let dappFromFolderDidTap = PassthroughSubject<ApiSite, Never>()

        let dappCategoryDidTap = PassthroughSubject<Int, Never>()

        let scrollOffsetDidChange = PassthroughSubject<CGFloat, Never>()
    }

    struct SectionItem: Identifiable {
        let identity: Identity
        let items: [ContentItem]

        var id: Identity { identity }

        enum Identity: Hashable {
            case lockdownModeWarning
            case connectedDapps
            case trending
            case popularDapps
        }
    }

    enum ContentItem: Equatable, Identifiable {
        case lockdownModeWarning
        case sectionHeader(title: String, isFirstHeader: Bool)
        case connectedDapps(dapps: [ApiDapp], layoutVariant: LayoutSizeVariant)
        case trendingDapps(sites: [ApiSite])
        case dappFolders(folders: [ExploreScreenDappFolderVM])

        var id: String {
            switch self {
            case .lockdownModeWarning: "lockdownModeWarning_UniqueSingleGroup"
            case let .sectionHeader(title, _): title
            case .connectedDapps: "connectedDapps_UniqueSingleGroup"
            case .trendingDapps: "trendingDapps_UniqueSingleGroup"
            case .dappFolders: "dappFolders_UniqueSingleGroup"
            }
        }
    }

    @Perceptible
    final class ObservedViewState {
        enum Content {
            case browsing([SectionItem])
            case search(ComposedSearchResult)

            var isBrowsing: Bool {
                if case .browsing = self { return true }
                return false
            }
        }

        fileprivate private(set) var content: Content = .browsing([])
        fileprivate private(set) var shouldShowWhiteBackground: Bool = false
        fileprivate private(set) var scrollToTopTrigger: UInt64 = 0
        fileprivate private(set) var scrollToTopAnimated: Bool = true

        init() {}

        func updateBrowsing(sections: [SectionItem], animated: Bool = true) {
            if animated {
                withAnimation {
                    self.shouldShowWhiteBackground = false
                    self.content = .browsing(sections)
                }
            } else {
                self.shouldShowWhiteBackground = false
                self.content = .browsing(sections)
            }
        }

        func updateSearch(_ result: ComposedSearchResult) {
            self.shouldShowWhiteBackground = true
            self.content = .search(result)
        }

        fileprivate var firstAnchorID: AnyHashable? {
            switch content {
            case .browsing(let sections): return sections.first.map { AnyHashable($0.id) }
            case .search(let result): return result.sections.first.map { AnyHashable($0.id) }
            }
        }

        func scrollToTop(animated: Bool = true) {
            scrollToTopAnimated = animated
            scrollToTopTrigger += 1
        }
    }

    static func makeBrowsingSections(connectedDapps: [ApiDapp],
                                     featuredTitle: String?,
                                     exploreSites: [ApiSite],
                                     siteCategories: [ApiSiteCategory],
                                     shouldRestrictSites: Bool,
                                     isLockdownModeEnabled: Bool) -> [SectionItem] {
        let exploreSites = shouldRestrictSites ? exploreSites.filter { !$0.canBeRestricted } : exploreSites
        var sections: [SectionItem] = []

        if isLockdownModeEnabled {
            sections.append(SectionItem(identity: .lockdownModeWarning, items: [.lockdownModeWarning]))
        }
        appendContentItems(to: &sections,
                           connectedDapps: connectedDapps,
                           featuredTitle: featuredTitle,
                           exploreSites: exploreSites,
                           siteCategories: siteCategories)
        return sections
    }

    private static func appendContentItems(to sections: inout [SectionItem],
                                           connectedDapps: [ApiDapp],
                                           featuredTitle: String?,
                                           exploreSites: [ApiSite],
                                           siteCategories: [ApiSiteCategory]) {
        var isFirstHeader: Bool { sections.isEmpty }

        // Connected Dapps Section
        if !connectedDapps.isEmpty {
            sections.append(SectionItem(identity: .connectedDapps, items: [
                .sectionHeader(title: lang("Connected Sites"), isFirstHeader: isFirstHeader),
                .connectedDapps(dapps: connectedDapps,
                                layoutVariant: connectedDapps.count > 3 ? .regular : .compact),
            ]))
        }

        // Trending Section
        let trending = exploreSites.filter { $0.isFeatured == true }
        if !trending.isEmpty {
            let titleText: String = if let featuredTitle = featuredTitle, !featuredTitle.isEmpty {
                lang(featuredTitle)
            } else {
                lang("Trending")
            }
            sections.append(SectionItem(identity: .trending, items: [
                .sectionHeader(title: titleText, isFirstHeader: isFirstHeader),
                .trendingDapps(sites: trending),
            ]))
        }

        // Popular Apps (All Dapps) Section
        if !exploreSites.isEmpty {
            let dappFolderVMs = siteCategories.compactMap { category in
                let categorySites: [ApiSite] = exploreSites.filter { $0.categoryId == category.id }
                return ExploreScreenDappFolderVM(category: category, sites: categorySites)
            }

            if !dappFolderVMs.isEmpty {
                sections.append(SectionItem(identity: .popularDapps, items: [
                    .sectionHeader(title: lang("Popular Sites"), isFirstHeader: isFirstHeader),
                    .dappFolders(folders: dappFolderVMs),
                ]))
            }
        }
    }
}

// MARK: - View Models

struct ExploreScreenDappFolderVM: Equatable {
    let categoryName: String
    let categoryId: Int
    let dapps: Dapps

    /// First 3 dapps in the folder
    enum Dapps: Equatable {
        case one(ApiSite)
        case two(ApiSite, ApiSite)
        case three(ApiSite, ApiSite, ApiSite)
        case four(ApiSite, ApiSite, ApiSite, LastItemVariant)
    }

    /// Last icon in folder, either 1 dapp or more items
    enum LastItemVariant: Equatable {
        case singleDapp(ApiSite)
        case moreDapps(MoreDapps)
    }

    /// Always 2–4 items, guaranteed at construction
    struct MoreDapps: Equatable {
        let first: ApiSite
        let second: ApiSite
        let rest: [ApiSite]

        init?(firstSite first: ApiSite, otherSites: [ApiSite]) {
            guard let second = otherSites.first else { return nil }
            self.first = first
            self.second = second
            rest = Array(otherSites.dropFirst().prefix(2))
        }
    }
}

extension ExploreScreenDappFolderVM {
    init?(category: ApiSiteCategory, sites: [ApiSite]) {
        // Folder can contain at least 1 element.
        guard let first = sites[at: 0] else { return nil }

        guard let second = sites[at: 1] else {
            self.init(categoryName: category.name, categoryId: category.id, dapps: .one(first)); return
        }

        guard let third = sites[at: 2] else {
            self.init(categoryName: category.name, categoryId: category.id, dapps: .two(first, second)); return
        }

        guard let fourth = sites[at: 3] else {
            self.init(categoryName: category.name, categoryId: category.id, dapps: .three(first, second, third)); return
        }

        let lastItemVariant: LastItemVariant
        if let moreDapps = MoreDapps(firstSite: fourth, otherSites: sites.dropFirst(4).apply(Array.init)) {
            lastItemVariant = .moreDapps(moreDapps)
        } else {
            lastItemVariant = .singleDapp(fourth)
        }
        self.init(categoryName: category.name, categoryId: category.id, dapps: .four(first, second, third, lastItemVariant))
    }
}

// MARK: - Screen View

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    @Previewable @State var showConnectedDapps = true
    @Previewable @State var largeConnectedDapps = false
    @Previewable @State var showTrending = true

    let viewOutput = ExploreVC.ViewOutput()
    let viewState = ExploreVC.ObservedViewState()

    var connectedDappsLayout: LayoutSizeVariant { largeConnectedDapps ? .regular : .compact }

    let sections = ExploreVC
        .previewBrowsingSections(showConnectedDapps: showConnectedDapps,
                                 connectedDappsLayout: connectedDappsLayout,
                                 showTrending: showTrending)

    viewState.updateBrowsing(sections: sections)

    return ExploreVC.ScreenView(viewState: viewState, viewOutput: viewOutput)
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Toggle(isOn: $showConnectedDapps, label: { Text("Show Connected Dapps") })
                Toggle(isOn: $largeConnectedDapps, label: { Text("Large Connected Dapps") })
                Toggle(isOn: $showTrending, label: { Text("Show Trending") })
            }
            .background { Rectangle().fill(.ultraThinMaterial).opacity(0.97) }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: -20, trailing: 20))
        }
}

extension ExploreVC {
    static func previewBrowsingSections(showConnectedDapps: Bool,
                                        connectedDappsLayout: LayoutSizeVariant,
                                        showTrending: Bool) -> [SectionItem] {
        let connectedDapps: [ApiDapp] = if showConnectedDapps {
            switch connectedDappsLayout {
            case .compact: ApiDapp.sampleList.prefix(2).apply(Array.init)
            case .regular: ApiDapp.sampleList
            }
        } else {
            []
        }

        let categories = ApiSiteCategory.sampleCategories

        var exploreSites: [ApiSite] = []
        for (categoryIndex, category) in categories.enumerated() {
            if showTrending, categoryIndex == 0 {
                exploreSites.append(.sampleFeatured(categoryId: category.id))
                continue
            }

            let sitesCount = categoryIndex + 1
            for siteIndex in 0 ..< sitesCount {
                let isFeatured = showTrending && sitesCount == 3 // create 3 trending sites when need to show them
                // sampleIndex is added to to name, as name is used as uniqueness identity for SwiftUI
                let sampleIndex = categoryIndex * 50 + siteIndex
                exploreSites.append(.randomSample(categoryId: category.id, isFeatured: isFeatured, uniquenessIndex: sampleIndex))
            }
        }

        return Self.makeBrowsingSections(connectedDapps: connectedDapps,
                                         featuredTitle: nil,
                                         exploreSites: exploreSites,
                                         siteCategories: categories,
                                         shouldRestrictSites: false,
                                         isLockdownModeEnabled: false)
    }
}
#endif

extension ExploreVC {
    struct ScreenView: View {
        let viewState: ObservedViewState
        let viewOutput: ViewOutput

        private let backgroundColor = Color.air.groupedBackground

        private let trendingDappsInterItemHSpacing: Double = 16

        @Environment(\.horizontalSizeClass)
        private var horizontalSizeClass: UserInterfaceSizeClass?

        private let screenEdgesHSpacing: Double = 20

        private static let screenSafeAreaCoordinateSpaceName = "ExploreScreenCoordinateSpace"

        var body: some View {
            WithPerceptionTracking {
                GeometryReader { screenGeometry in
                    ScrollViewReader { scrollReader in
                        WithPerceptionTracking {
                            ScrollView(showsIndicators: false) {
                                vScrollContent(viewState: viewState, screenGeometry: screenGeometry)
                            }
                            .backportScrollEdgeEffectHidden(viewState.content.isBrowsing, for: .top)
                            .backportScrollClipDisabled()
                            .scrollDismissesKeyboard(.immediately)
                            .safeAreaInset(edge: .leading, spacing: screenEdgesHSpacing) {
                                Color.clear.frame(width: 0, height: 1)
                            }
                            .safeAreaInset(edge: .trailing, spacing: screenEdgesHSpacing) {
                                Color.clear.frame(width: 0, height: 1)
                            }
                            .background(viewState.shouldShowWhiteBackground ? Color.air.background : Color.air.groupedBackground)
                            .onChange(of: viewState.scrollToTopTrigger) { _ in
                                let scroll = {
                                    scrollReader.scrollTo(viewState.firstAnchorID, anchor: .top)
                                }
                                if viewState.scrollToTopAnimated {
                                    withAnimation { scroll() }
                                } else {
                                    var transaction = Transaction()
                                    transaction.disablesAnimations = true
                                    withTransaction(transaction, scroll)
                                }
                            }
                        }
                    }
                }
                .coordinateSpace(name: Self.screenSafeAreaCoordinateSpaceName)
            }
        } 

        private func vScrollContent(viewState: ObservedViewState, screenGeometry: GeometryProxy) -> some View {
            @ViewBuilder var content: some View {
                Group {
                    switch viewState.content {
                    case .browsing(let sections):
                        ForEach(sections) { sectionItem in
                            viewForSection(sectionItem, screenGeometryProxy: screenGeometry)
                        }
                    case .search(let result):
                        searchContent(result)
                    }
                }
                .onFrameChange(inCoordinateSpace: Self.screenSafeAreaCoordinateSpaceName) { frame in
                    viewOutput.scrollOffsetDidChange.send(-frame.origin.y)
                }

                Color.clear.frame(height: 70 + 16) // content inset imitation / overScroll
            }

            @ViewBuilder var stack: some View {
                if #available(iOS 18.0, *) {
                    LazyVStack(alignment: .leading, spacing: 0) { content }
                        .id(viewState.shouldShowWhiteBackground)
                    // SwiftUI has a bug and animates layout differences inside ScrollView, causing content to slide from bottom to top
                    // when state changes from search to idle, if search content.height > scrollView.frame.height.
                    // .id(viewState.shouldShowWhiteBackground) forces a full rebuild on mode change, so SwiftUI doesn’t
                    // animate layout changes and only applies the fade. There problem is only with LazyVStack, VStack is ok.
                } else {
                    // In iOS <=17, LazyVStack inside a vertical ScrollView can fail to render horizontal ScrollView content after
                    // state changes, leaving blank areas while preserving their size. This is because SwiftUI incorrectly
                    // caches the layout of nested scroll views, preventing proper re-rendering.
                    VStack(alignment: .leading, spacing: 0) { content }
                }
            }
            return stack
        }

        @ViewBuilder private func viewForSection(_ sectionItem: SectionItem, screenGeometryProxy: GeometryProxy) -> some View {
            ForEach(sectionItem.items) { contentItem in
                viewForItem(contentItem, screenGeometryProxy: screenGeometryProxy)
            }
            .id(sectionItem.id)
        }

        @ViewBuilder private func viewForItem(_ contentItem: ContentItem, screenGeometryProxy: GeometryProxy) -> some View {
            switch contentItem {
            case .lockdownModeWarning:
                lockdownModeWarningView()

            case let .sectionHeader(title, isFirstHeader):
                sectionHeaderView(title: title, isFirstHeader: isFirstHeader)

            case let .connectedDapps(dapps, layoutVariant):
                connectedDappsView(dapps: dapps, layoutVariant: layoutVariant)

            case let .trendingDapps(sites):
                if #available(iOS 17.0, *) {
                    trendingDappsView(sites: sites)
                } else {
                    trendingDappsView_below_iOS17(sites: sites, screenGeometryProxy: screenGeometryProxy)
                }

            case let .dappFolders(folderVMs):
                ExploreScreenDappFoldersView(folders: folderVMs,
                                             onTapDapp: { site in
                                                 viewOutput.dappFromFolderDidTap.send(site)
                                             }, onTapMore: { categoryId in
                                                 viewOutput.dappCategoryDidTap.send(categoryId)
                                             })
            }
        }

        @ViewBuilder private func searchContent(_ result: ComposedSearchResult) -> some View {
            ForEach(Array(result.sections.enumerated()), id: \.element.id) { index, section in
                searchSectionView(section, hasTopGap: index > 0)
            }
        }

        @ViewBuilder private func searchSectionView(_ section: SearchResultSection, hasTopGap: Bool) -> some View {
            Group {
                if let header = section.header {
                    SearchSectionHeaderView(header: header, hasTopGap: hasTopGap)
                }
                ForEach(section.items, id: \.id) { item in
                    item.makeView(isTopMatch: section.isTopMatch)
                }
            }
            .id(section.id)
        }

        private func lockdownModeWarningView() -> some View {
            WarningView(
                header: lang("$lockdown_mode_enabled_title"),
                text: lang("$lockdown_mode_walletconnect_unavailable", arg1: APP_NAME),
                kind: .info
            )
            .padding(.top, 14)
        }

        private func sectionHeaderView(title: String, isFirstHeader: Bool) -> some View {
            HStack(spacing: 0) {
                if isFirstHeader {
                    SectionHeaderView(title: title, topInset: 14)
                } else {
                    SectionHeaderView(title: title)
                }
                Spacer()
            }
        }

        private func connectedDappsView(dapps: [ApiDapp], layoutVariant: LayoutSizeVariant) -> some View {
            let isCompact = switch layoutVariant {
            case .compact: true
            case .regular: false
            }

            return ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: isCompact ? 8 : 12) {
                    ForEach(dapps, id: \.url) { dapp in
                        ConnectedDappButton(dappName: dapp.name,
                                            iconURL: dapp.iconUrl,
                                            layoutVariant: layoutVariant,
                                            onTap: { viewOutput.connectedDappDidTap.send(dapp.url) })
                    }

                    ConnectedDappsSettingsButton(layoutVariant: layoutVariant,
                                                 onTap: { viewOutput.connectedDappSettingsDidTap.send(()) })
                } // end HStack
            } // end ScrollView
            .backportScrollClipDisabled()
            .applyModifierConditionally {
                if #available(iOS 17.0, *) {
                    $0
                } else {
                    $0.frame(height: isCompact ? 36 : 88) // below iOS ScrollView not sized by child views
                }
            }
        }

        @available(iOS 17.0, *)
        private func trendingDappsView(sites: [ApiSite]) -> some View {
            AutoScrollingTrendingView(
                sites: sites,
                spacing: trendingDappsInterItemHSpacing,
                viewOutput: viewOutput,
                itemWidth: { trendingDappViewWidth(basedOn: $0) }
            )
        }

        private func trendingDappsView_below_iOS17(sites: [ApiSite], screenGeometryProxy: GeometryProxy) -> some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: trendingDappsInterItemHSpacing) {
                    ForEach(sites, id: \.url) { site in
                        trendingDappView_below_iOS17(site: site, screenGeometryProxy: screenGeometryProxy)
                    }
                }
            }
            // on iOS16 ScrollView is not sized by child views, so make scrollView height via aspectRatio
            .aspectRatio(horizontalSizeClass == .regular ? 4 : 2, contentMode: .fit)
            .backportScrollClipDisabled()
        }

        private func trendingDappView_below_iOS17(site: ApiSite, screenGeometryProxy: GeometryProxy) -> some View {
            let safeAreaWidth = screenGeometryProxy.size.width
            let hScrollWidth = safeAreaWidth - screenEdgesHSpacing - screenEdgesHSpacing

            return ExploreScreenFeaturedDappView(site: site, onTap: {
                viewOutput.trendingDappDidTap.send(site)
            })
            .frame(idealWidth: trendingDappViewWidth(basedOn: hScrollWidth))
        }

        private func trendingDappViewWidth(basedOn hScrollWidth: CGFloat) -> CGFloat {
            Self.adaptiveWidthFor(availableHorizontalSpace: hScrollWidth,
                                  itemMinWidth: min(320, hScrollWidth),
                                  spacing: trendingDappsInterItemHSpacing)
        }

    }
}

// MARK: - Auto-Scrolling Trending View

@available(iOS 17.0, *)
private struct AutoScrollingTrendingView: View {
    let sites: [ApiSite]
    let spacing: Double
    let viewOutput: ExploreVC.ViewOutput
    let itemWidth: (CGFloat) -> CGFloat

    private static let autoScrollInterval: UInt64 = 5_000_000_000
    private static let manualScrollPause: UInt64 = 5_000_000_000

    @State private var currentIndex: Int = 0
    @State private var autoScrollTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: spacing) {
                    ForEach(Array(sites.enumerated()), id: \.element.url) { index, site in
                        ExploreScreenFeaturedDappView(site: site, onTap: {
                            viewOutput.trendingDappDidTap.send(site)
                        })
                        .aspectRatio(2, contentMode: .fill)
                        .containerRelativeFrame(.horizontal) { hScrollWidth, _ in
                            itemWidth(hScrollWidth)
                        }
                        .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
            .simultaneousGesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { _ in cancelAutoScroll() }
                    .onEnded { _ in startAutoScroll(delay: Self.manualScrollPause, proxy: proxy) }
            )
            .onAppear {
                if sites.count > 1 {
                    startAutoScroll(delay: Self.autoScrollInterval, proxy: proxy)
                }
            }
            .onDisappear {
                cancelAutoScroll()
            }
        }
    }

    private func startAutoScroll(delay: UInt64, proxy: ScrollViewProxy) {
        guard sites.count > 1 else { return }
        cancelAutoScroll()
        autoScrollTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay)
            while !Task.isCancelled {
                currentIndex = (currentIndex + 1) % sites.count
                withAnimation(.spring(duration: 0.5)) {
                    proxy.scrollTo(currentIndex, anchor: .leading)
                }
                try? await Task.sleep(nanoseconds: Self.autoScrollInterval)
            }
        }
    }

    private func cancelAutoScroll() {
        autoScrollTask?.cancel()
        autoScrollTask = nil
    }
}

