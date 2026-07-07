import WalletContext
import WalletCore

@MainActor
final class SitesAndDappsSearchProvider: SingleShotSearchProvider {
    private let exploreVM: ExploreVM
    private let actions: ExploreSearchActions

    init(exploreVM: ExploreVM, actions: ExploreSearchActions) {
        self.exploreVM = exploreVM
        self.actions = actions
    }

    func search(_ query: SearchQuery) async -> [SearchResultSection] {
        guard !query.isEmpty else { return [] }
        let keyword = query.keyword

        let connectedDapps = Array(exploreVM.connectedDapps.values)
        var sites = exploreVM.exploreSites.values.apply(Array.init)
        if query.shouldRestrictSites {
            sites = sites.filter { !$0.canBeRestricted }
        }

        let matchingDapps = connectedDapps
            .filter { $0.matches(query.text) }
            .map { ExploreSearchResultItem(source: .connectedDapp($0)) }
        let matchingSites = sites
            .filter { $0.matches(query.text) }
            .map { ExploreSearchResultItem(source: .site($0)) }

        var seen = Set<String>()
        let combined = (matchingDapps + matchingSites)
            .filter { seen.insert($0.id).inserted }
            .sorted { a, b in a.prefixMatches(keyword: keyword) && !b.prefixMatches(keyword: keyword) }
            .map { ResultSearchItem(payload: $0, isExactMatch: false, actions: actions) }

        return combined.isEmpty ? [] : [
            .init(id: .sitesAndDapps,
                order: SearchSectionOrder.sitesAndDapps,
                header: SearchSectionHeader(title: lang("Popular and connected apps")),
                items: combined
            )
        ]
    }
}

private extension ApiSite {
    func matches(_ searchString: String) -> Bool {
        let s = searchString.lowercased()
        return name.lowercased().contains(s)
            || description.lowercased().contains(s)
            || SearchURLMatching.urlContains(url, searchText: s)
    }
}

private extension ApiDapp {
    func matches(_ searchString: String) -> Bool {
        let searchString = searchString.lowercased()
        return name.lowercased().contains(searchString) || SearchURLMatching.urlContains(url, searchText: searchString)
    }
}
