import Foundation
import WalletContext

@MainActor
struct SearchResultComposer {
    let actions: ExploreSearchActions
    let recentSearchTag: String
    
    func compose(_ sections: [SearchResultSection], query: SearchQuery) -> ComposedSearchResult {
        // 1. Order sections first: the top match is the first eligible item in this order.
        var working = sections.sorted { $0.order < $1.order }

        // 2. Merge sections sharing an id (multiple providers may contribute to the same section):
        //    concatenate their items in order, keeping the first occurrence's header / order / cap.
        working = mergingSectionsWithSameID(working)

        // 3. Promote only the first exact-match-eligible item into a synthetic top section. Any other
        //    eligible items are left untouched in their sections and render as regular rows.
        promoteFirstExactMatch(in: &working)

        // 4. Add recent search / suggestions / open-in-google-stuff.
        if let suggestions = composeRecentSearchesSuggestionsAndGoogle(working, query: query) {
            working.append(contentsOf: suggestions)
            working = mergingSectionsWithSameID(working)
            working = working.sorted { $0.order < $1.order }
        }

        // 5. Cross-section deduplication (keep first by order) + per-section cap + drop empty.
        var seenDeduplicatedKeys = Set<String>()
        var result: [SearchResultSection] = []
        for section in working {
            var kept: [any SearchResultItem] = []
            for item in section.items {
                if let key = item.deduplicationKey {
                    guard seenDeduplicatedKeys.insert(key).inserted else { continue }
                }
                kept.append(item)
                if kept.count >= section.itemCap { break }
            }
            if !kept.isEmpty {
                result.append(section.replacingItems(kept))
            }
        }
        
        return ComposedSearchResult(sections: result)
    }

    private func mergingSectionsWithSameID(_ sections: [SearchResultSection]) -> [SearchResultSection] {
        var orderOfFirstAppearance: [SearchSectionID] = []
        var merged: [SearchSectionID: SearchResultSection] = [:]
        for section in sections {
            if let existing = merged[section.id] {
                merged[section.id] = existing.replacingItems(existing.items + section.items)
            } else {
                merged[section.id] = section
                orderOfFirstAppearance.append(section.id)
            }
        }
        return orderOfFirstAppearance.compactMap { merged[$0] }
    }
    
    private func composeRecentSearchesSuggestionsAndGoogle(_ sections: [SearchResultSection], query: SearchQuery) -> [SearchResultSection]? {
        let tag = recentSearchTag
        let all = RecentSearchStore.shared.items.filter { $0.tag == tag }
        
        // For empty query we will add all items as "Recent Searches"
        if query.isEmpty {
            guard !all.isEmpty else { return nil }

            let headerAction = SearchSectionHeader.Action(title: lang("Clear All")) { [actions] in
                actions.clearRecentSearches(tag)
            }
            let header = SearchSectionHeader(title: lang("Recent Searches"), action: headerAction)
            let items = all.map { RecentSearchResultItem(text: $0.text, actions: actions, isCompact: false) }
            return [
                .init(
                    id: .recentSearches,
                    order: SearchSectionOrder.recentSearchesEmpty,
                    header: header,
                    items: items
                )
            ]
        }
        
        var result: [SearchResultSection] = []
        let queryText = query.text
        
        // Suggestions
        let keyword = query.keyword
        let suggestions = all
            .filter { $0.text.lowercased().contains(keyword) && $0.text != queryText }
            .sorted { a, b in a.text.lowercased().hasPrefix(keyword) && !b.text.lowercased().hasPrefix(keyword) }
            .map { SuggestedSearchResultItem(text: $0.text, actions: actions, visitDate: $0.timestamp) }
        if !suggestions.isEmpty {
            result.append(
                .init(
                    id: .suggestions,
                    order: SearchSectionOrder.suggestions,
                    header: SearchSectionHeader(title: lang("Suggestions")),
                    items: suggestions
                )
            )
        }
        
        // Open link, Open in App or Search Google
        let isCompactRepresentation = !result.isEmpty || !sections.isEmpty
        if let openableURL = SearchOpenableURL(query.text) {
            result += SearchResultSection(
                id: .openLink,
                order: SearchSectionOrder.openLink,
                header: SearchSectionHeader(title: openableURL.actionTitle),
                items: [
                    OpenLinkResultItem(openableURL: openableURL, actions: actions, isCompact: isCompactRepresentation)
                ]
            )
        } else {
            result += SearchResultSection(
                id: .searchInGoogle,
                order: SearchSectionOrder.searchInGoogle,
                header: SearchSectionHeader(title: lang("Search in Google")),
                items: [
                    SearchGoogleResultItem(text: queryText, actions: actions, isCompact: isCompactRepresentation)
                ]
            )
        }
        
        return result
    }
    
    private func promoteFirstExactMatch(in working: inout [SearchResultSection]) {
        for sectionIndex in working.indices {
            guard let itemIndex = working[sectionIndex].items.firstIndex(where: { $0.isExactMatch }) else {
                continue
            }
            var items = working[sectionIndex].items
            let promoted = items.remove(at: itemIndex)
            working[sectionIndex] = working[sectionIndex].replacingItems(items)
            working.insert(
                .init(
                    id: .exactMatch,
                    order: SearchSectionOrder.exactMatch,
                    itemCap: 1,
                    header: nil,
                    items: [promoted],
                    isTopMatch: true
                ),
                at: 0
            )
            return
        }
    }
}
