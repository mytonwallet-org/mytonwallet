import AppIntents
import CoreSpotlight
import Foundation
import WalletContext

@available(iOS 18.4, *)
public struct TokenEntity: AppEntity, Identifiable, Sendable, Hashable, Codable {
    public static let typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Token"))
    public static let defaultQuery = TokenEntityQuery()

    public let id: String
    public var tokenSlug: String

    @Property(indexingKey: \.displayName)
    public var name: String

    @Property(customIndexingKey: CSCustomAttributeKey(keyName: "ticker", searchable: true, searchableByDefault: true, unique: false, multiValued: false)!)
    public var symbol: String
    public var chainRawValue: String
    public var chainTitle: String
    public var tokenAddress: String?
    public var decimals: Int

    @Property(indexingKey: \.contentDescription)
    public var contentDescription: String

    @Property(indexingKey: \.keywords)
    public var searchableKeywords: [String]

    public var displayRepresentation: DisplayRepresentation {
        .init(title: "\(symbol)", subtitle: "\(name) - \(chainTitle)")
    }

    public init(
        tokenSlug: String,
        name: String,
        symbol: String,
        chainRawValue: String,
        chainTitle: String,
        tokenAddress: String?,
        decimals: Int,
        contentDescription: String,
        searchableKeywords: [String]
    ) {
        self.id = tokenSlug
        self.tokenSlug = tokenSlug
        self.chainRawValue = chainRawValue
        self.chainTitle = chainTitle
        self.tokenAddress = tokenAddress
        self.decimals = decimals
        self.name = name
        self.symbol = symbol
        self.contentDescription = contentDescription
        self.searchableKeywords = searchableKeywords
    }

    public init(token: ApiToken) {
        let name = token.name.nilIfEmpty ?? token.slug
        let symbol = token.symbol.nilIfEmpty ?? token.slug
        let chainTitle = token.chain.title.nilIfEmpty ?? token.chain.rawValue.uppercased()
        let searchableKeywords = ([name, symbol, token.slug, chainTitle, token.tokenAddress].compactMap { $0 } + (token.keywords ?? []))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        self.init(
            tokenSlug: token.slug,
            name: name,
            symbol: symbol,
            chainRawValue: token.chain.rawValue,
            chainTitle: chainTitle,
            tokenAddress: token.tokenAddress,
            decimals: token.decimals,
            contentDescription: "\(name) \(symbol) \(chainTitle)",
            searchableKeywords: searchableKeywords
        )
    }

    public var apiTokenFallback: ApiToken {
        ApiToken(
            slug: tokenSlug,
            name: name,
            symbol: symbol,
            decimals: decimals,
            chain: ApiChain(rawValue: chainRawValue) ?? getChainBySlug(tokenSlug) ?? FALLBACK_CHAIN,
            tokenAddress: tokenAddress
        )
    }

    public func matchesSearch(_ query: String) -> Bool {
        let query = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if name.lowercased().contains(query) { return true }
        if symbol.lowercased().contains(query) { return true }
        if tokenSlug.lowercased().contains(query) { return true }
        if chainTitle.lowercased().contains(query) { return true }
        if tokenAddress?.lowercased().contains(query) == true { return true }
        return searchableKeywords.contains { $0.lowercased().contains(query) }
    }

    public static func == (lhs: TokenEntity, rhs: TokenEntity) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

@available(iOS 18.4, *)
public struct TokenEntityQuery: EntityStringQuery {
    public init() {}

    public func entities(for identifiers: [TokenEntity.ID]) async throws -> [TokenEntity] {
        let tokens = await loadTokens(tryRemote: false)
        let tokensBySlug = Dictionary(uniqueKeysWithValues: tokens.map { ($0.slug, $0) })
        return identifiers.map { identifier in
            TokenEntity.resolve(tokenSlug: identifier, tokensBySlug: tokensBySlug)
        }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<TokenEntity> {
        let tokens = await loadTokens(tryRemote: false)
            .filter { ($0.priceUsd ?? 0) != 0 }
            .filter { $0.isPopular == true }
            .map(TokenEntity.init(token:))
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("Popular"), items: tokens)
        }
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<TokenEntity> {
        let query = string.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = await loadTokens(tryRemote: false)
            .filter { ($0.priceUsd ?? 0) != 0 }
            .filter { $0.matchesSearch(query) }
            .map(TokenEntity.init(token:))
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("All Tokens"), items: tokens)
        }
    }

    private func loadTokens(tryRemote: Bool) async -> [ApiToken] {
        let store = SharedStore()
        await store.reloadCache()
        let tokens = await store.tokensDictionary(tryRemote: tryRemote)
        return Array(tokens.values)
    }
}

@available(iOS 18.4, *)
public extension TokenEntity {
    static func resolve(tokenSlug: String, tokensBySlug: [String: ApiToken] = [:]) -> TokenEntity {
        if let token = tokensBySlug[tokenSlug] ?? ApiToken.defaultTokens[tokenSlug] ?? nativeToken(slug: tokenSlug) {
            return TokenEntity(token: token)
        }
        return TokenEntity(token: .unknown(slug: tokenSlug))
    }

    static func nativeToken(slug: String) -> ApiToken? {
        ApiChain.allCases.first { $0.nativeToken.slug == slug }?.nativeToken
    }
}

@available(iOS 18.4, *)
extension TokenEntity: IndexedEntity {
    public var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet()
        attributes.contentDescription = contentDescription
        attributes.keywords = searchableKeywords
        return attributes
    }
}
