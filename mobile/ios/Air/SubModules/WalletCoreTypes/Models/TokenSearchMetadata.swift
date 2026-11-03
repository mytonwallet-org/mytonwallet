import Foundation
import UniversalSearchCore

/// The same token vocabulary is used by in-app search and system entity queries.
public enum TokenSearchMetadata {
    public static func fields(for token: ApiToken, displayName: String? = nil) -> [SearchField] {
        var candidates: [(String?, SearchFieldKind, SearchFieldMatchPolicy)] = [
            (displayName ?? token.name, .title, .text),
            (token.name, .alias, .text),
            (token.localizedName, .alias, .text),
            (token.symbol, .symbol, .text),
            (token.slug, .identifier, .exact),
            (token.tokenAddress, .address, .exact),
            (token.label, .alias, .text),
            (token.chain.title, .keyword, .text),
            (token.chain.rawValue, .keyword, .text),
        ]
        candidates += (token.keywords ?? []).map { (Optional($0), .keyword, .text) }
        var seen = Set<SearchField>()
        return candidates.compactMap { value, kind, policy in
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            let field = SearchField(value, kind: kind, matchPolicy: policy)
            return seen.insert(field).inserted ? field : nil
        }
    }

    public static func matchingTokens(_ query: String, tokens: [ApiToken]) -> [ApiToken] {
        let bySlug = Dictionary(tokens.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let documents = bySlug.values.map { token in
            SearchDocument(
                id: SearchEntityID(token.slug),
                kind: token.isRwaStock ? .stock : .token,
                fields: fields(for: token),
                signals: SearchSignals(traits: token.isPopular == true ? [.popular] : [])
            )
        }
        return UniversalSearchEngine().search(query, in: UniversalSearchIndex(documents: documents))
            .compactMap { bySlug[$0.document.id.rawValue] }
    }
}
