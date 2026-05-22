import Combine
import Kingfisher
import Perception
import SwiftUI
import UIComponents
import WalletContext
import WalletCore
import UIInAppBrowser

extension ExploreVC {
    /// UI events
    @MainActor struct ViewOutput {
        /// ApiDapp.url
        let connectedDappDidTap = PassthroughSubject<String, Never>()
        let connectedDappSettingsDidTap = PassthroughSubject<Void, Never>()

        let trendingDappDidTap = PassthroughSubject<ApiSite, Never>()
        let dappFromFolderDidTap = PassthroughSubject<ApiSite, Never>()
        let searchResultItemDidTap = PassthroughSubject<ExploreSearchResultItem, Never>()
        let recentSearchDidTap = PassthroughSubject<String, Never>()
        let clearRecentSearchesDidTap = PassthroughSubject<String, Never>()

        /// category id
        let dappCategoryDidTap = PassthroughSubject<Int, Never>()


        @available(iOS, deprecated: 26.0, message: "SwiftUI scroll is observed correctly in iOS 26")
        let scrollOffsetDidChange = PassthroughSubject<CGFloat, Never>()
    }

    struct SectionItem: Identifiable {
        let identity: Identity
        let items: [ContentItem]

        var id: Identity { identity }

        enum Identity: Hashable {
            case connectedDapps
            case trending
            case popularDapps
            case searchMatch       
            case searchSuggestions 
            case searchResults
            case searchHistory
            case recentSearches
        }
    }

    enum ContentItem: Equatable, Identifiable {
        case sectionHeader(title: String, isFirstHeader: Bool)
        case connectedDapps(dapps: [ApiDapp], layoutVariant: LayoutSizeVariant)
        case trendingDapps(sites: [ApiSite])
        case dappFolders(folders: [ExploreScreenDappFolderVM])

        case searchSectionHeader(title: String, hasTopGap: Bool = false)
        case searchResult(items: [ExploreSearchResultItem])
        case historyResult(items: [ExploreSearchResultItem])
        case recentSearchesHeader(title: String, tag: String)
        case recentSearches(items: [RecentSearchItem])

        var id: String {
            switch self {
            case let .sectionHeader(title, _): title
            case let .searchSectionHeader(title, _): "search_\(title)"
            case .connectedDapps: "connectedDapps_UniqueSingleGroup"
            case .trendingDapps: "trendingDapps_UniqueSingleGroup"
            case .dappFolders: "dappFolders_UniqueSingleGroup"
            case .searchResult: "searchResult_UniqueSingleGroup"
            case .historyResult: "historyResult_UniqueSingleGroup"
            case .recentSearchesHeader: "recentSearchesHeader_UniqueSingleGroup"
            case .recentSearches: "recentSearches_UniqueSingleGroup"
            }
        }
    }

    @Perceptible
    final class ObservedViewState {
        fileprivate private(set) var sections: [SectionItem] = []
        fileprivate private(set) var shouldShowWhiteBackground: Bool = false
        fileprivate private(set) var scrollToTopTrigger: UInt64 = 0

        init() {}

        func update(sections: [SectionItem], shouldShowWhiteBackground: Bool, animated: Bool = true) {
            func setChanges() {
                self.shouldShowWhiteBackground = shouldShowWhiteBackground
                self.sections = sections
            }

            animated ? withAnimation { setChanges() } : setChanges()
        }

        func scrollToTop() { scrollToTopTrigger += 1 }
    }

    static func makeViewStateSnapshot(exploreVM: ExploreVM,
                                      shouldRestrictSites: Bool,
                                      isSearchActive: Bool,
                                      trimmedSearchString: String,
                                      historyItems: [BrowserHistoryItem],
                                      recentSearchItems: [RecentSearchItem] = [])
        -> (sections: [SectionItem], shouldShowWhiteBackground: Bool) {
        makeViewStateSnapshot(connectedDapps: Array(exploreVM.connectedDapps.values.apply(Array.init)),
                              featuredTitle: exploreVM.featuredTitle,
                              exploreSites: exploreVM.exploreSites.values.apply(Array.init),
                              siteCategories: exploreVM.exploreCategories.values.apply(Array.init),
                              shouldRestrictSites: shouldRestrictSites,
                              isSearchActive: isSearchActive,
                              trimmedSearchString: trimmedSearchString,
                              historyItems: historyItems,
                              recentSearchItems: recentSearchItems)
    }

