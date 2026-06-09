import Foundation
import WalletContext

private let log = Log("ExploreSearchCoordinator")

/// Drives the search pipeline: runs all providers for a query, re-composes the result every time any
/// provider emits (progressive delivery, including intermediate emissions within a single provider),
/// and cancels the prior query's work.
@MainActor
final class ExploreSearchCoordinator {
    private let providers: [SearchProvider]
    private let composer: SearchResultComposer

    private var tasks: [Task<Void, Never>] = []
    private var collected: [[SearchResultSection]] = []
    private var currentQueryID: UInt64 = 0

    var onUpdate: ((ComposedSearchResult) -> Void)?

    init(providers: [SearchProvider], actions: ExploreSearchActions, recentSearchTag: String) {
        self.providers = providers
        self.composer = SearchResultComposer(actions: actions, recentSearchTag: recentSearchTag)
    }

    func search(_ query: SearchQuery) {
        cancel()
        currentQueryID &+= 1
        let queryID = currentQueryID
        collected = Array(repeating: [], count: providers.count)

        for (index, provider) in providers.enumerated() {
            let task = Task { @MainActor [weak self] in
                do {
                    try await provider.search(query) { [weak self] sections in
                        guard let self, !Task.isCancelled, self.currentQueryID == queryID else { return }
                        self.collected[index] = sections
                        let searchResult = self.composer.compose(self.collected.flatMap({ $0 }), query: query)
                        self.onUpdate?(searchResult)
                    }
                } catch {
                    if !(error is CancellationError) {
                        log.error("Provider \(type(of: provider), .public) failed: \(error, .public)")
                    }
                }
            }
            tasks.append(task)
        }
    }

    func cancel() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }
}
