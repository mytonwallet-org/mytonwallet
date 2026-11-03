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
    public var imageURL: String?
    public var localizedName: String?
    public var label: String?
    public var tokenKeywords: [String]?
    public var tokenType: ApiTokenType?
    public var decimals: Int

    // Prepared for a donation only; image bytes are not part of the persisted catalog.
    var indexedThumbnailData: Data?

    @Property(indexingKey: \.contentDescription)
    public var contentDescription: String

    @Property(indexingKey: \.keywords)
    public var searchableKeywords: [String]

    public var displayRepresentation: DisplayRepresentation {
        if let data = indexedThumbnailData ?? TokenEntityImage.bundledData(tokenSlug: tokenSlug) {
            return .init(title: "\(name)", subtitle: "\(contentDescription)", image: .init(data: data))
        }
        if #available(iOS 27.0, *) {
            let imageURL = imageURL
            let tokenSlug = tokenSlug
            return .init(title: "\(name)", subtitle: "\(contentDescription)") {
                await TokenEntityImage.load(imageURL, tokenSlug: tokenSlug)
            }
        }
        return .init(title: "\(name)", subtitle: "\(contentDescription)", image: .init(systemName: "circle.hexagongrid"))
    }

    public init(
        tokenSlug: String,
        name: String,
        symbol: String,
        chainRawValue: String,
        chainTitle: String,
        tokenAddress: String?,
        decimals: Int,
        searchableKeywords: [String],
        imageURL: String? = nil
    ) {
        self.imageURL = imageURL
        self.id = tokenSlug
        self.tokenSlug = tokenSlug
        self.chainRawValue = chainRawValue
        self.chainTitle = chainTitle
        self.tokenAddress = tokenAddress
        self.decimals = decimals
        self.name = name
        self.symbol = symbol
        var seen = Set([name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()])
        self.contentDescription = [symbol, chainTitle]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            .joined(separator: " · ")
        self.searchableKeywords = searchableKeywords
    }

    public init(token: ApiToken) {
        let name = token.name.nilIfEmpty ?? token.slug
        let symbol = token.symbol.nilIfEmpty ?? token.slug
        let chainTitle = token.chain.title.nilIfEmpty ?? token.chain.rawValue.uppercased()
        let searchableKeywords = Array(Set(TokenSearchMetadata.fields(for: token).map(\.value))).sorted()

        self.init(
            tokenSlug: token.slug,
            name: name,
            symbol: symbol,
            chainRawValue: token.chain.rawValue,
            chainTitle: chainTitle,
            tokenAddress: token.tokenAddress,
            decimals: token.decimals,
            searchableKeywords: searchableKeywords,
            imageURL: token.image
        )
        localizedName = token.localizedName
        label = token.label
        tokenKeywords = token.keywords
        tokenType = token.type
    }

    public var apiTokenFallback: ApiToken {
        ApiToken(
            slug: tokenSlug,
            name: name,
            localizedName: localizedName,
            symbol: symbol,
            decimals: decimals,
            chain: ApiChain(rawValue: chainRawValue) ?? getChainBySlug(tokenSlug) ?? FALLBACK_CHAIN,
            type: tokenType,
            tokenAddress: tokenAddress,
            image: imageURL,
            keywords: tokenKeywords,
            label: label
        )
    }

    public func matchesSearch(_ query: String) -> Bool {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !TokenSearchMetadata.matchingTokens(query, tokens: [apiTokenFallback]).isEmpty
    }

    // Persist the metadata values, not App Intents' process-local @Property containers.
    private enum CodingKeys: String, CodingKey {
        case tokenSlug, name, symbol, chainRawValue, chainTitle, decimals, contentDescription, searchableKeywords, tokenAddress, imageURL, localizedName, label, tokenKeywords, tokenType
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tokenSlug: try values.decode(String.self, forKey: .tokenSlug),
            name: try values.decode(String.self, forKey: .name),
            symbol: try values.decode(String.self, forKey: .symbol),
            chainRawValue: try values.decode(String.self, forKey: .chainRawValue),
            chainTitle: try values.decode(String.self, forKey: .chainTitle),
            tokenAddress: try values.decodeIfPresent(String.self, forKey: .tokenAddress),
            decimals: try values.decode(Int.self, forKey: .decimals),
            searchableKeywords: try values.decode([String].self, forKey: .searchableKeywords),
            imageURL: try values.decodeIfPresent(String.self, forKey: .imageURL)
        )
        localizedName = try values.decodeIfPresent(String.self, forKey: .localizedName)
        label = try values.decodeIfPresent(String.self, forKey: .label)
        tokenKeywords = try values.decodeIfPresent([String].self, forKey: .tokenKeywords)
        tokenType = try values.decodeIfPresent(ApiTokenType.self, forKey: .tokenType)
    }

    public func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(tokenSlug, forKey: .tokenSlug)
        try values.encode(name, forKey: .name)
        try values.encode(symbol, forKey: .symbol)
        try values.encode(chainRawValue, forKey: .chainRawValue)
        try values.encode(chainTitle, forKey: .chainTitle)
        try values.encode(decimals, forKey: .decimals)
        try values.encode(contentDescription, forKey: .contentDescription)
        try values.encode(searchableKeywords, forKey: .searchableKeywords)
        try values.encodeIfPresent(tokenAddress, forKey: .tokenAddress)
        try values.encodeIfPresent(imageURL, forKey: .imageURL)
        try values.encodeIfPresent(localizedName, forKey: .localizedName)
        try values.encodeIfPresent(label, forKey: .label)
        try values.encodeIfPresent(tokenKeywords, forKey: .tokenKeywords)
        try values.encodeIfPresent(tokenType, forKey: .tokenType)
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
        let tokensBySlug = await loadTokens()
        return identifiers.compactMap { identifier in
            tokensBySlug[identifier].map(TokenEntity.init(token:))
        }
    }

    public func suggestedEntities() async throws -> IntentItemCollection<TokenEntity> {
        let tokens = await TokenSpotlightStore.shared.entities()
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("Tokens"), items: tokens)
        }
    }

    public func entities(matching string: String) async throws -> IntentItemCollection<TokenEntity> {
        let tokens = TokenSearchMetadata.matchingTokens(string, tokens: Array(await loadTokens().values))
            .map(TokenEntity.init(token:))
        return IntentItemCollection {
            ItemSection(LocalizedStringResource("All Tokens"), items: tokens)
        }
    }

    private func loadTokens() async -> [String: ApiToken] {
        let store = SharedStore()
        await store.reloadCache()
        var tokens = await store.tokensDictionary()
        for entity in await TokenSpotlightStore.shared.entities() where tokens[entity.id] == nil {
            tokens[entity.id] = entity.apiTokenFallback
        }
        for chain in ApiChain.allCases where tokens[chain.nativeToken.slug] == nil {
            tokens[chain.nativeToken.slug] = chain.nativeToken
        }
        return tokens
    }
}

@available(iOS 18.4, *)
public extension TokenEntity {
    static func resolve(
        tokenSlug: String,
        tokensBySlug: [String: ApiToken] = [:]
    ) -> TokenEntity {
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
        let attributes = defaultAttributeSet
        attributes.title = name
        attributes.contentDescription = contentDescription
        attributes.keywords = searchableKeywords
        if let data = indexedThumbnailData ?? TokenEntityImage.bundledData(tokenSlug: tokenSlug) {
            attributes.thumbnailData = data
        }
        return attributes
    }
}

@available(iOS 27.0, *)
extension TokenEntityQuery: IndexedEntityQuery {
    public func reindexEntities(for identifiers: [TokenEntity.ID], indexDescription: CSSearchableIndexDescription) async throws {
        try await TokenSpotlightStore.shared.reindex(identifiers: identifiers)
    }

    public func reindexAllEntities(indexDescription: CSSearchableIndexDescription) async throws {
        try await TokenSpotlightStore.shared.reindex()
    }
}