    private static func makeViewStateSnapshot(connectedDapps: [ApiDapp],
                                                  featuredTitle: String?,
                                                  exploreSites: [ApiSite],
                                                  siteCategories: [ApiSiteCategory],
                                                  shouldRestrictSites: Bool,
                                                  isSearchActive: Bool,
                                                  trimmedSearchString: String,
                                                  historyItems: [BrowserHistoryItem],
                                                  recentSearchItems: [RecentSearchItem] = [])
        -> (sections: [SectionItem], shouldShowWhiteBackground: Bool) {
        let exploreSites = shouldRestrictSites ? exploreSites.filter { !$0.canBeRestricted } : exploreSites
        var sections: [SectionItem] = []

        // Idle state:
        if !isSearchActive && trimmedSearchString.isEmpty {
            appendContentItems(to: &sections,
                               connectedDapps: connectedDapps,
                               featuredTitle: featuredTitle,
                               exploreSites: exploreSites,
                               siteCategories: siteCategories)
            return (sections, false)
        }

        // Search active, no query yet — show recent searches:
        if isSearchActive && trimmedSearchString.isEmpty {
            if !recentSearchItems.isEmpty {
                let tag = recentSearchItems.first?.tag ?? exploreHistoryTag
                sections.append(SectionItem(identity: .recentSearches, items: [
                    .recentSearchesHeader(title: lang("Recent Searches"), tag: tag),
                    .recentSearches(items: recentSearchItems),
                ]))
            }
            return (sections, !sections.isEmpty)
        }

        // Search state with query:
        let keyword = trimmedSearchString.lowercased()

        // 1. Exact URL match — first history item whose host or URL starts with the keyword.
        let matchedHistoryItem = historyItems.first { item in
            URL(string: item.url)?.host?.lowercased().hasPrefix(keyword) == true
                || item.url.lowercased().hasPrefix(keyword)
        }
        if let matched = matchedHistoryItem {
            let showFavicon = !matched.favicon.isEmpty
            sections.append(SectionItem(identity: .searchMatch, items: [
                .historyResult(items: [ExploreSearchResultItem(source: .history(matched), showFavicon: showFavicon)]),
            ]))
        }

        // 2. Suggestions — recent searches that contain the keyword, prefix matches ranked first, max 10.
        let suggestions = Array(
            recentSearchItems
                .filter { $0.text.lowercased().contains(keyword) }
                .sorted { a, b in
                    a.text.lowercased().hasPrefix(keyword) && !b.text.lowercased().hasPrefix(keyword)
                }
                .prefix(10)
        )
        if !suggestions.isEmpty {
            sections.append(SectionItem(identity: .searchSuggestions, items: [
                .recentSearches(items: suggestions),
            ]))
        }

        // 3. Dapps — name/description/url contains keyword, prefix matches ranked first, max 5.
        let matchingDapps = connectedDapps
            .filter { $0.matches(trimmedSearchString) }
            .map { ExploreSearchResultItem(source: .connectedDapp($0)) }
        let matchingSites = exploreSites
            .filter { $0.matches(trimmedSearchString) }
            .map { ExploreSearchResultItem(source: .site($0)) }

        var seen = Set<String>()
        let combinedResults = Array(
            (matchingDapps + matchingSites)
                .filter { seen.insert($0.id).inserted }
                .sorted { a, b in
                    prefixMatches(item: a, keyword: keyword) && !prefixMatches(item: b, keyword: keyword)
                }
                .prefix(5)
        )
        if !combinedResults.isEmpty {
            sections.append(SectionItem(identity: .searchResults, items: [
                .searchSectionHeader(title: lang("Popular and connected apps"), hasTopGap: !sections.isEmpty),
                .searchResult(items: combinedResults),
            ]))
        }

        // 4. History — contains match, prefix matches ranked first, max 5.
        // Exclude the exact-match item (already shown in section 1) to avoid duplication.
        let matchedURL = matchedHistoryItem?.url
        let matchingHistory = Array(
            historyItems
                .filter { $0.matches(trimmedSearchString) && $0.url != matchedURL }
                .sorted { a, b in
                    (a.title.lowercased().hasPrefix(keyword) || a.url.lowercased().hasPrefix(keyword))
                        && !(b.title.lowercased().hasPrefix(keyword) || b.url.lowercased().hasPrefix(keyword))
                }
                .prefix(5)
                .map { ExploreSearchResultItem(source: .history($0)) }
        )
        if !matchingHistory.isEmpty {
            sections.append(SectionItem(identity: .searchHistory, items: [
                .searchSectionHeader(title: lang("History"), hasTopGap: !sections.isEmpty),
                .historyResult(items: matchingHistory),
            ]))
        }

        return (sections, true)
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

// MARK: - Search Helpers

/// Returns true when any primary field of a search result item starts with the given (already-lowercased) keyword.
/// Used to rank prefix matches above substring matches.
private func prefixMatches(item: ExploreSearchResultItem, keyword: String) -> Bool {
    switch item.source {
    case .site(let s):
        return s.name.lowercased().hasPrefix(keyword)
            || s.description.lowercased().hasPrefix(keyword)
            || s.url.lowercased().hasPrefix(keyword)
    case .connectedDapp(let d):
        return d.name.lowercased().hasPrefix(keyword)
            || d.url.lowercased().hasPrefix(keyword)
    case .history(let h):
        return h.title.lowercased().hasPrefix(keyword)
            || h.url.lowercased().hasPrefix(keyword)
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
        /// 2 or more dapps
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
    /// Convenience init
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

//===-------------------------------------------------------------------------------------------------------------------===//

// MARK: - Screen View

#if DEBUG
@available(iOS 17.0, *)
#Preview {
    @Previewable @State var showConnectedDapps = true
    @Previewable @State var largeConnectedDapps = false
    @Previewable @State var showTrending = true
    @Previewable @State var searchState = false

    let viewOutput = ExploreVC.ViewOutput()
    let viewState = ExploreVC.ObservedViewState()

    var connectedDappsLayout: LayoutSizeVariant { largeConnectedDapps ? .regular : .compact }

    let (sections, shouldShowWhiteBackground) = ExploreVC
        .previewSnapshot(showConnectedDapps: showConnectedDapps,
                         connectedDappsLayout: connectedDappsLayout,
                         showTrending: showTrending,
                         searchString: searchState ? "t" : "",
                         isSearchActive: searchState)

    viewState.update(sections: sections, shouldShowWhiteBackground: shouldShowWhiteBackground)

    return ExploreVC.ScreenView(viewState: viewState, viewOutput: viewOutput)
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Toggle(isOn: $showConnectedDapps, label: { Text("Show Connected Dapps") })
                Toggle(isOn: $largeConnectedDapps, label: { Text("Large Connected Dapps") })
                Toggle(isOn: $showTrending, label: { Text("Show Trending") })
                Toggle(isOn: $searchState, label: { Text("Search State") })
            }
            .background { Rectangle().fill(.ultraThinMaterial).opacity(0.97) }
            .padding(EdgeInsets(top: 0, leading: 20, bottom: -20, trailing: 20))
        }
}

extension ExploreVC {
    static func previewSnapshot(showConnectedDapps: Bool,
                                connectedDappsLayout: LayoutSizeVariant,
                                showTrending: Bool,
                                searchString: String,
                                isSearchActive: Bool = false) -> (sections: [SectionItem], shouldShowWhiteBackground: Bool) {
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

        return Self.makeViewStateSnapshot(connectedDapps: connectedDapps,
                                          featuredTitle: nil,
                                          exploreSites: exploreSites,
                                          siteCategories: categories,
                                          shouldRestrictSites: false,
                                          isSearchActive: isSearchActive,
                                          trimmedSearchString: searchString,
                                          historyItems: [])
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
                            .backportScrollClipDisabled()
                            .scrollDismissesKeyboard(.immediately)
                            .safeAreaInset(edge: .leading, spacing: screenEdgesHSpacing) {
                                Color.clear.frame(width: 0, height: 1)
                            }
                            .safeAreaInset(edge: .trailing, spacing: screenEdgesHSpacing) {
                                Color.clear.frame(width: 0, height: 1)
                            }
                            .background(viewState.shouldShowWhiteBackground ? Color.air.background : Color.air.groupedBackground) // ignores safe area
                            .onChange(of: viewState.scrollToTopTrigger) { _ in
                                withAnimation { scrollReader.scrollTo(viewState.sections.first?.id, anchor: .top) }
                            } // end scrollView setup
                        }
                    } // end ScrollViewReader
                } // end GeometryReader
                .coordinateSpace(name: Self.screenSafeAreaCoordinateSpaceName)
            }
        } // end body

        private func vScrollContent(viewState: ObservedViewState, screenGeometry: GeometryProxy) -> some View {
            @ViewBuilder var content: some View {
                ForEach(viewState.sections) { sectionItem in
                    viewForSection(sectionItem, screenGeometryProxy: screenGeometry)
                }
                .applyModifierConditionally {
                    if #available(iOS 26.0, *) {
                        $0 // no need in scrollOffsetDidChange
                    } else {
                        $0.onFrameChange(inCoordinateSpace: Self.screenSafeAreaCoordinateSpaceName) { frame in
                            viewOutput.scrollOffsetDidChange.send(-frame.origin.y)
                        }
                    }
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

        // MARK: Child Views Building

        @ViewBuilder private func viewForSection(_ sectionItem: SectionItem, screenGeometryProxy: GeometryProxy) -> some View {
            ForEach(sectionItem.items) { contentItem in
                viewForItem(contentItem, screenGeometryProxy: screenGeometryProxy)
            }
            .id(sectionItem.id)
        }

        @ViewBuilder private func viewForItem(_ contentItem: ContentItem, screenGeometryProxy: GeometryProxy) -> some View {
            switch contentItem {
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

            case let .searchSectionHeader(title, hasTopGap):
                SearchSectionHeaderView(title: title, hasTopGap: hasTopGap)

            case let .searchResult(items):
                searchResultView(items: items)

            case let .historyResult(items):
                historyResultView(items: items)

            case let .recentSearchesHeader(title, tag):
                RecentSearchesSectionHeaderView(title: title, clearAction: {
                    viewOutput.clearRecentSearchesDidTap.send(tag)
                })

            case let .recentSearches(items):
                recentSearchesView(items: items)
            }
        }

        // MARK: Section Header View

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

        // MARK: Connected Daps

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

        // MARK: Trending Dapps

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

        // MARK: Search Results Section View

        private func searchResultView(items: [ExploreSearchResultItem]) -> some View {
            ForEach(items) { item in
                SearchResultItemRow(item: item, openAction: {
                    viewOutput.searchResultItemDidTap.send(item)
                })
            }
        }

        private func historyResultView(items: [ExploreSearchResultItem]) -> some View {
            ForEach(items) { item in
                SearchResultItemRow(item: item, openAction: {
                    viewOutput.searchResultItemDidTap.send(item)
                })
            }
        }

        // MARK: Recent Searches

        private func recentSearchesView(items: [RecentSearchItem]) -> some View {
            ForEach(items, id: \.text) { item in
                RecentSearchItemRow(item: item, tapAction: {
                    viewOutput.recentSearchDidTap.send(item.text)
                })
            }
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

// MARK: - Search Result Item

struct ExploreSearchResultItem: Equatable, Identifiable {
    enum Source: Equatable {
        case site(ApiSite)
        case connectedDapp(ApiDapp)
        case history(BrowserHistoryItem)
    }

    let source: Source
    var showFavicon: Bool = false

    var id: String {
        switch source {
        case .site(let s): s.url
        case .connectedDapp(let d): d.url
        // Prefix differs when showFavicon is set so SwiftUI treats the exact-match row
        // as a distinct identity from any same-URL row in the regular history section.
        case .history(let h): (showFavicon ? "match_" : "history_") + h.url
        }
    }

    var name: String {
        switch source {
        case .site(let s): s.name
        case .connectedDapp(let d): d.name
        case .history(let h): h.title
        }
    }

    var iconURL: String {
        switch source {
        case .site(let s): s.icon
        case .connectedDapp(let d): d.iconUrl
        case .history(let h): h.favicon
        }
    }

    nonisolated(unsafe) private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var subtitle: String {
        switch source {
        case .site(let s): return s.description
        case .connectedDapp(let d): return d.displayUrl
        case .history(let h):
            let host = URL(string: h.url)?.host ?? h.url
            let relative = Self.relativeDateFormatter.localizedString(for: h.visitDate, relativeTo: Date())
            return "\(host) · \(relative)"
        }
    }

    var shouldOpenExternally: Bool {
        switch source {
        case .site(let s): s.shouldOpenExternally
        case .connectedDapp, .history: false
        }
    }

    var showOpenButton: Bool {
        switch source {
        case .site, .connectedDapp: true
        case .history: false
        }
    }

    var url: String {
        switch source {
        case .site(let s): s.url
        case .connectedDapp(let d): d.url
        case .history(let h): h.url
        }
    }
}

private struct SearchSectionHeaderView: View {
    let title: String
    var hasTopGap: Bool = false

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.air.secondaryLabel)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(EdgeInsets(top: hasTopGap ? 20 : 0, leading: 12, bottom: 3, trailing: 16))
            .background(alignment: .bottom) {
                Rectangle()
                    .fill(Color.air.separator)
                    .frame(height: 1 / UIScreen.main.scale)
                    .padding(.leading, 12)
                    .padding(.trailing, 16)
            }
    }
}

private struct SearchResultItemRow: View {
    let item: ExploreSearchResultItem
    let openAction: () -> ()

    private let iconSize: CGFloat = 24
    private let iconCornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            leadingIcon

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 17, weight: .medium))
                        .lineLimit(1)
                    if item.shouldOpenExternally {
                        Image.airBundle("TelegramLogo20")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 18)
                            .foregroundStyle(Color.air.secondaryLabel.opacity(0.5))
                    }
                }
                
                Text(item.subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.air.secondaryLabel)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.showOpenButton {
                Button(action: openAction) {
                    Text(lang("Open"))
                    .foregroundStyle(.tint)
                }
                .buttonStyle(OpenButtonStyle(size: .small))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !item.showOpenButton { openAction() } }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.air.separator)
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.leading, 48)
                .padding(.trailing, 12)
        }
    }

    @ViewBuilder private var leadingIcon: some View {
        if case .history = item.source, !item.showFavicon {
            Image(systemName: "clock")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .frame(width: iconSize, height: iconSize)
        } else {
            KFImage(URL(string: item.iconURL))
                .resizable()
                .loadDiskFileSynchronously(false)
                .aspectRatio(contentMode: .fill)
                .clipShape(.rect(cornerRadius: iconCornerRadius))
                .frame(width: iconSize, height: iconSize)
                .applyModifierConditionally {
                    if #available(iOS 26.0, *) {
                        $0.glassEffect(.regular, in: .rect(cornerRadius: iconCornerRadius))
                    } else {
                        $0
                    }
                }
        }
    }
}

// MARK: - Recent Searches Section Header

private struct RecentSearchesSectionHeaderView: View {
    let title: String
    let clearAction: () -> ()

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.air.secondaryLabel)

            Spacer()

            Button(action: clearAction) {
                Text(lang("Clear All"))
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 0, leading: 12, bottom: 3, trailing: 12))
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.air.separator)
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.leading, 12)
                .padding(.trailing, 16)
        }
    }
}

// MARK: - Recent Search Item Row

private struct RecentSearchItemRow: View {
    let item: RecentSearchItem
    let tapAction: () -> ()

    private let iconSize: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color.air.secondaryLabel)
                .frame(width: iconSize, height: iconSize)

            Text(item.text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Color.air.primaryLabel)
                .lineLimit(1)

            Spacer(minLength: 4)
        }
        .contentShape(Rectangle())
        .onTapGesture { tapAction() }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(alignment: .bottom) {
            Rectangle()
                .fill(Color.air.separator)
                .frame(height: 1 / UIScreen.main.scale)
                .padding(.leading, 48)
                .padding(.trailing, 12)
        }
    }
}
