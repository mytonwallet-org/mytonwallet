import Foundation
import UIInAppBrowser
import WalletContext
import WalletCore

@MainActor
final class HistorySearchProvider: SingleShotSearchProvider {
    private let tag: String
    private let actions: ExploreSearchActions

    init(tag: String, actions: ExploreSearchActions) {
        self.tag = tag
        self.actions = actions
    }

    func search(_ query: SearchQuery) async -> [SearchResultSection] {
        guard !query.isEmpty else { return [] }
        let keyword = query.keyword
        let history = BrowserHistoryStore.shared.items.filter { $0.tag == tag && !$0.isGoogleSearchResult }

        // Exact match: first item whose host or URL starts with the keyword.
        let exact = history.first { $0.urlPrefixMatches(keyword: keyword) }

        var items: [any SearchResultItem] = []
        if let exact {
            let payload = ExploreSearchResultItem(source: .history(exact), showFavicon: !exact.favicon.isEmpty)
            items.append(ResultSearchItem(payload: payload, isExactMatch: true, actions: actions))
        }

        let regular = history
            .filter { $0.matches(query.text) && $0.url != exact?.url }
            .sorted { a, b in
                a.prefixMatches(keyword: keyword) && !b.prefixMatches(keyword: keyword)
            }
            .map {
                ResultSearchItem(payload: ExploreSearchResultItem(source: .history($0)), isExactMatch: false, actions: actions)
            }
        items.append(contentsOf: regular)

        return items.isEmpty ? [] : [
            .init(id: .history,
                  order: SearchSectionOrder.history,
                  header: .init(title: lang("History")),
                  items: items
            )
        ]
    }
}

private extension BrowserHistoryItem {
    func urlPrefixMatches(keyword: String) -> Bool {
        SearchURLMatching.urlHasPrefix(url, prefix: keyword)
    }

    func prefixMatches(keyword: String) -> Bool {
        title.lowercased().hasPrefix(keyword) || urlPrefixMatches(keyword: keyword)
    }

    func matches(_ searchString: String) -> Bool {
        let s = searchString.lowercased()
        return title.lowercased().contains(s) || SearchURLMatching.urlContains(url, searchText: s)
    }

    var isGoogleSearchResult: Bool {
        guard let components = URLComponents(string: url),
              let host = components.host?.lowercased() else { return false }
        return host.contains("google.") && components.path.lowercased().hasPrefix("/search")
    }
}
