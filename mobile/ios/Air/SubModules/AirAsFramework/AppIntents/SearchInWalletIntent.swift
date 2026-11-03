import AppIntents

@available(iOS 27.0, *)
@AppIntent(schema: .system.searchInApp)
public struct SearchInWalletIntent: ShowInAppSearchResultsIntent {
    public static let title: LocalizedStringResource = "Search"
    public static let searchScopes: [StringSearchScope] = [.general]

    @Parameter(title: "Search")
    public var criteria: StringSearchCriteria

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult {
        AirLauncher.handle(systemAction: .search(query: criteria.term))
        return .result()
    }
}
