import UniversalSearchCore
import WalletCore
import WalletCoreTypes

/// Ranks a caller's token candidates with the same fields, signals and policy as Universal Search.
public struct WalletCoreTokenSearch {
    private var index = UniversalSearchIndex()
    private let engine = UniversalSearchEngine()
    private let interactionStore: WalletCoreSearchInteractionStore

    public init(interactionStore: WalletCoreSearchInteractionStore = .shared) {
        self.interactionStore = interactionStore
    }

    public mutating func update(
        accountID: String,
        tokens: [ApiToken],
        balances: [MTokenBalance],
        trackedTokenSlugs: Set<String>
    ) {
        let documents = WalletCoreTokenSearchDocuments.documents(
            tokens: tokens,
            balances: balances,
            trackedTokenSlugs: trackedTokenSlugs,
            interactions: interactionStore.records(scopeID: accountID)
        )
        index = UniversalSearchIndex(documents: documents, reusing: index)
    }

    public func search(_ query: String) -> [String] {
        engine.search(query, in: index).compactMap {
            $0.document.attributeValue(for: WalletCoreSearchAttributeKey.tokenSlug)
        }
    }

    public func recordSelection(tokenSlug: String, accountID: String) {
        interactionStore.recordSelection(
            of: WalletCoreTokenSearchDocuments.entityID(tokenSlug: tokenSlug),
            scopeID: accountID
        )
    }
}
