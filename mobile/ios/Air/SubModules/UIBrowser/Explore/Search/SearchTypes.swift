import SwiftUI
import UIInAppBrowser
import WalletContext
import WalletCore

struct SearchQuery: Equatable {
    let text: String
    let keyword: String // lowercased text, convenient for matching.
    let shouldRestrictSites: Bool

    var isEmpty: Bool { keyword.isEmpty }

    init(text: String, shouldRestrictSites: Bool) {
        self.text = text
        self.keyword = text.lowercased()
        self.shouldRestrictSites = shouldRestrictSites
    }
}

enum SearchSectionID: Hashable {
    case exactMatch
    case wallets
    case suggestions
    case recentSearches
    case sitesAndDapps
    case history
    case searchInGoogle
}

enum SearchSectionOrder {
    static let recentSearchesEmpty = -10
    static let exactMatch = 0
    static let suggestions = 5
    static let wallets = 10
    static let sitesAndDapps = 20
    static let history = 30
    static let searchInGoogle = 40
}

struct SearchSectionHeader {
    struct Action {
        let title: String
        let handler: @MainActor () -> Void
    }

    let title: String
    var action: Action?

    init(title: String, action: Action? = nil) {
        self.title = title
        self.action = action
    }
}

struct AnySearchItemView: View {
    private let erased: AnyView

    init<Content: View>(@ViewBuilder content: () -> Content) {
        self.erased = AnyView(content())
    }

    var body: some View { erased }
}

@MainActor
enum SearchDateFormatting {
    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    static func relativeString(for date: Date, relativeTo: Date = Date()) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: relativeTo)
    }
}

@MainActor
protocol SearchResultItem {
    var id: String { get }
    var deduplicationKey: String? { get }
    
    /// Whether this item is eligible to become the single top match. The composer promotes only the
    /// first such item it meets in ordered sections; any other eligible items stay in their section
    /// and render as regular rows.
    var isExactMatch: Bool { get }

    func makeView(isTopMatch: Bool) -> AnySearchItemView
    func performDefaultAction()
}

extension SearchResultItem {
    var deduplicationKey: String? { nil }
    var isExactMatch: Bool { false }
}

struct SearchResultSection {
    let id: SearchSectionID
    let order: Int
    var itemCap: Int = 5
    let header: SearchSectionHeader?
    let items: [any SearchResultItem]
    var isTopMatch: Bool = false

    func replacingItems(_ items: [any SearchResultItem]) -> SearchResultSection {
        SearchResultSection(
            id: id, order: order, itemCap: itemCap, header: header,
            items: items, isTopMatch: isTopMatch
        )
    }
}

struct ComposedSearchResult {
    let sections: [SearchResultSection]
    var isEmpty: Bool { sections.isEmpty }

    var topMatch: (any SearchResultItem)? {
        sections.first(where: \.isTopMatch)?.items.first
    }
}

// MARK: - Provider

/// A self-contained search provider. Owns / accesses its own data source and emits 0..n sections.
///
/// Providers may call `emit` multiple times to deliver intermediate results progressively (e.g. instant
/// local matches first, then a refined snapshot once a network request resolves). Each `emit` carries the
/// provider's full current snapshot of sections, not a delta — the coordinator replaces this provider's
/// prior contribution with the latest snapshot. `emit` stays on the main actor, so sections/items never
/// cross an actor boundary and need not be `Sendable`.
///
/// Cancellation is cooperative: when the surrounding `Task` is cancelled the provider should stop early
/// (`guard !Task.isCancelled`) and rely on cancellation-aware awaits; any late `emit` is discarded by the
/// coordinator, so partial work is dropped silently.
@MainActor
protocol SearchProvider: AnyObject {
    func search(_ query: SearchQuery, emit: @MainActor ([SearchResultSection]) -> Void) async throws
}

@MainActor
protocol SingleShotSearchProvider: SearchProvider {
    func search(_ query: SearchQuery) async throws -> [SearchResultSection]
}

extension SingleShotSearchProvider {
    func search(_ query: SearchQuery, emit: @MainActor ([SearchResultSection]) -> Void) async throws {
        let sections = try await search(query)
        guard !Task.isCancelled else { return }
        emit(sections)
    }
}

@MainActor
struct ExploreSearchActions {
    let openSite: (ApiSite) -> Void
    let openDapp: (ApiDapp) -> Void
    let openHistory: (BrowserHistoryItem) -> Void
    let openWallet: (MAccount) -> Void
    let openExternalURL: (_ url: String, _ appUrl: String?) -> Void
    let showTemporaryViewAccount: (_ network: ApiNetwork, _ addressOrDomainByChain: [String: String]) -> Void
    let insertToSearchString: (_ text: String) -> Void
    let searchGoogle: (String) -> Void
    let clearRecentSearches: (String) -> Void
}
